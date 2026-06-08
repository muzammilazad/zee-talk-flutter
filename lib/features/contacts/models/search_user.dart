class SearchUser {
  const SearchUser({
    required this.id,
    required this.name,
    this.email,
    this.phone,
    this.avatarUrl,
    this.relationshipStatus,
    this.requestStatus,
    this.contactRequestId,
  });

  final String id;
  final String name;
  final String? email;
  final String? phone;
  final String? avatarUrl;
  final String? relationshipStatus;
  final String? requestStatus;
  final String? contactRequestId;

  SearchUser withRelationshipStatus(String value) {
    return SearchUser(
      id: id,
      name: name,
      email: email,
      phone: phone,
      avatarUrl: avatarUrl,
      relationshipStatus: value,
      requestStatus: requestStatus,
      contactRequestId: contactRequestId,
    );
  }

  factory SearchUser.fromJson(Map<String, dynamic> json) {
    return SearchUser(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString(),
      phone: json['phone']?.toString(),
      avatarUrl: json['avatarUrl']?.toString(),
      relationshipStatus: json['relationshipStatus']?.toString(),
      requestStatus: json['requestStatus']?.toString(),
      contactRequestId: json['contactRequestId']?.toString(),
    );
  }
}
