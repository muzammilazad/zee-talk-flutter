class CallSession {
  const CallSession({
    required this.callId,
    required this.peerId,
    required this.peerName,
    required this.callType,
    required this.isIncoming,
    required this.status,
    required this.startedAt,
  });

  final String callId;
  final String peerId;
  final String peerName;
  final String callType;
  final bool isIncoming;
  final String status;
  final DateTime startedAt;

  bool get isVideo => callType == 'video';

  bool get isVoice => callType == 'voice';

  CallSession copyWith({
    String? status,
  }) {
    return CallSession(
      callId: callId,
      peerId: peerId,
      peerName: peerName,
      callType: callType,
      isIncoming: isIncoming,
      status: status ?? this.status,
      startedAt: startedAt,
    );
  }
}
