import 'dart:async';

/// Invia al bridge un movimento manuale: [dir] N/S/E/W, [active] parte/ferma.
/// [beat] e' true per le ripetizioni di un movimento gia' in corso.
typedef SlewSender = Future<void> Function(String dir, bool active, {bool beat});

/// Movimenti manuali della montatura con arresto automatico lato bridge.
///
/// Chi usa questa classe dice solo quale direzione vuole su ciascun asse
/// ([set], [press], [release]). La classe:
///  - manda al bridge partenze e arresti, UNO ALLA VOLTA e nell'ordine giusto:
///    un arresto non puo' mai arrivare prima della partenza che lo precede,
///    altrimenti la montatura ripartirebbe da sola;
///  - mentre un asse si muove ripete il comando ogni [heartbeat], cosi' il
///    bridge (>= 0.9.0, `ttl_ms`) ferma l'asse da solo se le ripetizioni
///    smettono di arrivare: rete che cade, telefono in standby, app chiusa;
///  - se un invio fallisce riprova al giro successivo, finche' lo stato del
///    bridge non coincide con quello voluto.
class SlewController {
  SlewController({
    required this.send,
    this.heartbeat = const Duration(milliseconds: 250),
    this.onError,
  });

  final SlewSender send;
  final Duration heartbeat;
  final void Function(Object error)? onError;

  /// Scadenza chiesta al bridge: quattro ripetizioni perse di fila prima
  /// che fermi l'asse, per non dare scatti al primo pacchetto in ritardo.
  static const int ttlMs = 1000;

  // Direzione voluta e direzione che il bridge potrebbe avere in corso, per
  // asse. "Potrebbe": una partenza e' segnata PRIMA di inviarla, perche' se
  // la risposta si perde il movimento puo' essere partito lo stesso, e al
  // rilascio l'arresto va mandato comunque.
  final Map<String, String?> _want = {'NS': null, 'WE': null};
  final Map<String, String?> _sent = {'NS': null, 'WE': null};

  Timer? _timer;
  bool _busy = false;
  bool _again = false;
  bool _beatDue = false;
  bool _disposed = false;
  DateTime? _giveUpAt;

  String? get ns => _want['NS'];
  String? get we => _want['WE'];
  bool get moving => _want.values.any((d) => d != null);
  bool get _settled =>
      !moving && _sent.values.every((d) => d == null);

  static String _axis(String dir) => (dir == 'N' || dir == 'S') ? 'NS' : 'WE';

  /// Stato completo voluto (controller: croce/levetta).
  void set({String? ns, String? we}) {
    if (_want['NS'] == ns && _want['WE'] == we) return;
    _want['NS'] = ns;
    _want['WE'] = we;
    _kick();
  }

  /// Tasto a schermo premuto.
  void press(String dir) {
    _want[_axis(dir)] = dir;
    _kick();
  }

  /// Tasto a schermo rilasciato.
  void release(String dir) {
    final axis = _axis(dir);
    if (_want[axis] == dir) _want[axis] = null;
    _kick();
  }

  /// Ferma tutti e due gli assi.
  void stopAll() => set();

  /// Attende che gli arresti siano stati consegnati (o falliti).
  Future<void> flush() async {
    while (_busy) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  void dispose() {
    stopAll();
    _disposed = true;
    // Il timer resta vivo finche' gli arresti non sono consegnati: uscire
    // dalla schermata non deve lasciare la montatura in moto. Se il bridge
    // resta irraggiungibile si smette dopo qualche secondo: a quel punto
    // l'asse l'ha gia' fermato lui, allo scadere di [ttlMs].
    _giveUpAt = DateTime.now().add(const Duration(seconds: 5));
  }

  void _kick() {
    _timer ??= Timer.periodic(heartbeat, (_) => _tick());
    _pump();
  }

  void _tick() {
    final giveUp = _giveUpAt;
    if (giveUp != null && DateTime.now().isAfter(giveUp)) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    _beatDue = true;
    _pump();
  }

  Future<void> _pump() async {
    if (_busy) {
      _again = true;
      return;
    }
    _busy = true;
    try {
      do {
        _again = false;
        final beat = _beatDue;
        _beatDue = false;
        for (final axis in const ['NS', 'WE']) {
          await _sync(axis, beat);
        }
      } while (_again);
    } finally {
      _busy = false;
      if (_settled) {
        _timer?.cancel();
        _timer = null;
      }
    }
  }

  Future<void> _sync(String axis, bool beat) async {
    final want = _want[axis];
    final sent = _sent[axis];
    try {
      if (want != null && want != sent) {
        _sent[axis] = want;
        await send(want, true);
      } else if (want == null && sent != null) {
        await send(sent, false);
        // Solo se nel frattempo non e' stato richiesto un nuovo movimento.
        if (_sent[axis] == sent) _sent[axis] = null;
      } else if (want != null && beat && !_disposed) {
        await send(want, true, beat: true);
      }
    } catch (e) {
      // Si riprova al prossimo giro del timer.
      if (!_disposed) onError?.call(e);
    }
  }
}
