import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/config/app_config.dart';
import '../../../core/notifications/local_notification_service.dart';
import '../../../core/state/current_chat_tracker.dart';
import '../../../core/storage/token_storage.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/api/conversations_api.dart';
import '../../../data/api/users_api.dart';
import '../../../data/socket/socket_service.dart';
import '../../auth/screens/login_screen.dart';
import '../../calls/services/call_manager.dart';
import '../../chat/models/chat_message.dart';
import '../../chat/screens/chat_screen.dart';
import '../../contacts/screens/add_contact_screen.dart';
import '../../contacts/screens/requests_screen.dart';
import '../models/contact_user.dart';

class UserListScreen extends StatefulWidget {
  const UserListScreen({super.key});

  @override
  State<UserListScreen> createState() => _UserListScreenState();
}

class _UserListScreenState extends State<UserListScreen> {
  final UsersApi _usersApi = UsersApi();
  final ConversationsApi _conversationsApi = ConversationsApi();
  final SocketService _socketService = SocketService.instance;
  List<ContactUser> _contacts = [];
  Map<String, int> _unreadCounts = {};
  Map<String, String> _latestPreviews = {};
  final Set<String> _processedMessageIds = {};
  Set<String> _onlineUserIds = {};
  String? _currentUserId;
  String? _openChatPeerId;
  String _currentUserName = '';
  String? _errorMessage;
  bool _isLoading = true;
  int _realtimeRevision = 0;

  @override
  void initState() {
    super.initState();
    _loadCurrentUserName();
    _loadContacts();
    _loadSummaries();
    _initializeRealtime();
    _socketService.onLastSeenUpdated(_handleLastSeenUpdated);
  }

  Future<void> _initializeRealtime() async {
    _currentUserId = await TokenStorage().getUserId();
    _socketService.addMessageListener(_handleRealtimeMessage);
    _socketService.onPresence(_handlePresence);
    try {
      await _socketService.connect();
      await CallManager().initialize();
    } catch (error) {
      debugPrint('Presence connection failed: $error');
    }
  }

  void _handleRealtimeMessage(ChatMessage message) {
    final currentUserId = _currentUserId;
    if (!mounted || currentUserId == null || currentUserId.isEmpty) {
      return;
    }

    final messageId = message.id;
    if (messageId != null && messageId.isNotEmpty) {
      if (_processedMessageIds.contains(messageId)) {
        return;
      }
      _processedMessageIds.add(messageId);
    }

    final isOutgoing = message.senderId == currentUserId;
    final peerId = isOutgoing ? message.receiverId : message.senderId;
    if (peerId == null || peerId.isEmpty) {
      return;
    }

    final preview = _messagePreview(message);
    setState(() {
      _realtimeRevision++;
      if (preview.isNotEmpty) {
        _latestPreviews[peerId] = preview;
      }
      if (!isOutgoing && _openChatPeerId != peerId) {
        _unreadCounts[peerId] = (_unreadCounts[peerId] ?? 0) + 1;
      }
    });

    if (!isOutgoing && !CurrentChatTracker().isChatOpen(peerId)) {
      unawaited(
        LocalNotificationService().showMessageNotification(
          title: _contactName(peerId),
          body: preview.isEmpty ? 'New message' : preview,
          payload: peerId,
        ),
      );
    }
  }

  String _contactName(String userId) {
    for (final contact in _contacts) {
      if (contact.id == userId) {
        final name = contact.name.trim();
        return name.isEmpty ? 'Zee Talk' : name;
      }
    }
    return 'Zee Talk';
  }

  String _messagePreview(ChatMessage message) {
    final text = message.displayText.trim();
    if (text.isNotEmpty) {
      return text;
    }
    return message.type?.toLowerCase().contains('call') == true ? 'Call' : '';
  }

  void _handlePresence(Set<String> onlineUserIds) {
    if (mounted) {
      setState(() => _onlineUserIds = onlineUserIds);
    }
  }

  void _handleLastSeenUpdated(String userId, String lastSeenAt) {
    if (!mounted) {
      return;
    }

    setState(() {
      _contacts = _contacts
          .map(
            (contact) => contact.id == userId
                ? contact.withLastSeenAt(lastSeenAt)
                : contact,
          )
          .toList();
    });
  }

  Future<void> _loadCurrentUserName() async {
    final name = await TokenStorage().getUserName();
    if (mounted) {
      setState(() => _currentUserName = name?.trim() ?? '');
    }
  }

  Future<void> _loadContacts() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final contacts = await _usersApi.getContacts();
      if (!mounted) {
        return;
      }
      setState(() => _contacts = contacts);
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

