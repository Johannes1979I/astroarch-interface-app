import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../i18n/strings.dart';
import '../mount/gamepad_input.dart';
import '../mount/slew_controller.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

/// Telecomando della montatura con un controller Bluetooth (Xbox e simili)
/// abbinato al telefono.
///
/// Muove solo AR e Dec, alla velocita' selezionata nel driver (quella che
/// Ekos mostra): il telecomando non cambia nessuna impostazione. Croce o
/// levetta sinistra muovono, rilasciando si ferma, B e' lo STOP.
class MountRemoteScreen extends StatefulWidget {
  const MountRemoteScreen({super.key});
  @override
  State<MountRemoteScreen> createState() => _MountRemoteScreenState();
}

class _MountRemoteScreenState extends State<MountRemoteScreen> {
  static const _kInvertNS = 'remote_invert_ns';
  static const _kInvertEW = 'remote_invert_ew';

  late final AppState _app;
  late final SlewController _slew;
  StreamSubscription<GamepadState>? _sub;
  AppLifecycleListener? _life;

  GamepadState _pad = const GamepadState();
  bool _invertNS = false;
  bool _invertEW = false;
  // Dopo uno STOP le direzioni sono ignorate finche' non si rilascia tutto:
  // tenendo premuta la croce mentre si preme B la montatura non deve ripartire.
  bool _stopLatched = false;
  String? _bridgeVersion;
  bool? _guarded;
  String? _lastError;

  @override
  void initState() {
    super.initState();
    _app = context.read<AppState>();
    _slew = SlewController(send: _send, onError: (e) {
      if (mounted) setState(() => _lastError = '$e');
    });
    // Telefono che si blocca, notifica aperta, app in secondo piano:
    // la montatura si ferma.
    _life = AppLifecycleListener(
      onInactive: _slew.stopAll, onHide: _slew.stopAll, onPause: _slew.stopAll,
    );
    _sub = GamepadInput.states().listen(_onPad);
    GamepadInput.keepScreenOn(true);
    _loadPrefs();
    _checkBridge();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _life?.dispose();
    _slew.dispose();
    GamepadInput.keepScreenOn(false);
    super.dispose();
  }

