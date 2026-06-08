import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../../core/config/app_config.dart';
import '../../core/storage/token_storage.dart';
import '../../features/chat/models/chat_message.dart';

class SocketService {
  SocketService._();

  static final SocketService instance = SocketService._();

  io.Socket? _socket;
  void Function(ChatMessage message)? _messageCallback;
  void Function(dynamic data)? _messageHandler;
  final Set<void Function(Set<String> onlineUserIds)> _presenceCallbacks = {};
  void Function(dynamic data)? _presenceHandler;
  final Set<void Function(Map<String, dynamic> data)> _typingCallbacks = {};
  void Function(dynamic data)? _typingHandler;
  final Set<void Function(String userId, String lastSeenAt)>
      _lastSeenCallbacks = {};
  void Function(dynamic data)? _lastSeenHandler;
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

  void onMessage(void Function(ChatMessage message) callback) {
    _messageCallback = callback;
    _bindMessageListeners();
  }

  void _bindListeners() {
    _bindMessageListeners();
    _bindPresenceListeners();
    _bindTypingListener();
    _bindLastSeenListener();
  }

  void _bindMessageListeners() {
    final socket = _socket;
    final callback = _messageCallback;
    if (socket == null || callback == null) {
      return;
    }

    final previousHandler = _messageHandler;
    if (previousHandler != null) {
      socket.off('private-message', previousHandler);
      socket.off('receive-message', previousHandler);
    }

    void handleMessage(dynamic data) {
      final messageData = _extractMessageData(data);
      if (messageData != null) {
        callback(ChatMessage.fromJson(messageData));
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

  void offMessage() {
    final handler = _messageHandler;
    if (handler != null) {
      _socket?.off('private-message', handler);
      _socket?.off('receive-message', handler);
    }
    _messageHandler = null;
    _messageCallback = null;
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
}

class SocketServiceException implements Exception {
  const SocketServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}
