import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Stato di un controller di gioco (Xbox e simili) collegato al telefono.
///
/// Lo produce `GamepadInput.kt`, che riduce croce, levetta sinistra e tasti
/// a quattro direzioni piu' l'elenco dei tasti premuti.
@immutable
class GamepadState {
  final bool up, down, left, right;
  final Set<String> buttons;
  final List<String> devices;

  const GamepadState({
    this.up = false, this.down = false, this.left = false, this.right = false,
    this.buttons = const {}, this.devices = const [],
  });

  factory GamepadState.fromMap(Map<dynamic, dynamic> m) => GamepadState(
        up: m['up'] == true,
        down: m['down'] == true,
        left: m['left'] == true,
        right: m['right'] == true,
        buttons: {for (final b in (m['buttons'] as List? ?? const [])) b.toString()},
        devices: [for (final d in (m['devices'] as List? ?? const [])) d.toString()],
      );

  bool get connected => devices.isNotEmpty;
}

/// Canale verso il codice Android del controller. Solo Android: sul web e
/// altrove [supported] e' false e [states] non emette nulla.
class GamepadInput {
  static const _events = EventChannel('astroarch/gamepad/events');
  static const _methods = MethodChannel('astroarch/gamepad');

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Stati del controller finche' qualcuno ascolta. Mentre si ascolta, il
  /// controller non muove piu' il focus dell'interfaccia.
  static Stream<GamepadState> states() => supported
      ? _events.receiveBroadcastStream().map((e) => GamepadState.fromMap(e as Map))
      : const Stream.empty();

  static Future<void> keepScreenOn(bool on) async {
    if (!supported) return;
    try {
      await _methods.invokeMethod('keepScreenOn', on);
    } on PlatformException {
      // Non essenziale: il telecomando funziona anche senza.
    }
  }
}

/// Stato del telecomando associato (in background), letto da Android.
@immutable
class RemoteStatus {
  final bool serviceEnabled;
  final bool associated;
  final String label;
  final String? lastError;
  final String? lastKey;

  const RemoteStatus({
    this.serviceEnabled = false, this.associated = false, this.label = '',
    this.lastError, this.lastKey,
  });

  factory RemoteStatus.fromMap(Map<dynamic, dynamic> m) => RemoteStatus(
        serviceEnabled: m['serviceEnabled'] == true,
        associated: m['associated'] == true,
        label: (m['label'] ?? '').toString(),
        lastError: m['lastError']?.toString(),
        lastKey: m['lastKey']?.toString(),
      );
}

/// Telecomando in background: un servizio di accessibilita' Android
/// (`RemoteAccessibilityService.kt`) riceve i tasti del controller anche con
/// l'app chiusa o altre app aperte, e manda lui i comandi al bridge.
/// In background arrivano solo i tasti, non la levetta.
class RemoteService {
  static const _methods = MethodChannel('astroarch/gamepad');

  static Future<RemoteStatus> status() async {
    if (!GamepadInput.supported) return const RemoteStatus();
    final m = await _methods.invokeMethod<Map<dynamic, dynamic>>('remoteStatus');
    return m == null ? const RemoteStatus() : RemoteStatus.fromMap(m);
  }

  static Future<void> associate({
    required String baseUrl, required String token, required String label,
    required String mode, required bool invertNS, required bool invertEW,
  }) => _methods.invokeMethod('remoteAssociate', {
        'baseUrl': baseUrl, 'token': token, 'label': label,
        'mode': mode, 'invertNS': invertNS, 'invertEW': invertEW,
      });

  static Future<void> dissociate() => _methods.invokeMethod('remoteDissociate');

  static Future<void> options({String? mode, bool? invertNS, bool? invertEW}) async {
    if (!GamepadInput.supported) return;
    await _methods.invokeMethod('remoteOptions', {
      if (mode != null) 'mode': mode,
      if (invertNS != null) 'invertNS': invertNS,
      if (invertEW != null) 'invertEW': invertEW,
    });
  }

  /// La schermata Telecomando e' aperta: finche' e' in primo piano gestisce
  /// lei il controller (anche la levetta) e il servizio si fa da parte.
  static Future<void> screenOpen(bool open) async {
    if (!GamepadInput.supported) return;
    await _methods.invokeMethod('remoteScreenOpen', open);
  }

  static Future<void> openAccessibilitySettings() =>
      _methods.invokeMethod('openAccessibilitySettings');
  static Future<void> openAppSettings() => _methods.invokeMethod('openAppSettings');
}
