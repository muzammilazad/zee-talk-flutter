class ContactUser {
  const ContactUser({
    required this.id,
    required this.name,
    this.email,
    this.phone,
    this.avatarUrl,
    this.lastSeenAt,
    this.showOnline = false,
    this.showLastSeen = false,
    this.role,
    this.isSupport = false,
    this.isOfficialSupport = false,
  });

  final String id;
  final String name;
  final String? email;
  final String? phone;
  final String? avatarUrl;
  final String? lastSeenAt;
  final bool showOnline;
  final bool showLastSeen;
  final String? role;
  final bool isSupport;
  final bool isOfficialSupport;

  ContactUser withLastSeenAt(String? value) {
    return ContactUser(
      id: id,
      name: name,
      email: email,
      phone: phone,
      avatarUrl: avatarUrl,
      lastSeenAt: value,
      showOnline: showOnline,
      showLastSeen: showLastSeen,
      role: role,
      isSupport: isSupport,
      isOfficialSupport: isOfficialSupport,
    );
  }

  factory ContactUser.fromJson(Map<String, dynamic> json) {
    return ContactUser(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString(),
      phone: json['phone']?.toString(),
      avatarUrl: json['avatarUrl']?.toString(),
      lastSeenAt: json['lastSeenAt']?.toString(),
      showOnline: json['showOnline'] == true,
      showLastSeen: json['showLastSeen'] == true,
      role: json['role']?.toString(),
      isSupport: json['isSupport'] == true,
      isOfficialSupport: json['isOfficialSupport'] == true,
    );
  }
}
