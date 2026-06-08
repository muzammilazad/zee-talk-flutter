import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class LocalNotificationService {
  LocalNotificationService._();

  static final LocalNotificationService _instance =
      LocalNotificationService._();

  factory LocalNotificationService() => _instance;

  static const AndroidNotificationChannel _messageChannel =
      AndroidNotificationChannel(
    'zee_talk_messages',
    'Messages',
    description: 'Zee Talk message notifications',
    importance: Importance.high,
  );

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) {
      return;
    }

    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      _isInitialized = true;
      return;
    }

    try {
      const initializationSettings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      );

      await _notifications.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: (_) {},
      );

      await _notifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_messageChannel);

      _isInitialized = true;
      await requestPermissionsIfNeeded();
    } catch (error) {
      debugPrint('[Notifications] initialization failed: $error');
    }
  }

  Future<void> requestPermissionsIfNeeded() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    try {
      await _notifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (error) {
      debugPrint('[Notifications] permission request failed: $error');
    }
  }

  Future<void> showMessageNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_isInitialized) {
      await init();
    }

    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    try {
      const notificationDetails = NotificationDetails(
        android: AndroidNotificationDetails(
          'zee_talk_messages',
          'Messages',
          channelDescription: 'Zee Talk message notifications',
          importance: Importance.high,
          priority: Priority.high,
        ),
      );

      final notificationId =
          DateTime.now().millisecondsSinceEpoch.remainder(2147483647);
      await _notifications.show(
        notificationId,
        title,
        body,
        notificationDetails,
        payload: payload,
      );
    } catch (error) {
      debugPrint('[Notifications] failed to show notification: $error');
    }
  }
}
