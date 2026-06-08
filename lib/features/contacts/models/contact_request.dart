class ContactRequest {
  const ContactRequest({
    required this.id,
    this.senderId,
    this.requesterId,
    this.receiverId,
    this.status,
    this.createdAt,
    this.respondedAt,
    this.requesterName,
    this.requesterEmail,
    this.requesterPhone,
    this.receiverName,
    this.receiverEmail,
  });

  final String id;
  final String? senderId;
  final String? requesterId;
  final String? receiverId;
  final String? status;
  final String? createdAt;
  final String? respondedAt;
  final String? requesterName;
  final String? requesterEmail;
  final String? requesterPhone;
  final String? receiverName;
  final String? receiverEmail;

  factory ContactRequest.fromJson(Map<String, dynamic> json) {
    final requester = json['requester'];
    final receiver = json['receiver'];
    final requesterData = requester is Map
        ? Map<String, dynamic>.from(requester)
        : const <String, dynamic>{};
    final receiverData = receiver is Map
        ? Map<String, dynamic>.from(receiver)
        : const <String, dynamic>{};

    return ContactRequest(
      id: json['id']?.toString() ?? '',
      senderId: json['senderId']?.toString(),
      requesterId: json['requesterId']?.toString(),
      receiverId: json['receiverId']?.toString(),
      status: json['status']?.toString(),
      createdAt: json['createdAt']?.toString(),
      respondedAt: json['respondedAt']?.toString(),
      requesterName: requesterData['name']?.toString(),
      requesterEmail: requesterData['email']?.toString(),
      requesterPhone: requesterData['phone']?.toString(),
      receiverName: receiverData['name']?.toString(),
      receiverEmail: receiverData['email']?.toString(),
    );
  }
}
