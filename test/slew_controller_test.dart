import 'package:astroarch_interface/mount/slew_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// Registra le chiamate al bridge; ogni invio dura [delay] e i primi
/// [failures] falliscono, per simulare una rete lenta o che cade.
class _FakeBridge {
  _FakeBridge({this.delay = Duration.zero});
  final Duration delay;
  int failures = 0;
  final calls = <String>[];

  Future<void> send(String dir, bool active, {bool beat = false}) async {
    await Future<void>.delayed(delay);
    if (failures > 0) {
      failures--;
      throw Exception('rete giu');
    }
    calls.add('$dir ${active ? (beat ? 'beat' : 'on') : 'off'}');
  }
}

Future<void> _wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  test('lo stop non sorpassa mai la partenza, anche con la rete lenta', () async {
    final b = _FakeBridge(delay: const Duration(milliseconds: 30));
    final c = SlewController(send: b.send, heartbeat: const Duration(seconds: 10));
    c.press('N');
    c.release('N'); // rilascio mentre la partenza e' ancora in volo
    await _wait(120);
    expect(b.calls, ['N on', 'N off']);
    c.dispose();
  });

  test('mentre il tasto e\' premuto il movimento viene confermato', () async {
    final b = _FakeBridge();
    final c = SlewController(send: b.send, heartbeat: const Duration(milliseconds: 20));
    c.press('E');
    await _wait(110);
    c.release('E');
    await _wait(60);
    expect(b.calls.first, 'E on');
    expect(b.calls.where((x) => x == 'E beat').length, greaterThanOrEqualTo(3));
    expect(b.calls.last, 'E off');
    final n = b.calls.length;
    await _wait(80);
    expect(b.calls.length, n, reason: 'a riposo non si manda piu\' nulla');
    c.dispose();
  });

  test('uno stop fallito viene ritentato', () async {
    final b = _FakeBridge();
    final c = SlewController(send: b.send, heartbeat: const Duration(milliseconds: 20));
    c.press('S');
    await _wait(5);
    b.failures = 2;
    c.release('S');
    await _wait(120);
    expect(b.calls.last, 'S off');
    c.dispose();
  });

  test('diagonale: due assi indipendenti, stopAll li ferma entrambi', () async {
    final b = _FakeBridge();
    final c = SlewController(send: b.send, heartbeat: const Duration(seconds: 10));
    c.set(ns: 'N', we: 'W');
    await _wait(20);
    c.stopAll();
    await _wait(20);
    expect(b.calls, ['N on', 'W on', 'N off', 'W off']);
    c.dispose();
  });

  test('uscire dalla schermata ferma la montatura', () async {
    final b = _FakeBridge();
    final c = SlewController(send: b.send, heartbeat: const Duration(seconds: 10));
    c.press('W');
    await _wait(20);
    c.dispose();
    await _wait(20);
    expect(b.calls, ['W on', 'W off']);
  });
}
