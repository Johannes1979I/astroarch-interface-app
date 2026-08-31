import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Notification backend for platforms that have system notifications.
///
/// Selected by the conditional import in notifications.dart when `dart:io`
/// is available, that is, on Android. This is the code that was there
/// before, moved here untouched: it cannot even compile for the web,
/// because flutter_local_notifications imports `dart:io`.
class NotifBackend {
  static bool get available => true;

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _inited = false;

  static const String _channelId = 'astroarch_alerts';
  static const String _channelName = 'Astroarch alerts';
  static const String _channelDesc =
      'Avvisi osservatorio: sequenza, guida, meteo, errori';

  static Future<void> init() async {
    if (_inited) return;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    try {
      await _plugin.initialize(initSettings);
      // Crea il canale (Android 8+)
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(const AndroidNotificationChannel(
        _channelId, _channelName,
        description: _channelDesc,
        importance: Importance.high,
      ));
      _inited = true;
    } catch (e) {
      if (kDebugMode) print('NotifBackend.init error: $e');
    }
  }

  /// Chiede il permesso notifiche (Android 13+). Idempotente.
  static Future<void> requestPermission() async {
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();
    } catch (_) {}
  }

  static Future<void> show(int id, String title, String body,
      {bool highPriority = true}) async {
    if (!_inited) return;
    final android = AndroidNotificationDetails(
      _channelId, _channelName,
      channelDescription: _channelDesc,
      importance: highPriority ? Importance.high : Importance.defaultImportance,
      priority: highPriority ? Priority.high : Priority.defaultPriority,
      styleInformation: BigTextStyleInformation(body),
    );
    try {
      await _plugin.show(id, title, body,
          NotificationDetails(android: android));
    } catch (e) {
      if (kDebugMode) print('NotifBackend.show error: $e');
    }
  }
}
