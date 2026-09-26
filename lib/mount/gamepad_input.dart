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
