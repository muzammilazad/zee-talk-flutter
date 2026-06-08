import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../../core/config/app_config.dart';
import '../../core/storage/token_storage.dart';
import '../../features/chat/models/chat_message.dart';

class SocketService {
  SocketService._();

  static final SocketService instance = SocketService._();

  io.Socket? _socket;
  final Set<void Function(ChatMessage message)> _messageCallbacks = {};
  void Function(dynamic data)? _messageHandler;
  final Set<void Function(Set<String> onlineUserIds)> _presenceCallbacks = {};
  void Function(dynamic data)? _presenceHandler;
  final Set<void Function(Map<String, dynamic> data)> _typingCallbacks = {};
  void Function(dynamic data)? _typingHandler;
  final Set<void Function(String userId, String lastSeenAt)>
      _lastSeenCallbacks = {};
  void Function(dynamic data)? _lastSeenHandler;
  final Set<void Function(String from, List<String> messageIds)>
      _readReceiptCallbacks = {};
  final Map<String, void Function(dynamic data)> _readReceiptHandlers = {};
  final Set<void Function(ChatMessage message)> _messageStatusCallbacks = {};
  void Function(dynamic data)? _messageStatusHandler;
  final Set<void Function(Map<String, dynamic> data)> _incomingCallCallbacks =
      {};
  final Set<void Function(Map<String, dynamic> data)> _callRejectCallbacks = {};
  final Set<void Function(Map<String, dynamic> data)> _callEndCallbacks = {};
  final Set<void Function(Map<String, dynamic> data)> _callTimeoutCallbacks =
      {};
  final Set<void Function(Map<String, dynamic> data)>
      _callUnavailableCallbacks = {};
  final Set<void Function(Map<String, dynamic> data)> _missedCallCallbacks = {};
  final Set<void Function(Map<String, dynamic> data)> _callOfferCallbacks = {};
  final Set<void Function(Map<String, dynamic> data)> _callAnswerCallbacks = {};
  final Set<void Function(Map<String, dynamic> data)> _iceCandidateCallbacks =
      {};
  final Map<String, void Function(dynamic data)> _callHandlers = {};
  Set<String> _onlineUserIds = {};