  Future<void> _send(String dir, bool active, {bool beat = false}) async {
    final api = _app.api;
    if (api == null) throw StateError('Bridge non connesso');
    await api.mountSlewGuarded(
        dir: dir, active: active, ttlMs: SlewController.ttlMs, beat: beat);
    if (_lastError != null && mounted) setState(() => _lastError = null);
  }

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _invertNS = p.getBool(_kInvertNS) ?? false;
      _invertEW = p.getBool(_kInvertEW) ?? false;
    });
  }

  Future<void> _savePref(String key, bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(key, v);
  }

  /// L'arresto automatico c'e' solo dal bridge 0.9.0: con uno piu' vecchio
  /// il telecomando funziona, ma bisogna saperlo.
  Future<void> _checkBridge() async {
    try {
      final info = await _app.api?.info();
      final v = info?['version']?.toString();
      if (!mounted || v == null) return;
      setState(() {
        _bridgeVersion = v;
        _guarded = _atLeast(v, const [0, 9, 0]);
      });
    } catch (_) {
      // Nessuna informazione: nessun avviso, meglio che uno sbagliato.
    }
  }

  static bool _atLeast(String v, List<int> min) {
    final parts = v.split(RegExp(r'[^0-9]+')).where((s) => s.isNotEmpty)
        .map(int.parse).toList();
    for (var i = 0; i < min.length; i++) {
      final p = i < parts.length ? parts[i] : 0;
      if (p != min[i]) return p > min[i];
    }
    return true;
  }

  void _onPad(GamepadState p) {
    final bPressed = p.buttons.contains('B') && !_pad.buttons.contains('B');
    setState(() => _pad = p);
    if (bPressed) {
      _emergencyStop();
      return;
    }
    final anyDir = p.up || p.down || p.left || p.right;
    if (_stopLatched) {
      if (anyDir) return;
      setState(() => _stopLatched = false);
    }
    String? ns = p.up == p.down ? null : (p.up ? 'N' : 'S');
    String? we = p.left == p.right ? null : (p.left ? 'W' : 'E');
    if (_invertNS && ns != null) ns = ns == 'N' ? 'S' : 'N';
    if (_invertEW && we != null) we = we == 'W' ? 'E' : 'W';
    _slew.set(ns: ns, we: we);
  }

  Future<void> _emergencyStop() async {
    setState(() => _stopLatched = true);
    _slew.stopAll();
    try {
      await _app.api?.mountAbort();
      if (mounted) showSnack(context, 'STOP');
    } catch (e) {
      if (mounted) showSnack(context, '${'Errore: '.tr(context)}$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final m = s.mountDevice();
    final rates = m == null ? null : s.prop(m, 'TELESCOPE_SLEW_RATE');
    final coord = m == null ? null : s.prop(m, 'EQUATORIAL_EOD_COORD');
    final ra = (propValue(coord, 'RA') as num?)?.toDouble();
    final dec = (propValue(coord, 'DEC') as num?)?.toDouble();

    return Scaffold(
      appBar: AppBar(
        title: Text(m == null ? 'Telecomando'.tr(context) : '${'Telecomando'.tr(context)} · $m'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 40),
        children: [
          if (!GamepadInput.supported)
            _notice(Icons.info_outline, T.muted(context),
                'Il controller funziona solo nell\'app Android.'.tr(context)),
          if (_guarded == false)
            _notice(Icons.warning_amber, T.warn(context),
                'Bridge {0}: manca l\'arresto automatico (serve la 0.9.0). Se la connessione cade durante un movimento, la montatura non si ferma da sola.'
                    .trFmt(context, [_bridgeVersion ?? '?'])),
          if (m == null)
            _notice(Icons.info_outline, T.muted(context),
                'Nessun mount connesso ad Ekos.'.tr(context)),
          _controllerCard(),
          const SizedBox(height: 18),
          Center(child: _cross()),
          const SizedBox(height: 10),
          Center(child: Text(
            '${'Velocità (da Ekos)'.tr(context)}: ${_selectedLabel(rates) ?? '—'}',
            style: TextStyle(color: T.muted(context), fontSize: 12),
          )),
          if (ra != null && dec != null)
            Center(child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('RA ${_hms(ra)}   Dec ${_dms(dec)}',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
            )),
          if (_lastError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('${'Errore: '.tr(context)}$_lastError',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: T.err(context), fontSize: 12)),
            ),
          const SizedBox(height: 18),
          SizedBox(
            height: 56,
            child: GhostButton(label: 'STOP', icon: Icons.stop, danger: true,
                onPressed: _emergencyStop),
          ),
          SectionLabel('Tasti'.tr(context)),
          _legend('✚ / L', 'Croce o levetta sinistra: muove la montatura, rilasciando si ferma'.tr(context)),
          _legend('B', 'STOP: ferma subito ogni movimento, anche un GoTo'.tr(context)),
          SectionLabel('Direzioni'.tr(context)),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Inverti Nord/Sud'.tr(context)),
            value: _invertNS,
            onChanged: (v) {
              setState(() => _invertNS = v);
              _savePref(_kInvertNS, v);
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Inverti Est/Ovest'.tr(context)),
            value: _invertEW,
            onChanged: (v) {
              setState(() => _invertEW = v);
              _savePref(_kInvertEW, v);
            },
          ),
        ],
      ),
    );
  }

  Widget _notice(IconData icon, Color color, String text) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: T.panel(context), borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ]),
      );

  Widget _controllerCard() {
    final connected = _pad.connected;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: T.panel(context), borderRadius: BorderRadius.circular(14),
        border: Border.all(color: connected ? T.ok(context) : T.line(context)),
      ),
      child: Row(children: [
        Icon(Icons.sports_esports, size: 28,
            color: connected ? T.ok(context) : T.muted(context)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(connected ? _pad.devices.join(', ') : 'Nessun controller'.tr(context),
              style: const TextStyle(fontWeight: FontWeight.w600)),
          if (!connected) ...[
            const SizedBox(height: 4),
            Text('Abbinalo dalle impostazioni Bluetooth del telefono: tieni premuto il tasto di abbinamento del controller finché il logo lampeggia veloce.'
                    .tr(context),
                style: TextStyle(color: T.muted(context), fontSize: 12)),
          ],
        ])),
      ]),
    );
  }

  Widget _cross() {
    Widget cell(String dir, String label) {
      final on = _slew.ns == dir || _slew.we == dir;
      return Container(
        width: 64, height: 64,
        decoration: BoxDecoration(
          color: on ? T.accent(context).withValues(alpha: 0.35) : T.panel(context),
          border: Border.all(color: on ? T.accent(context) : T.line(context), width: on ? 2 : 1),
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.center,
        child: Text(label, style: TextStyle(
            fontSize: 20, fontWeight: FontWeight.w700,
            color: on ? T.accent(context) : T.text(context))),
      );
    }
    const gap = SizedBox(width: 64, height: 64);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Row(mainAxisSize: MainAxisSize.min, children: [gap, cell('N', 'N'), gap]),
      Row(mainAxisSize: MainAxisSize.min, children: [
        cell('W', 'W'),
        SizedBox(width: 64, height: 64, child: Center(child: Icon(
            _stopLatched ? Icons.block : Icons.adjust,
            color: _stopLatched ? T.err(context) : T.muted(context)))),
        cell('E', 'E'),
      ]),
      Row(mainAxisSize: MainAxisSize.min, children: [gap, cell('S', 'S'), gap]),
    ]);
  }

  Widget _legend(String key, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 56, child: Text(key,
              style: TextStyle(color: T.accent(context), fontWeight: FontWeight.w700))),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ]),
      );

  String? _selectedLabel(Map<String, dynamic>? rates) {
    for (final e in (rates?['elements'] as List? ?? const [])) {
      if (e['value'] == true) return (e['label'] ?? e['name']).toString();
    }
    return null;
  }

  String _hms(double hours) {
    final h = hours.floor();
    final m = ((hours - h) * 60).floor();
    final s = (((hours - h) * 60 - m) * 60).round();
    return '${h.toString().padLeft(2, '0')}h ${m.toString().padLeft(2, '0')}m ${s.toString().padLeft(2, '0')}s';
  }

  String _dms(double deg) {
    final sign = deg < 0 ? '-' : '+';
    final a = deg.abs();
    final d = a.floor();
    final m = ((a - d) * 60).floor();
    final s = (((a - d) * 60 - m) * 60).round();
    return '$sign${d.toString().padLeft(2, '0')}° ${m.toString().padLeft(2, '0')}′ ${s.toString().padLeft(2, '0')}″';
  }
}