  Future<void> _loadSummaries() async {
    final revisionAtStart = _realtimeRevision;
    try {
      final summaries = await _conversationsApi.getSummary();
      if (!mounted) {
        return;
      }

      final unreadCounts = <String, int>{};
      final latestPreviews = <String, String>{};
      final summaryMessageIds = <String>{};
      for (final summary in summaries) {
        unreadCounts[summary.peerId] = summary.unreadCount;
        final preview = summary.latestText?.trim();
        if (preview != null && preview.isNotEmpty) {
          latestPreviews[summary.peerId] = preview;
        }
        final latestId = summary.latestId;
        if (latestId != null && latestId.isNotEmpty) {
          summaryMessageIds.add(latestId);
        }
      }

      setState(() {
        if (_realtimeRevision != revisionAtStart) {
          unreadCounts.addAll(_unreadCounts);
          latestPreviews.addAll(_latestPreviews);
        }
        _unreadCounts = unreadCounts;
        _latestPreviews = latestPreviews;
        _processedMessageIds.addAll(summaryMessageIds);
      });
    } catch (error) {
      debugPrint('Conversation summary load failed: $error');
    }
  }

  Future<void> _refreshHomeData() async {
    await Future.wait([
      _loadContacts(),
      _loadSummaries(),
    ]);
  }