  Future<void> connect() async {
    final existingSocket = _socket;
    if (existingSocket != null) {
      _bindListeners();
      if (!existingSocket.connected && !existingSocket.active) {
        existingSocket.connect();
      }
      return;
    }

    final token = await TokenStorage().getToken();
    if (token == null || token.isEmpty) {
      throw const SocketServiceException('Authentication token is missing');
    }

    _socket?.dispose();
    _socket = io.io(
      AppConfig.socketUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .setAuth({'token': token})
          .setAckTimeout(15000)
          .build(),
    );
    _socket!.onConnect((_) {
      debugPrint('[Socket] connected: ${_socket?.id}');
    });
    _socket!.onConnectError((error) {
      debugPrint('[Socket] connect_error: $error');
    });
    _socket!.onDisconnect((_) {
      debugPrint('[Socket] disconnected');
    });
    _bindListeners();
    _socket!.connect();
  }

  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _onlineUserIds = {};
  }

  Future<ChatMessage> sendMessage({
    required String receiverId,
    required String text,
    String? replyToMessageId,
  }) async {
    final socket = _socket;
    if (socket == null) {
      throw const SocketServiceException('Chat is not connected');
    }

    final clientId = '${DateTime.now().millisecondsSinceEpoch}-$receiverId';
    final payload = <String, dynamic>{
      'receiverId': receiverId,
      'text': text,
      'clientId': clientId,
      'replyToMessageId': replyToMessageId,
    };

    try {
      final response = await socket.emitWithAckAsync(
        'send-message',
        payload,
      );
      if (response is! Map) {
        throw const SocketServiceException(
          'Invalid response while sending message',
        );
      }

      final acknowledgement = Map<String, dynamic>.from(response);
      if (acknowledgement['ok'] != true) {
        throw SocketServiceException(
          acknowledgement['message']?.toString() ??
              acknowledgement['error']?.toString() ??
              'Message could not be sent',
        );
      }

      final messageData = acknowledgement['message'];
      if (messageData is! Map) {
        throw const SocketServiceException(
          'Message acknowledgement was incomplete',
        );
      }

      return ChatMessage.fromJson(
        Map<String, dynamic>.from(messageData),
      );
    } catch (error) {
      if (error is SocketServiceException) {
        rethrow;
      }
      throw SocketServiceException(error.toString());
    }
  }

  void markMessagesRead({
    required String peerId,
    List<String> messageIds = const [],
  }) {
    _socket?.emit('message-read', {
      'peerId': peerId,
      'messageIds': messageIds,
    });
  }

  Future<Map<String, dynamic>?> startCall({
    required String to,
    required String callId,
    required String callType,
  }) async {
    final socket = _socket;
    if (socket == null || !socket.connected) {
      throw const SocketServiceException('Call service is not connected');
    }

    final response = await socket.emitWithAckAsync(
      'call-start',
      {
        'to': to,
        'callId': callId,
        'callType': callType,
      },
    );
    if (response is! Map) {
      return null;
    }
    return Map<String, dynamic>.from(response);
  }

  void rejectCall({
    required String to,
    required String callId,
    required String callType,
  }) {
    _socket?.emit('call-reject', {
      'to': to,
      'callId': callId,
      'callType': callType,
    });
  }

  void endCall({
    required String to,
    required String callId,
    required String callType,
  }) {
    _socket?.emit('call-end', {
      'to': to,
      'callId': callId,
      'callType': callType,
    });
  }

  void sendCallOffer({
    required String to,
    required String callId,
    required String callType,
    required Map<String, dynamic> offer,
  }) {
    _socket?.emit('call-offer', {
      'to': to,
      'callId': callId,
      'callType': callType,
      'offer': offer,
    });
  }

  void sendCallAnswer({
    required String to,
    required String callId,
    required String callType,
    required Map<String, dynamic> answer,
  }) {
    _socket?.emit('call-answer', {
      'to': to,
      'callId': callId,
      'callType': callType,
      'answer': answer,
    });
  }

  void sendIceCandidate({
    required String to,
    required String callId,
    required String callType,
    required Map<String, dynamic> candidate,
  }) {
    _socket?.emit('ice-candidate', {
      'to': to,
      'callId': callId,
      'callType': callType,
      'candidate': candidate,
    });
  }

  void addMessageListener(
    void Function(ChatMessage message) callback,
  ) {
    _messageCallbacks.add(callback);
    _bindMessageListeners();
  }

  void _bindListeners() {
    _bindMessageListeners();
    _bindPresenceListeners();
    _bindTypingListener();
    _bindLastSeenListener();
    _bindReadReceiptListeners();
    _bindMessageStatusListener();
    _bindCallListeners();
  }

  void _bindMessageListeners() {
    final socket = _socket;
    if (socket == null || _messageCallbacks.isEmpty) {
      return;
    }

    final previousHandler = _messageHandler;
    if (previousHandler != null) {
      socket.off('private-message', previousHandler);
      socket.off('receive-message', previousHandler);
    }

    void handleMessage(dynamic data) {
      debugPrint('[Socket] incoming message raw: $data');
      final messageData = _extractMessageData(data);
      if (messageData != null) {
        final message = ChatMessage.fromJson(messageData);
        debugPrint('[Socket] incoming message id: ${message.id}');
        for (final callback in List.of(_messageCallbacks)) {
          callback(message);
        }
      }
    }

    _messageHandler = handleMessage;
    socket.on('private-message', handleMessage);
    socket.on('receive-message', handleMessage);
  }

  Map<String, dynamic>? _extractMessageData(dynamic data) {
    if (data is! Map) {
      return null;
    }

    final payload = Map<String, dynamic>.from(data);
    if (payload['message'] is Map) {
      return Map<String, dynamic>.from(payload['message'] as Map);
    }
    if (payload['data'] is Map) {
      return _extractMessageData(payload['data']);
    }
    return payload;
  }

  void removeMessageListener(
    void Function(ChatMessage message) callback,
  ) {
    _messageCallbacks.remove(callback);
    if (_messageCallbacks.isNotEmpty) {
      return;
    }

    final handler = _messageHandler;
    if (handler != null) {
      _socket?.off('private-message', handler);
      _socket?.off('receive-message', handler);
    }
    _messageHandler = null;
  }

  void onPresence(
    void Function(Set<String> onlineUserIds) callback,
  ) {
    _presenceCallbacks.add(callback);
    callback(Set<String>.unmodifiable(_onlineUserIds));
    _bindPresenceListeners();
  }

  void _bindPresenceListeners() {
    final socket = _socket;
    if (socket == null || _presenceCallbacks.isEmpty) {
      return;
    }

    final previousHandler = _presenceHandler;
    if (previousHandler != null) {
      socket.off('presence', previousHandler);
    }

    void handlePresence(dynamic data) {
      if (data is! List) {
        debugPrint('[Socket] presence payload ignored: $data');
        return;
      }

      final onlineIds = <String>{};
      for (final user in data) {
        if (user is Map && user['id'] != null) {
          onlineIds.add(user['id'].toString());
        }
      }

      _onlineUserIds = onlineIds;
      debugPrint('[Socket] presence ids: $onlineIds');
      final snapshot = Set<String>.unmodifiable(onlineIds);
      for (final callback in List.of(_presenceCallbacks)) {
        callback(snapshot);
      }
    }

    _presenceHandler = handlePresence;
    socket.on('presence', handlePresence);
  }

  void removePresenceListener(
    void Function(Set<String> onlineUserIds) callback,
  ) {
    _presenceCallbacks.remove(callback);
    if (_presenceCallbacks.isNotEmpty) {
      return;
    }

    final handler = _presenceHandler;
    if (handler != null) {
      _socket?.off('presence', handler);
    }
    _presenceHandler = null;
  }

  void sendTyping({
    required String to,
    required bool isTyping,
  }) {
    _socket?.emit('typing', {
      'to': to,
      'isTyping': isTyping,
    });
  }

  void onTyping(
    void Function(Map<String, dynamic> data) callback,
  ) {
    _typingCallbacks.add(callback);
    _bindTypingListener();
  }

  void _bindTypingListener() {
    final socket = _socket;
    if (socket == null || _typingCallbacks.isEmpty) {
      return;
    }

    final previousHandler = _typingHandler;
    if (previousHandler != null) {
      socket.off('typing', previousHandler);
    }

    void handleTyping(dynamic data) {
      final typingData = _extractTypingData(data);
      if (typingData == null) {
        return;
      }
      for (final callback in List.of(_typingCallbacks)) {
        callback(typingData);
      }
    }

    _typingHandler = handleTyping;
    socket.on('typing', handleTyping);
  }

  Map<String, dynamic>? _extractTypingData(dynamic data) {
    if (data is! Map) {
      return null;
    }

    final payload = Map<String, dynamic>.from(data);
    if (payload['data'] is Map) {
      return Map<String, dynamic>.from(payload['data'] as Map);
    }
    return payload;
  }

  void offTyping([
    void Function(Map<String, dynamic> data)? callback,
  ]) {
    if (callback != null) {
      _typingCallbacks.remove(callback);
    } else {
      _typingCallbacks.clear();
    }

    if (_typingCallbacks.isNotEmpty) {
      return;
    }
    final handler = _typingHandler;
    if (handler != null) {
      _socket?.off('typing', handler);
    }
    _typingHandler = null;
  }

  void onLastSeenUpdated(
    void Function(String userId, String lastSeenAt) callback,
  ) {
    _lastSeenCallbacks.add(callback);
    _bindLastSeenListener();
  }

  void _bindLastSeenListener() {
    final socket = _socket;
    if (socket == null || _lastSeenCallbacks.isEmpty) {
      return;
    }

    final previousHandler = _lastSeenHandler;
    if (previousHandler != null) {
      socket.off('last-seen-updated', previousHandler);
    }

    void handleLastSeen(dynamic data) {
      if (data is! Map) {
        return;
      }

      final userId = data['userId']?.toString();
      final lastSeenAt = data['lastSeenAt']?.toString();
      if (userId == null ||
          userId.isEmpty ||
          lastSeenAt == null ||
          lastSeenAt.isEmpty) {
        return;
      }

      for (final callback in List.of(_lastSeenCallbacks)) {
        callback(userId, lastSeenAt);
      }
    }

    _lastSeenHandler = handleLastSeen;
    socket.on('last-seen-updated', handleLastSeen);
  }

  void removeLastSeenListener(
    void Function(String userId, String lastSeenAt) callback,
  ) {
    _lastSeenCallbacks.remove(callback);
    if (_lastSeenCallbacks.isNotEmpty) {
      return;
    }

    final handler = _lastSeenHandler;
    if (handler != null) {
      _socket?.off('last-seen-updated', handler);
    }
    _lastSeenHandler = null;
  }

  void addReadReceiptListener(
    void Function(String from, List<String> messageIds) callback,
  ) {
    _readReceiptCallbacks.add(callback);
    _bindReadReceiptListeners();
  }

  void _bindReadReceiptListeners() {
    final socket = _socket;
    if (socket == null || _readReceiptCallbacks.isEmpty) {
      return;
    }

    for (final event in ['message-read', 'messages-read']) {
      final previousHandler = _readReceiptHandlers[event];
      if (previousHandler != null) {
        socket.off(event, previousHandler);
      }

      void handleReceipt(dynamic data) {
        debugPrint('[Socket] $event raw: $data');
        if (data is! Map) {
          return;
        }

        final payload = Map<String, dynamic>.from(data);
        final from = payload['from']?.toString();
        if (from == null || from.isEmpty) {
          return;
        }

        final rawIds = payload['messageIds'];
        final messageIds = rawIds is List
            ? rawIds
                .where((id) => id != null)
                .map((id) => id.toString())
                .toList()
            : <String>[];
        for (final callback in List.of(_readReceiptCallbacks)) {
          callback(from, messageIds);
        }
      }

      _readReceiptHandlers[event] = handleReceipt;
      socket.on(event, handleReceipt);
    }
  }

  void removeReadReceiptListener(
    void Function(String from, List<String> messageIds) callback,
  ) {
    _readReceiptCallbacks.remove(callback);
    if (_readReceiptCallbacks.isNotEmpty) {
      return;
    }

    for (final entry in _readReceiptHandlers.entries) {
      _socket?.off(entry.key, entry.value);
    }
    _readReceiptHandlers.clear();
  }

  void addMessageStatusListener(
    void Function(ChatMessage message) callback,
  ) {
    _messageStatusCallbacks.add(callback);
    _bindMessageStatusListener();
  }

  void _bindMessageStatusListener() {
    final socket = _socket;
    if (socket == null || _messageStatusCallbacks.isEmpty) {
      return;
    }

    final previousHandler = _messageStatusHandler;
    if (previousHandler != null) {
      socket.off('message-status-updated', previousHandler);
    }

    void handleStatus(dynamic data) {
      debugPrint('[Socket] message-status-updated raw: $data');
      final messageData = _extractMessageData(data);
      if (messageData == null) {
        return;
      }

      final message = ChatMessage.fromJson(messageData);
      for (final callback in List.of(_messageStatusCallbacks)) {
        callback(message);
      }
    }

    _messageStatusHandler = handleStatus;
    socket.on('message-status-updated', handleStatus);
  }

  void removeMessageStatusListener(
    void Function(ChatMessage message) callback,
  ) {
    _messageStatusCallbacks.remove(callback);
    if (_messageStatusCallbacks.isNotEmpty) {
      return;
    }

    final handler = _messageStatusHandler;
    if (handler != null) {
      _socket?.off('message-status-updated', handler);
    }
    _messageStatusHandler = null;
  }

  void addIncomingCallListener(
    void Function(Map<String, dynamic> data) callback,
  ) {
    _incomingCallCallbacks.add(callback);
    _bindCallListeners();
  }

  void removeIncomingCallListener(
    void Function(Map<String, dynamic> data) callback,
  ) {
    _incomingCallCallbacks.remove(callback);
    _unbindCallEventIfUnused('incoming-call', _incomingCallCallbacks);
  }

  void addCallRejectListener(
    void Function(Map<String, dynamic> data) callback,
  ) {
    _callRejectCallbacks.add(callback);
    _bindCallListeners();
  }

  void removeCallRejectListener(
    void Function(Map<String, dynamic> data) callback,
  ) {
    _callRejectCallbacks.remove(callback);
    _unbindCallEventIfUnused('call-reject', _callRejectCallbacks);
  }

  void addCallEndListener(
    void Function(Map<String, dynamic> data) callback,
  ) {
    _callEndCallbacks.add(callback);
    _bindCallListeners();
  }

  void removeCallEndListener(
    void Function(Map<String, dynamic> data) callback,
  ) {
    _callEndCallbacks.remove(callback);
    _unbindCallEventIfUnused('call-end', _callEndCallbacks);
  }

  void addCallTimeoutListener(
    void Function(Map<String, dynamic> data) callback,
  ) {
    _callTimeoutCallbacks.add(callback);
    _bindCallListeners();
  }

  void removeCallTimeoutListener(
    void Function(Map<String, dynamic> data) callback,
  ) {
    _callTimeoutCallbacks.remove(callback);
    _unbindCallEventIfUnused('call-timeout', _callTimeoutCallbacks);
  }

  void addCallUnavailableListener(
    void Function(Map<String, dynamic> data) callback,
  ) {
    _callUnavailableCallbacks.add(callback);
    _bindCallListeners();
  }

  void removeCallUnavailableListener(
    void Function(Map<String, dynamic> data) callback,
  ) {
    _callUnavailableCallbacks.remove(callback);
    _unbindCallEventIfUnused('call-unavailable', _callUnavailableCallbacks);
  }

  void addMissedCallListener(
    void Function(Map<String, dynamic> data) callback,
  ) {
    _missedCallCallbacks.add(callback);
    _bindCallListeners();
  }

  void removeMissedCallListener(
    void Function(Map<String, dynamic> data) callback,
  ) {
    _missedCallCallbacks.remove(callback);
    _unbindCallEventIfUnused('missed-call', _missedCallCallbacks);
  }

  void addCallOfferListener(
    void Function(Map<String, dynamic> data) callback,
  ) {
    _callOfferCallbacks.add(callback);
    _bindCallListeners();
  }

  void removeCallOfferListener(
    void Function(Map<String, dynamic> data) callback,
  ) {
    _callOfferCallbacks.remove(callback);
    _unbindCallEventIfUnused('call-offer', _callOfferCallbacks);
  }

  void addCallAnswerListener(
    void Function(Map<String, dynamic> data) callback,
  ) {
    _callAnswerCallbacks.add(callback);
    _bindCallListeners();
  }

  void removeCallAnswerListener(
    void Function(Map<String, dynamic> data) callback,
  ) {
    _callAnswerCallbacks.remove(callback);
    _unbindCallEventIfUnused('call-answer', _callAnswerCallbacks);
  }

  void addIceCandidateListener(
    void Function(Map<String, dynamic> data) callback,
  ) {
    _iceCandidateCallbacks.add(callback);
    _bindCallListeners();
  }

  void removeIceCandidateListener(
    void Function(Map<String, dynamic> data) callback,
  ) {
    _iceCandidateCallbacks.remove(callback);
    _unbindCallEventIfUnused('ice-candidate', _iceCandidateCallbacks);
  }

  void _bindCallListeners() {
    _bindCallEvent('incoming-call', _incomingCallCallbacks);
    _bindCallEvent('call-reject', _callRejectCallbacks);
    _bindCallEvent('call-end', _callEndCallbacks);
    _bindCallEvent('call-timeout', _callTimeoutCallbacks);
    _bindCallEvent('call-unavailable', _callUnavailableCallbacks);
    _bindCallEvent('missed-call', _missedCallCallbacks);
    _bindCallEvent('call-offer', _callOfferCallbacks);
    _bindCallEvent('call-answer', _callAnswerCallbacks);
    _bindCallEvent('ice-candidate', _iceCandidateCallbacks);
  }

  void _bindCallEvent(
    String event,
    Set<void Function(Map<String, dynamic> data)> callbacks,
  ) {
    final socket = _socket;
    if (socket == null || callbacks.isEmpty) {
      return;
    }

    final previousHandler = _callHandlers[event];
    if (previousHandler != null) {
      socket.off(event, previousHandler);
    }

    void handleCallEvent(dynamic data) {
      debugPrint('[Socket Call] $event: $data');
      if (data is! Map) {
        return;
      }

      final payload = Map<String, dynamic>.from(data);
      for (final callback in List.of(callbacks)) {
        callback(payload);
      }
    }

    _callHandlers[event] = handleCallEvent;
    socket.on(event, handleCallEvent);
  }

  void _unbindCallEventIfUnused(
    String event,
    Set<void Function(Map<String, dynamic> data)> callbacks,
  ) {
    if (callbacks.isNotEmpty) {
      return;
    }

    final handler = _callHandlers.remove(event);
    if (handler != null) {
      _socket?.off(event, handler);
    }
  }
}

class SocketServiceException implements Exception {
  const SocketServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}
