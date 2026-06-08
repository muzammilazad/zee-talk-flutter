class AppConfig {
  AppConfig._();

  static const String appName = 'Zee Talk';
  static const String baseUrl = 'https://zivico-talk-production.up.railway.app';
  static const String socketUrl =
      'https://zivico-talk-production.up.railway.app';

  static const List<Map<String, dynamic>> iceServers = [
    {
      'urls': ['stun:stun.l.google.com:19302'],
    },
    {
      'urls': ['turn:openrelay.metered.ca:80'],
      'username': 'openrelayproject',
      'credential': 'openrelayproject',
    },
  ];
}
