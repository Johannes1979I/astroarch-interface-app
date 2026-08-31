import 'notif_backend.dart' if (dart.library.io) 'notif_backend_io.dart';

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
///
/// The real implementation lives in notif_backend_io.dart; on the web the
/// conditional import selects an inert backend, because
/// `flutter_local_notifications` does not support the web and imports
/// `dart:io`, which would break the build. The public API is identical on
/// every platform, so callers need not know where they run.
class Notifs {
  static bool enabled = true; // toggle utente (persistito da AppState)

  /// Whether this platform can show system notifications. Settings can use
  /// it to hide a toggle that would have no effect.
  static bool get supported => NotifBackend.available;

  static Future<void> init() => NotifBackend.init();

  /// Requests notification permission. Idempotent.
  static Future<void> requestPermission() => NotifBackend.requestPermission();

  /// Mostra una notifica. [id] stabile per categoria così notifiche dello
  /// stesso tipo si sostituiscono invece di accumularsi.
  static Future<void> show(int id, String title, String body,
      {bool highPriority = true}) async {
    if (!enabled) return;
    return NotifBackend.show(id, title, body, highPriority: highPriority);
  }

  // ID stabili per categoria
  static const int idSequence = 1001;
  static const int idStarLost = 1002;
  static const int idWeather = 1003;
  static const int idError = 1004;
  static const int idGuiding = 1005;
  static const int idCooler = 1006;
}
