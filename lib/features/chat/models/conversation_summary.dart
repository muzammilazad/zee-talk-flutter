class ConversationSummary {
  const ConversationSummary({
    required this.peerId,
    required this.unreadCount,
    this.latestId,
    this.latestText,
    this.latestType,
    this.latestSenderId,
    this.latestReceiverId,
    this.latestStatus,
    this.latestCreatedAt,
  });

  final String peerId;
  final int unreadCount;
  final String? latestId;
  final String? latestText;
  final String? latestType;
  final String? latestSenderId;
  final String? latestReceiverId;
  final String? latestStatus;
  final String? latestCreatedAt;

  factory ConversationSummary.fromJson(Map<String, dynamic> json) {
    final latestValue = json['latest'];
    if (latestValue is! Map) {
      return ConversationSummary(
        peerId: json['peerId']?.toString() ?? '',
        unreadCount: _parseCount(json['unreadCount']),
      );
    }

    final latest = Map<String, dynamic>.from(latestValue);
    final type = latest['type']?.toString();

    return ConversationSummary(
      peerId: json['peerId']?.toString() ?? '',
      unreadCount: _parseCount(json['unreadCount']),
      latestId: latest['id']?.toString(),
      latestText: _previewText(latest, type),
      latestType: type,
      latestSenderId: latest['senderId']?.toString(),
      latestReceiverId: latest['receiverId']?.toString(),
      latestStatus: latest['status']?.toString(),
      latestCreatedAt: (latest['createdAt'] ?? latest['timestamp'])?.toString(),
    );
  }

  static int _parseCount(dynamic value) {
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String? _previewText(
    Map<String, dynamic> latest,
    String? type,
  ) {
    final text = latest['text']?.toString().trim();
    if (text != null && text.isNotEmpty) {
      return text;
    }

    final message = latest['message']?.toString().trim();
    if (message != null && message.isNotEmpty) {
      return message;
    }

    final normalizedType = type?.toLowerCase() ?? '';
    final looksLikeCall = normalizedType.contains('call') ||
        latest.containsKey('callId') ||
        latest.containsKey('callType') ||
        latest.containsKey('duration');
    return looksLikeCall ? 'Call' : null;
  }
}
