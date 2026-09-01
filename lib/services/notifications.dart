import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Servizio notifiche locali (v0.2.44).
///
/// Mostra notifiche di sistema su eventi critici dell'osservatorio:
/// sequenza completata, star lost, meteo non sicuro, errori.
///
/// LIMITE ONESTO: le notifiche sono generate dal poller dell'app, quindi
/// arrivano in modo affidabile mentre l'app è in foreground o background
/// recente. Android (specie Oppo/Xiaomi) può sospendere l'app dopo un po';
/// per garanzia totale servirebbe un foreground service nativo. Per l'uso
/// tipico (telefono in tasca, app aperta durante la sessione) è efficace.
class Notifs {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _inited = false;
  static bool enabled = true; // toggle utente (persistito da AppState)

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
      if (kDebugMode) print('Notifs.init error: $e');
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

  /// Mostra una notifica. [id] stabile per categoria così notifiche dello
  /// stesso tipo si sostituiscono invece di accumularsi.
  static Future<void> show(int id, String title, String body,
      {bool highPriority = true}) async {
    if (!enabled || !_inited) return;
    final details = AndroidNotificationDetails(
      _channelId, _channelName,
      channelDescription: _channelDesc,
      importance: highPriority ? Importance.high : Importance.defaultImportance,
      priority: highPriority ? Priority.high : Priority.defaultPriority,
      styleInformation: BigTextStyleInformation(body),
    );
    try {
      await _plugin.show(id, title, body, NotificationDetails(android: details));
    } catch (e) {
      if (kDebugMode) print('Notifs.show error: $e');
    }
  }

  // ID stabili per categoria
  static const int idSequence = 1001;
  static const int idStarLost = 1002;
  static const int idWeather = 1003;
  static const int idError = 1004;
  static const int idGuiding = 1005;
  static const int idCooler = 1006;
  /// Alerts arriving from outside the app (bridge /ws/state `notification`).
  static const int idExternal = 1007;
}
