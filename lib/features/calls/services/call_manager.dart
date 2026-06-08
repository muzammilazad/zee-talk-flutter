import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/navigation/app_navigator.dart';
import '../../../data/socket/socket_service.dart';
import '../../users/models/contact_user.dart';
import '../models/call_session.dart';
import '../screens/incoming_call_screen.dart';
import '../screens/outgoing_call_screen.dart';

class CallManager {
  CallManager._();

  static final CallManager _instance = CallManager._();

  factory CallManager() => _instance;

  final SocketService _socketService = SocketService.instance;
  final ValueNotifier<CallSession?> activeCallNotifier =
      ValueNotifier<CallSession?>(null);
  final Set<String> _presentedCallIds = {};

  Timer? _clearTimer;
  bool _isInitialized = false;

  CallSession? get activeCall => activeCallNotifier.value;

  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }

    _socketService.addIncomingCallListener(_handleIncomingCall);
    _socketService.addCallRejectListener(_handleCallReject);
    _socketService.addCallEndListener(_handleCallEnd);
    _socketService.addCallTimeoutListener(_handleCallTimeout);
    _socketService.addCallUnavailableListener(_handleCallUnavailable);
    _socketService.addMissedCallListener(_handleMissedCall);
    _isInitialized = true;

    try {
      await _socketService.connect();
    } catch (error) {
      debugPrint('[CallManager] initialization failed: $error');
    }
  }

  Future<void> startOutgoingCall({
    required ContactUser contact,
    required String callType,
  }) async {
    if (activeCall != null) {
      _showMessage('Another call is already active');
      return;
    }

    await initialize();
    final callId =
        '${DateTime.now().millisecondsSinceEpoch}-${contact.id}';

    try {
      final acknowledgement = await _socketService.startCall(
        to: contact.id,
        callId: callId,
        callType: callType,
      );
      if (acknowledgement?['ok'] != true) {
        final reason = acknowledgement?['reason']?.toString();
        activeCallNotifier.value = CallSession(
          callId: callId,
          peerId: contact.id,
          peerName: contact.name,
          callType: callType,
          isIncoming: false,
          status: 'unavailable',
          startedAt: DateTime.now(),
        );
        _showMessage(
          reason == 'offline' ? 'User is offline' : 'Call is unavailable',
        );
        _scheduleClear();
        return;
      }

      final session = CallSession(
        callId: acknowledgement?['callId']?.toString() ?? callId,
        peerId: contact.id,
        peerName: contact.name,
        callType: callType,
        isIncoming: false,
        status: 'calling',
        startedAt: DateTime.now(),
      );
      activeCallNotifier.value = session;
      _showOutgoingCall(session);
    } catch (error) {
      _showMessage(error.toString());
      clearCall();
    }
  }

  void rejectIncomingCall(CallSession session) {
    _socketService.rejectCall(
      to: session.peerId,
      callId: session.callId,
      callType: session.callType,
    );
    clearCall();
  }

  void acceptIncomingCall(CallSession session) {
    activeCallNotifier.value = session.copyWith(status: 'connecting');
  }

  void endCurrentCall() {
    final session = activeCall;
    if (session == null) {
      return;
    }

    _socketService.endCall(
      to: session.peerId,
      callId: session.callId,
      callType: session.callType,
    );
    clearCall();
  }

  void clearCall() {
    _clearTimer?.cancel();
    _clearTimer = null;
    activeCallNotifier.value = null;
  }

  void dispose() {
    if (_isInitialized) {
      _socketService.removeIncomingCallListener(_handleIncomingCall);
      _socketService.removeCallRejectListener(_handleCallReject);
      _socketService.removeCallEndListener(_handleCallEnd);
      _socketService.removeCallTimeoutListener(_handleCallTimeout);
      _socketService.removeCallUnavailableListener(_handleCallUnavailable);
      _socketService.removeMissedCallListener(_handleMissedCall);
    }
    _isInitialized = false;
    _presentedCallIds.clear();
    clearCall();
  }

  void _handleIncomingCall(Map<String, dynamic> data) {
    final callId = data['callId']?.toString();
    final peerId = data['from']?.toString();
    if (callId == null ||
        callId.isEmpty ||
        peerId == null ||
        peerId.isEmpty) {
      return;
    }

    final currentCall = activeCall;
    if (currentCall != null) {
      if (currentCall.callId == callId) {
        return;
      }
      // TODO: emit an explicit busy response when the backend supports it.
      return;
    }

    final fromUser = data['fromUser'];
    final peerName = fromUser is Map
        ? fromUser['name']?.toString() ?? 'Unknown'
        : 'Unknown';
    final session = CallSession(
      callId: callId,
      peerId: peerId,
      peerName: peerName,
      callType: data['callType']?.toString() == 'video' ? 'video' : 'voice',
      isIncoming: true,
      status: 'ringing',
      startedAt: DateTime.now(),
    );

    activeCallNotifier.value = session;
    _showIncomingCall(session);
  }

  void _handleCallReject(Map<String, dynamic> data) {
    _finishMatchingCall(data, 'declined');
  }

  void _handleCallEnd(Map<String, dynamic> data) {
    _finishMatchingCall(data, 'ended');
  }

  void _handleCallTimeout(Map<String, dynamic> data) {
    _finishMatchingCall(data, 'timeout');
  }

  void _handleCallUnavailable(Map<String, dynamic> data) {
    _finishMatchingCall(data, 'unavailable');
  }

  void _handleMissedCall(Map<String, dynamic> data) {
    _finishMatchingCall(data, 'missed');
  }

  void _finishMatchingCall(Map<String, dynamic> data, String status) {
    final session = activeCall;
    final callId = data['callId']?.toString();
    if (session == null || callId == null || session.callId != callId) {
      return;
    }

    activeCallNotifier.value = session.copyWith(status: status);
    _scheduleClear();
  }

  void _scheduleClear() {
    _clearTimer?.cancel();
    _clearTimer = Timer(const Duration(milliseconds: 1400), clearCall);
  }

  void _showIncomingCall(CallSession session) {
    if (!_presentedCallIds.add(session.callId)) {
      return;
    }

    final navigator = appNavigatorKey.currentState;
    if (navigator == null) {
      _presentedCallIds.remove(session.callId);
      return;
    }
    unawaited(
      navigator
          .push(
            MaterialPageRoute<void>(
              builder: (_) => IncomingCallScreen(session: session),
              fullscreenDialog: true,
            ),
          )
          .whenComplete(() => _presentedCallIds.remove(session.callId)),
    );
  }

  void _showOutgoingCall(CallSession session) {
    if (!_presentedCallIds.add(session.callId)) {
      return;
    }

    final navigator = appNavigatorKey.currentState;
    if (navigator == null) {
      _presentedCallIds.remove(session.callId);
      clearCall();
      return;
    }
    unawaited(
      navigator
          .push(
            MaterialPageRoute<void>(
              builder: (_) => OutgoingCallScreen(session: session),
              fullscreenDialog: true,
            ),
          )
          .whenComplete(() => _presentedCallIds.remove(session.callId)),
    );
  }

  void _showMessage(String message) {
    final context = appNavigatorKey.currentContext;
    if (context == null) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
