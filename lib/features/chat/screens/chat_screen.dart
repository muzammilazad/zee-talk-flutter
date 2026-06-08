import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/config/app_config.dart';
import '../../../core/state/current_chat_tracker.dart';
import '../../../core/storage/token_storage.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/last_seen_formatter.dart';
import '../../../data/api/messages_api.dart';
import '../../../data/socket/socket_service.dart';
import '../../calls/services/call_manager.dart';
import '../../users/models/contact_user.dart';
import '../models/chat_message.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    required this.contact,
    super.key,
  });

  final ContactUser contact;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final MessagesApi _messagesApi = MessagesApi();
  final SocketService _socketService = SocketService.instance;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];

  String? _currentUserId;
  String? _errorMessage;
  String? _lastSeenAt;
  Timer? _typingTimer;
  Timer? _remoteTypingTimer;
  bool _isLoading = true;
  bool _isSending = false;
  bool _isContactOnline = false;
  bool _isContactTyping = false;
  bool _typingSent = false;

  @override
  void initState() {
    super.initState();
    CurrentChatTracker().openChat(widget.contact.id);
    _lastSeenAt = widget.contact.lastSeenAt;
    _initializeChat();
  }

  Future<void> _initializeChat() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final currentUserId = await TokenStorage().getUserId();
      if (currentUserId == null || currentUserId.isEmpty) {
        throw const MessagesApiException('Current user is unavailable');
      }

      _currentUserId = currentUserId;
      _socketService.removeMessageListener(_handleSocketMessage);
      _socketService.addMessageListener(_handleSocketMessage);
      _socketService.removePresenceListener(_handlePresence);
      _socketService.onPresence(_handlePresence);
      _socketService.offTyping(_handleTyping);
      _socketService.onTyping(_handleTyping);
      _socketService.removeLastSeenListener(_handleLastSeenUpdated);
      _socketService.onLastSeenUpdated(_handleLastSeenUpdated);
      _socketService.removeReadReceiptListener(_handleReadReceipt);
      _socketService.addReadReceiptListener(_handleReadReceipt);
      _socketService.removeMessageStatusListener(_handleMessageStatus);
      _socketService.addMessageStatusListener(_handleMessageStatus);
      await _socketService.connect();

      final timeline = await _messagesApi.getTimeline(widget.contact.id);
      if (!mounted) {
        return;
      }

      setState(() {
        for (final message in timeline) {
          _upsertMessage(message);
        }
        _sortMessages();
      });
      _markIncomingMessagesRead(timeline);
      _scrollToBottom();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _errorMessage = error.toString());
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _handleSocketMessage(ChatMessage message) {
    if (!mounted || !_belongsToConversation(message)) {
      return;
    }

    final isIncoming = message.senderId == widget.contact.id &&
        message.receiverId == _currentUserId;
    final displayedMessage = isIncoming ? message.withStatus('read') : message;
    setState(() {
      _upsertMessage(displayedMessage);
      _sortMessages();
    });
    if (isIncoming) {
      final id = message.id;
      _socketService.markMessagesRead(
        peerId: widget.contact.id,
        messageIds: id == null || id.isEmpty ? const [] : [id],
      );
    }
    _scrollToBottom();
  }

  void _markIncomingMessagesRead(Iterable<ChatMessage> messages) {
    final unreadIds = messages
        .where(
          (message) =>
              message.senderId == widget.contact.id &&
              message.receiverId == _currentUserId &&
              message.status?.toLowerCase() != 'read',
        )
        .map((message) => message.id)
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toList();

    setState(() {
      for (var index = 0; index < _messages.length; index++) {
        final message = _messages[index];
        if (message.senderId == widget.contact.id &&
            message.receiverId == _currentUserId &&
            message.status?.toLowerCase() != 'read') {
          _messages[index] = message.withStatus('read');
        }
      }
    });
    _socketService.markMessagesRead(
      peerId: widget.contact.id,
      messageIds: unreadIds,
    );
  }

  void _handleReadReceipt(String from, List<String> messageIds) {
    if (!mounted) {
      return;
    }

    final ids = messageIds.toSet();
    setState(() {
      for (var index = 0; index < _messages.length; index++) {
        final message = _messages[index];
        final isOutgoing = message.senderId == _currentUserId &&
            message.receiverId == widget.contact.id;
        final matchesIds = message.id != null && ids.contains(message.id);
        final marksConversation = ids.isEmpty && from == widget.contact.id;
        if (isOutgoing && (matchesIds || marksConversation)) {
          _messages[index] = message.withStatus('read');
        }
      }
    });
  }

  void _handleMessageStatus(ChatMessage message) {
    if (!mounted || !_belongsToConversation(message)) {
      return;
    }

    setState(() {
      _upsertMessage(message);
      _sortMessages();
    });
  }

  void _handlePresence(Set<String> onlineUserIds) {
    if (mounted) {
      setState(
        () => _isContactOnline = onlineUserIds.contains(widget.contact.id),
      );
    }
  }

  void _handleTyping(Map<String, dynamic> data) {
    if (data['from']?.toString() != widget.contact.id) {
      return;
    }

    _remoteTypingTimer?.cancel();
    final isTyping = data['isTyping'] == true;
    if (mounted) {
      setState(() => _isContactTyping = isTyping);
    }

    if (isTyping) {
      _remoteTypingTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() => _isContactTyping = false);
        }
      });
    }
  }

  void _handleLastSeenUpdated(String userId, String lastSeenAt) {
    if (mounted && userId == widget.contact.id) {
      setState(() => _lastSeenAt = lastSeenAt);
    }
  }

  bool _belongsToConversation(ChatMessage message) {
    final currentUserId = _currentUserId;
    if (currentUserId == null) {
      return false;
    }

    return (message.senderId == currentUserId &&
            message.receiverId == widget.contact.id) ||
        (message.senderId == widget.contact.id &&
            message.receiverId == currentUserId);
  }

  void _upsertMessage(ChatMessage message) {
    if (!_belongsToConversation(message)) {
      return;
    }

    final id = message.id;
    if (id != null && id.isNotEmpty) {
      final existingIndex = _messages.indexWhere((item) => item.id == id);
      if (existingIndex != -1) {
        _messages[existingIndex] = message;
        return;
      }
    }

    _messages.add(message);
  }

  void _sortMessages() {
    _messages.sort(
      (first, second) => _messageDate(first).compareTo(_messageDate(second)),
    );
  }

  DateTime _messageDate(ChatMessage message) {
    return DateTime.tryParse(message.createdAt ?? message.timestamp ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isSending) {
      return;
    }

    _messageController.clear();
    _stopTyping();
    setState(() => _isSending = true);

    try {
      final message = await _socketService.sendMessage(
        receiverId: widget.contact.id,
        text: text,
      );
      if (!mounted || !_belongsToConversation(message)) {
        return;
      }

      setState(() {
        _upsertMessage(message);
        _sortMessages();
      });
      _scrollToBottom();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  String _messageTime(ChatMessage message) {
    final date = DateTime.tryParse(
      message.createdAt ?? message.timestamp ?? '',
    )?.toLocal();
    if (date == null) {
      return '';
    }

    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  Widget _buildMessageStatusIcon(String? status) {
    switch (status?.trim().toLowerCase()) {
      case 'delivered':
        return const Icon(
          Icons.done_all,
          size: 16,
          color: AppColors.mutedText,
        );
      case 'read':
        return const Icon(
          Icons.done_all,
          size: 16,
          color: Color(0xFF34B7F1),
        );
      case 'failed':
        return const Icon(
          Icons.error_outline,
          size: 16,
          color: Colors.red,
        );
      case 'sent':
      default:
        return const Icon(
          Icons.done,
          size: 16,
          color: AppColors.mutedText,
        );
    }
  }

  String? _avatarUrl() {
    final avatarUrl = widget.contact.avatarUrl;
    if (avatarUrl == null || avatarUrl.trim().isEmpty) {
      return null;
    }

    return Uri.parse(AppConfig.baseUrl).resolve(avatarUrl).toString();
  }

  String _contactInitial() {
    final name = widget.contact.name.trim();
    return name.isEmpty ? '?' : name[0].toUpperCase();
  }

  String _contactSubtitle() {
    return formatLastSeen(_lastSeenAt);
  }

  String _headerSubtitle() {
    if (_isContactTyping) {
      return 'typing...';
    }
    if (_isContactOnline) {
      return 'online';
    }
    return _contactSubtitle();
  }

  Color _headerSubtitleColor() {
    return _isContactTyping || _isContactOnline
        ? AppColors.onlineGreen
        : AppColors.mutedText;
  }

  void _handleInputChanged(String value) {
    _typingTimer?.cancel();
    if (value.trim().isEmpty) {
      _stopTyping();
      return;
    }

    if (!_typingSent) {
      _typingSent = true;
      _socketService.sendTyping(
        to: widget.contact.id,
        isTyping: true,
      );
    }

    _typingTimer = Timer(
      const Duration(milliseconds: 1500),
      _stopTyping,
    );
  }

  void _stopTyping() {
    _typingTimer?.cancel();
    _typingTimer = null;
    if (!_typingSent) {
      return;
    }

    _typingSent = false;
    _socketService.sendTyping(
      to: widget.contact.id,
      isTyping: false,
    );
  }

  void _startCall(String callType) {
    CallManager().startOutgoingCall(
      contact: widget.contact,
      callType: callType,
    );
  }

  Widget _buildContactAvatar({double radius = 21}) {
    final avatarUrl = _avatarUrl();

    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.mintAvatar,
      backgroundImage: widget.contact.isOfficialSupport || avatarUrl == null
          ? null
          : NetworkImage(avatarUrl),
      child: widget.contact.isOfficialSupport
          ? Icon(
              Icons.headset_mic_outlined,
              color: AppColors.primaryGreen,
              size: radius,
            )
          : avatarUrl == null
              ? Text(
                  _contactInitial(),
                  style: const TextStyle(
                    color: AppColors.primaryGreen,
                    fontWeight: FontWeight.w700,
                  ),
                )
              : null,
    );
  }

  Widget _buildHeaderIcon({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      color: AppColors.mutedText,
      icon: Icon(icon),
    );
  }

  Widget _buildChatHeader() {
    return Container(
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: const BoxDecoration(
        color: AppColors.headerBackground,
        border: Border(
          bottom: BorderSide(color: AppColors.border),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.maybePop(context),
            tooltip: 'Back',
            color: AppColors.primaryGreen,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          _buildContactAvatar(),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.contact.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.darkText,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _headerSubtitle(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _headerSubtitleColor(),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          _buildHeaderIcon(
            icon: Icons.call_outlined,
            tooltip: 'Audio call',
            onPressed: () => _startCall('voice'),
          ),
          _buildHeaderIcon(
            icon: Icons.videocam_outlined,
            tooltip: 'Video call',
            onPressed: () => _startCall('video'),
          ),
        ],
      ),
    );
  }

  Widget _buildMessage(ChatMessage message) {
    final isOwnMessage = message.senderId == _currentUserId;
    final messageTime = _messageTime(message);

    return Align(
      alignment: isOwnMessage ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.75,
        ),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isOwnMessage ? AppColors.outgoingBubble : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isOwnMessage ? 16 : 4),
            bottomRight: Radius.circular(isOwnMessage ? 4 : 16),
          ),
          border: Border.all(
            color: isOwnMessage ? const Color(0xFFC8EFC2) : AppColors.border,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0D111827),
              blurRadius: 4,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                message.displayText,
                style: const TextStyle(
                  color: AppColors.darkText,
                  fontSize: 16,
                ),
              ),
            ),
            if (messageTime.isNotEmpty || isOwnMessage) ...[
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (messageTime.isNotEmpty)
                    Text(
                      messageTime,
                      style: const TextStyle(
                        color: AppColors.mutedText,
                        fontSize: 11,
                      ),
                    ),
                  if (messageTime.isNotEmpty && isOwnMessage)
                    const SizedBox(width: 3),
                  if (isOwnMessage) _buildMessageStatusIcon(message.status),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTimeline() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _initializeChat,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_messages.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'No messages yet',
              style: TextStyle(
                color: AppColors.darkText,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 7),
            Text(
              'Send a message to start the conversation',
              style: TextStyle(color: AppColors.mutedText),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _messages.length,
      itemBuilder: (context, index) => _buildMessage(_messages[index]),
    );
  }

  @override
  void dispose() {
    CurrentChatTracker().closeChat(widget.contact.id);
    _stopTyping();
    _remoteTypingTimer?.cancel();
    _socketService.removeMessageListener(_handleSocketMessage);
    _socketService.removePresenceListener(_handlePresence);
    _socketService.offTyping(_handleTyping);
    _socketService.removeLastSeenListener(_handleLastSeenUpdated);
    _socketService.removeReadReceiptListener(_handleReadReceipt);
    _socketService.removeMessageStatusListener(_handleMessageStatus);
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.chatBackground,
      body: SafeArea(
        child: Column(
          children: [
            _buildChatHeader(),
            Expanded(child: _buildTimeline()),
            Container(
              decoration: const BoxDecoration(
                color: AppColors.headerBackground,
                border: Border(
                  top: BorderSide(color: AppColors.border),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Attachments will be added next'),
                          ),
                        );
                      },
                      tooltip: 'Attach',
                      color: AppColors.mutedText,
                      icon: const Icon(Icons.attach_file_rounded),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        textCapitalization: TextCapitalization.sentences,
                        textInputAction: TextInputAction.send,
                        onChanged: _handleInputChanged,
                        onSubmitted: (_) => _sendMessage(),
                        decoration: const InputDecoration(
                          hintText: 'Type a message',
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Material(
                      color: AppColors.primaryGreen,
                      shape: const CircleBorder(),
                      child: IconButton(
                        onPressed: _isSending ? null : _sendMessage,
                        color: Colors.white,
                        icon: _isSending
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.send_rounded),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