  Future<void> _logout(BuildContext context) async {
    CallManager().dispose();
    _socketService.removeMessageListener(_handleRealtimeMessage);
    _socketService.removePresenceListener(_handlePresence);
    _socketService.removeLastSeenListener(_handleLastSeenUpdated);
    _socketService.disconnect();
    await TokenStorage().clear();

    if (!context.mounted) {
      return;
    }
    await Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute<void>(
        builder: (_) => const LoginScreen(),
      ),
      (route) => false,
    );
  }

  void _showComingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature coming soon')),
    );
  }

  Future<void> _openAddContact() async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => const AddContactScreen(),
      ),
    );
    if (mounted) {
      await _refreshHomeData();
    }
  }

  Future<void> _openRequests() async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => const RequestsScreen(),
      ),
    );
    if (mounted) {
      await _refreshHomeData();
    }
  }

  Future<void> _openChat(ContactUser contact) async {
    setState(() {
      _openChatPeerId = contact.id;
      _unreadCounts[contact.id] = 0;
    });
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(contact: contact),
      ),
    );
    if (mounted) {
      setState(() => _openChatPeerId = null);
      await _refreshHomeData();
    }
  }

  String? _avatarUrl(ContactUser contact) {
    final avatarUrl = contact.avatarUrl;
    if (avatarUrl == null || avatarUrl.trim().isEmpty) {
      return null;
    }

    return Uri.parse(AppConfig.baseUrl).resolve(avatarUrl).toString();
  }

  String _initial(String name) {
    final trimmedName = name.trim();
    return trimmedName.isEmpty ? '?' : trimmedName[0].toUpperCase();
  }

  Widget _buildHeaderButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppColors.softButton,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 42,
            height: 42,
            child: Icon(
              icon,
              size: 21,
              color: AppColors.primaryGreen,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 24,
            backgroundColor: AppColors.mintAvatar,
            child: Text(
              'ZT',
              style: TextStyle(
                color: AppColors.primaryGreen,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Zee Talk',
                  style: TextStyle(
                    color: AppColors.darkText,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _currentUserName.isEmpty ? 'Welcome back' : _currentUserName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.mutedText,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          _buildHeaderButton(
            icon: Icons.settings_outlined,
            tooltip: 'Settings',
            onPressed: () => _showComingSoon('Settings'),
          ),
          const SizedBox(width: 9),
          CircleAvatar(
            radius: 21,
            backgroundColor: AppColors.mintAvatar,
            child: Text(
              _initial(_currentUserName),
              style: const TextStyle(
                color: AppColors.primaryGreen,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 9),
          _buildHeaderButton(
            icon: Icons.logout,
            tooltip: 'Logout',
            onPressed: () => _logout(context),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: AppColors.lightGrey,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: AppColors.mutedText),
              const SizedBox(width: 5),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.darkText,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChatControls() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 0),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Chats',
                  style: TextStyle(
                    color: AppColors.darkText,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _buildActionButton(
                icon: Icons.person_add_alt_1_outlined,
                label: 'Add Contact',
                onPressed: _openAddContact,
              ),
              const SizedBox(width: 8),
              _buildActionButton(
                icon: Icons.notifications_none,
                label: 'Requests',
                onPressed: _openRequests,
              ),
            ],
          ),
          const SizedBox(height: 16),
          const TextField(
            decoration: InputDecoration(
              hintText: 'Search contacts',
              prefixIcon: Icon(Icons.search),
              filled: true,
              fillColor: AppColors.lightGrey,
              contentPadding: EdgeInsets.symmetric(vertical: 13),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(13)),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(13)),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(13)),
                borderSide: BorderSide(
                  color: AppColors.primaryGreen,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _buildContactAvatar(ContactUser contact) {
    final avatarUrl = _avatarUrl(contact);

    return CircleAvatar(
      radius: 27,
      backgroundColor: AppColors.mintAvatar,
      backgroundImage: contact.isOfficialSupport || avatarUrl == null
          ? null
          : NetworkImage(avatarUrl),
      child: contact.isOfficialSupport
          ? const Icon(
              Icons.headset_mic_outlined,
              color: AppColors.primaryGreen,
              size: 25,
            )
          : avatarUrl == null
              ? Text(
                  _initial(contact.name),
                  style: const TextStyle(
                    color: AppColors.primaryGreen,
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                )
              : null,
    );
  }

  Widget _buildOfficialBadge() {
    return Container(
      margin: const EdgeInsets.only(left: 7),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.mintAvatar,
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Text(
        'Official Support',
        style: TextStyle(
          color: AppColors.primaryGreen,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildContactItem(ContactUser contact) {
    final isOnline = _onlineUserIds.contains(contact.id) ||
        _onlineUserIds.contains(contact.id.toString());
    final latestPreview = _latestPreviews[contact.id]?.trim();
    final hasPreview = latestPreview != null && latestPreview.isNotEmpty;
    final unreadCount = _unreadCounts[contact.id] ?? 0;

    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: () => _openChat(contact),
        splashColor: AppColors.mintAvatar.withOpacity(0.45),
        highlightColor: const Color(0xFFF2FFFB),
        child: Container(
          constraints: const BoxConstraints(minHeight: 76),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AppColors.homeBorder),
            ),
          ),
          child: Row(
            children: [
              _buildContactAvatar(contact),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            contact.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.darkText,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (contact.isOfficialSupport) _buildOfficialBadge(),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      hasPreview
                          ? latestPreview
                          : isOnline
                              ? 'Online'
                              : 'Offline',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: !hasPreview && isOnline
                            ? AppColors.onlineGreen
                            : AppColors.mutedText,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (unreadCount > 0) ...[
                    Container(
                      constraints: const BoxConstraints(
                        minWidth: 22,
                        minHeight: 22,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.onlineGreen,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        unreadCount > 99 ? '99+' : unreadCount.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 7),
                  ],
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color:
                          isOnline ? AppColors.onlineGreen : AppColors.offline,
                      shape: BoxShape.circle,
                    ),
                    child: const SizedBox(width: 9, height: 9),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContactList() {
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
                style: const TextStyle(color: AppColors.mutedText),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadContacts,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_contacts.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'No contacts yet',
              style: TextStyle(
                color: AppColors.darkText,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Your accepted contacts will appear here',
              style: TextStyle(color: AppColors.mutedText),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: _contacts.length,
      itemBuilder: (context, index) => _buildContactItem(_contacts[index]),
    );
  }

  void _onBottomNavigationTap(int index) {
    switch (index) {
      case 0:
        return;
      case 1:
        _openAddContact();
        return;
      case 2:
        _openRequests();
        return;
      case 3:
        _showComingSoon('Profile');
        return;
      case 4:
        _logout(context);
        return;
    }
  }

  @override
  void dispose() {
    _socketService.removeMessageListener(_handleRealtimeMessage);
    _socketService.removePresenceListener(_handlePresence);
    _socketService.removeLastSeenListener(_handleLastSeenUpdated);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(),
            _buildChatControls(),
            const Divider(height: 1, color: AppColors.homeBorder),
            Expanded(child: _buildContactList()),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: BottomNavigationBar(
          currentIndex: 0,
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          selectedItemColor: AppColors.primaryGreen,
          unselectedItemColor: AppColors.mutedText,
          selectedFontSize: 11,
          unselectedFontSize: 11,
          elevation: 10,
          onTap: _onBottomNavigationTap,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.chat_bubble_outline),
              label: 'Chats',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.people_outline),
              label: 'Contacts',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.notifications_none),
              label: 'Requests',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.account_circle_outlined),
              label: 'Profile',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.logout),
              label: 'Logout',
            ),
          ],
        ),
      ),
    );
  }
}
