class ChatMessage {
  const ChatMessage({
    this.id,
    this.senderId,
    this.receiverId,
    this.type,
    this.text,
    this.message,
    this.status,
    this.createdAt,
    this.timestamp,
    this.replyToMessageId,
  });

  final String? id;
  final String? senderId;
  final String? receiverId;
  final String? type;
  final String? text;
  final String? message;
  final String? status;
  final String? createdAt;
  final String? timestamp;
  final String? replyToMessageId;

  String get displayText => text ?? message ?? '';

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id']?.toString(),
      senderId: json['senderId']?.toString(),
      receiverId: json['receiverId']?.toString(),
      type: json['type']?.toString(),
      text: json['text']?.toString(),
      message: json['message']?.toString(),
      status: json['status']?.toString(),
      createdAt: json['createdAt']?.toString(),
      timestamp: json['timestamp']?.toString(),
      replyToMessageId: json['replyToMessageId']?.toString(),
    );
  }
}
