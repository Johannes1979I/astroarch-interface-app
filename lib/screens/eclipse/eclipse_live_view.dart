import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/api_client.dart';
import '../../i18n/strings.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../eclipse/eclipse_planner.dart';
import '../../eclipse/eclipse_optimizer.dart';

/// Sezione Eclissi — direttore LIVE (Fase 2, punto 4).
///
/// Invia il piano al conduttore del bridge, arma la camera e la avvia; poi
/// mostra lo stato live (blocco, frame, bias, ultimo frame) e offre gli
/// override "a un tap" (±EV, salta, auto ON/OFF, STOP). Il fire-loop gira nel
/// bridge: se il telefono si disconnette, la totalità continua a scattare.
const double _max16 = 65535.0;

class EclipseLiveView extends StatefulWidget {
  final EclipsePlan plan;
  final double? gain;
  final double? offset;
  /// Camera principale (imaging) rilevata dal setup — usata per gli scatti.
  final String? device;
  /// true = eclissi di LUNA → l'autopuntamento punta la Luna (TRACK_LUNAR).
  final bool isLunar;
  /// Contatti calcolati dal bridge (c1..c4 o p1..p4) — per la sessione a timer.
  final Map<String, dynamic>? contacts;
  const EclipseLiveView(
      {super.key, required this.plan, this.gain, this.offset, this.device,
      this.isLunar = false, this.contacts});

  @override
  State<EclipseLiveView> createState() => _EclipseLiveViewState();
}

class _EclipseLiveViewState extends State<EclipseLiveView> {
  Timer? _poll;
  Map<String, dynamic> _status = {};
  bool _sending = false;
  String? _sendError;
  bool _pointSun = false; // spunta: autopuntamento del Sole all'avvio
  bool _cool = false;      // spunta: raffreddamento camera all'arm
  double _coolTemp = -10.0; // target °C (default richiesto: -10°C)
  bool _simulate = true;    // sessione: simulazione (default ON per i test)
  double _simSpeed = 60;    // compressione tempo in simulazione (×)
  bool _sessionBusy = false;

  @override
  void initState() {
    super.initState();
    _sendPlan();
    _poll = Timer.periodic(const Duration(milliseconds: 1200), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  AppState get _s => context.read<AppState>();

  Future<void> _sendPlan() async {
    if (_s.api == null) {
      setState(() => _sendError = 'Bridge non connesso'.tr(context));
      return;
    }
    setState(() {
      _sending = true;
      _sendError = null;
    });
    try {
      // Usa SEMPRE la camera principale (imaging): quella rilevata dal setup
      // per l'eclissi ha precedenza, poi la selezione/auto dell'AppState.
      final dev = widget.device ?? _s.selectedCamera ?? _s.primaryCameraAuto;
      await _s.api!.eclipsePlan(widget.plan.bridgePayload(
          gain: widget.gain, offset: widget.offset, device: dev));
      await _refresh();
    } on ApiException catch (e) {
      _sendError = e.body;
    } catch (e) {
      _sendError = '$e';
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _refresh() async {
    if (_s.api == null) return;
    try {
      final st = await _s.api!.eclipseStatus();
      if (mounted) setState(() => _status = st);
    } catch (_) {
      /* silenzioso: il banner di connessione della shell copre i disconnessi */
    }
  }

  Future<void> _do(Future<void> Function() fn, String ok) async {
    if (_s.api == null) return;
    try {
      await fn();
      await _refresh();
      if (mounted) showSnack(context, ok);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, '${'Errore: '.tr(context)}${e.body}', error: true);
    } catch (e) {
      if (mounted) showSnack(context, '${'Errore: '.tr(context)}$e', error: true);
    }
  }

  Future<void> _armAndStart() async {
    if (_s.api == null) return;
    await _do(() async {
      await _s.api!.eclipseArm(
          pointSun: !widget.isLunar && _pointSun,
          pointMoon: widget.isLunar && _pointSun,
          cool: _cool,
          coolTemp: _coolTemp);
      await _s.api!.eclipseStart();
    }, 'Direttore avviato'.tr(context));
  }

  /// Offset (secondi dal 1° contatto) di ogni blocco, dai contatti calcolati.
  List<double> _computeOffsets() {
    final blocks = widget.plan.totalityBlocks;
    final c = widget.contacts;
    double? sec(String? k) {
      final s = c?[k] as String?;
      if (s == null) return null;
      final m = RegExp(r'(\d{1,2}):(\d{2}):(\d{2})').firstMatch(s);
      if (m == null) return null;
      return int.parse(m[1]!) * 3600 + int.parse(m[2]!) * 60 + int.parse(m[3]!) + 0.0;
    }
    double diff(double? t, double? a) {
      if (t == null || a == null) return 0;
      var d = t - a;
      if (d < -43200) d += 86400;
      return d < 0 ? 0 : d;
    }
    final anchor = widget.isLunar ? (sec('u1') ?? sec('p1')) : sec('c1');
    double offForKey(String k) {
      if (widget.isLunar) {
        if (k.contains('penumbral')) return diff(sec('p1') ?? anchor, anchor);
        if (k.contains('partial')) return diff(sec('u1'), anchor);
        if (k.contains('total')) return diff(sec('u2'), anchor);
        return 0;
      }
      if (k == 'partial') return diff(sec('c1'), anchor);
      return diff(sec('c2'), anchor); // totalità (Sole)
    }
    final offs = <double>[];
    var fb = 0.0;
    for (final b in blocks) {
      offs.add(anchor == null ? fb : offForKey(b.feature.key));
      fb += 60;
    }
    return offs;
  }

  Future<void> _startSession() async {
    if (_s.api == null) return;
    setState(() => _sessionBusy = true);
    await _do(() async {
      await _s.api!.eclipseSession(
        blockOffsets: _computeOffsets(),
        simulate: _simulate,
        simSpeed: _simSpeed,
        pointSun: !widget.isLunar && _pointSun,
        pointMoon: widget.isLunar && _pointSun,
        cool: _cool,
        coolTemp: _coolTemp,
      );
    }, _simulate
        ? 'Sessione SIMULATA avviata'.tr(context)
        : 'Sessione avviata: attendo il 1° contatto'.tr(context));
    if (mounted) setState(() => _sessionBusy = false);
  }

  String get _phase => (_status['phase'] as String?) ?? 'idle';

  @override
  Widget build(BuildContext context) {
    final running = _phase == 'running';
    return Scaffold(
      appBar: AppBar(title: Text('Eclissi — Direttore live'.tr(context))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 40),
        children: [
          if (_sendError != null) _errBanner(context, _sendError!),
          _phaseHeader(context),
          const SizedBox(height: 10),
          _lastFrameCard(context),
          const SizedBox(height: 10),
          _progressCards(context),
          const SizedBox(height: 16),
          if (!running) _armSection(context),
          if (!running) _sessionSection(context),
          if (running) _overrideSection(context),
          const SizedBox(height: 14),
          _logs(context),
        ],
      ),
    );
  }

  Widget _errBanner(BuildContext c, String msg) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: T.err(c).withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: T.err(c).withValues(alpha: 0.5)),
        ),
        child: Row(children: [
          Icon(Icons.error_outline, color: T.err(c), size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(msg, style: TextStyle(color: T.text(c), fontSize: 12.5))),
          TextButton(onPressed: _sending ? null : _sendPlan, child: Text('RIPROVA'.tr(c))),
        ]),
      );

  Widget _phaseHeader(BuildContext c) {
    final labels = {
      'idle': 'In attesa'.tr(c),
      'planned': 'Piano pronto'.tr(c),
      'armed': 'Armato'.tr(c),
      'cooling': '❄️ Raffreddamento'.tr(c),
      'calibrating': '🎯 Calibrazione'.tr(c),
      'running': 'IN CORSO'.tr(c),
      'done': 'Completato'.tr(c),
      'aborted': 'Interrotto'.tr(c),
    };
    final colors = {
      'running': T.ok(c),
      'cooling': T.accent(c),
      'calibrating': T.warn(c),
      'armed': T.warn(c),
      'aborted': T.err(c),
      'done': T.accent(c),
    };
    const activePhases = {'running', 'cooling', 'calibrating'};
    final col = colors[_phase] ?? T.muted(c);
    final bias = (_status['ev_bias_stops'] as num?)?.toDouble() ?? 0.0;
    final autoOn = _status['auto_enabled'] == true;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: col.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: col.withValues(alpha: 0.5)),
      ),
      child: Row(children: [
        if (activePhases.contains(_phase)) const Padding(
          padding: EdgeInsets.only(right: 10),
          child: LiveDot(),
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(labels[_phase] ?? _phase,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: col)),
            const SizedBox(height: 2),
            Text('${_status['block_label'] ?? '—'}',
                style: TextStyle(fontSize: 12.5, color: T.text(c))),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('Bias ${bias >= 0 ? '+' : ''}${bias.toStringAsFixed(1)} stop',
              style: TextStyle(fontSize: 12, color: T.text(c), fontWeight: FontWeight.w600)),
          Text('Auto ${autoOn ? 'ON' : 'OFF'}',
              style: TextStyle(fontSize: 11, color: autoOn ? T.ok(c) : T.muted(c))),
        ]),
      ]),
    );
  }

  Widget _lastFrameCard(BuildContext c) {
    final s = context.watch<AppState>();
    final jpeg = s.lastFrameJpeg;
    final median = (s.lastFrameMeta['median'] as num?)?.toDouble();
    final vmax = (s.lastFrameMeta['vmax'] as num?)?.toDouble();
    final clipping = vmax != null && vmax / _max16 >= 0.97;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: T.panel(c),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: T.line(c)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.image_outlined, size: 14, color: T.muted(c)),
          const SizedBox(width: 6),
          Text('Ultimo frame'.tr(c),
              style: TextStyle(fontSize: 10.5, color: T.muted(c), letterSpacing: 1.1)),
          const Spacer(),
          if (clipping)
            Text('CLIPPING', style: TextStyle(fontSize: 10, color: T.err(c), fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: AspectRatio(
            aspectRatio: 3 / 2,
            child: jpeg != null
                ? Image.memory(jpeg, fit: BoxFit.contain, gaplessPlayback: true)
                : Container(
                    color: Colors.black.withValues(alpha: 0.25),
                    child: Center(
                      child: Text('Nessun frame ancora'.tr(c),
                          style: TextStyle(color: T.muted(c), fontSize: 12)),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 8),
        _histBar(c, 'Median', median, T.accent(c)),
        const SizedBox(height: 4),
        _histBar(c, 'Picco (vmax)'.tr(c), vmax, clipping ? T.err(c) : T.warn(c)),
      ]),
    );
  }

  Widget _histBar(BuildContext c, String label, double? v, Color col) {
    final frac = (v == null) ? 0.0 : (v / _max16).clamp(0.0, 1.0);
    return Row(children: [
      SizedBox(width: 92, child: Text(label, style: TextStyle(fontSize: 11, color: T.muted(c)))),
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: frac,
            minHeight: 8,
            backgroundColor: T.line(c),
            valueColor: AlwaysStoppedAnimation(col),
          ),
        ),
      ),
      const SizedBox(width: 8),
      SizedBox(
        width: 52,
        child: Text(v == null ? '—' : '${(frac * 100).toStringAsFixed(0)}%',
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 11, color: T.text(c), fontFamily: 'monospace')),
      ),
    ]);
  }

  Widget _progressCards(BuildContext c) {
    final shot = _status['frames_shot'] ?? 0;
    final total = _status['frames_total'] ?? 0;
    final bi = _status['block_index'];
    final bt = _status['blocks_total'] ?? 0;
    final elapsed = (_status['elapsed_sec'] as num?)?.toDouble() ?? 0.0;
    return Row(children: [
      Expanded(child: StatusCard(
        header: 'Frame'.tr(c), value: '$shot / $total', leading: Icons.burst_mode)),
      const SizedBox(width: 8),
      Expanded(child: StatusCard(
        header: 'Blocco'.tr(c),
        value: bi == null || (bi as num) < 0 ? '—' : '${bi + 1} / $bt',
        leading: Icons.view_module_outlined)),
      const SizedBox(width: 8),
      Expanded(child: StatusCard(
        header: 'Tempo'.tr(c), value: '${elapsed.toStringAsFixed(0)}s', leading: Icons.timer_outlined)),
    ]);
  }

  Widget _armSection(BuildContext c) {
    final canStart = _phase != 'idle' && _s.api != null;
    final dev = _s.selectedCamera ?? _s.primaryCameraAuto;
    return Column(children: [
      if (dev != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            Icon(Icons.camera_alt_outlined, size: 14, color: T.muted(c)),
            const SizedBox(width: 6),
            Expanded(
              child: Text('${'Camera'.tr(c)}: $dev',
                  style: TextStyle(fontSize: 12.5, color: T.text(c), fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
      Text(
        'Arma la camera (upload+BLOB) e avvia il conduttore a C2. Il fire-loop resta nel bridge anche se il telefono si disconnette.'
            .tr(c),
        style: TextStyle(fontSize: 12, color: T.muted(c)),
      ),
      const SizedBox(height: 6),
      // Spunta: autopuntamento del Sole all'avvio (scelta dell'utente).
      InkWell(
        onTap: () => setState(() => _pointSun = !_pointSun),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Icon(_pointSun ? Icons.check_box : Icons.check_box_outline_blank,
                size: 20, color: _pointSun ? T.accent(c) : T.muted(c)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                  (widget.isLunar
                          ? '🌙 Autopunta la Luna all\'avvio'
                          : '☀️ Autopunta il Sole all\'avvio')
                      .tr(c),
                  style: TextStyle(fontSize: 13, color: T.text(c))),
            ),
          ]),
        ),
      ),
      if (_pointSun && !widget.isLunar)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            '⚠️ La montatura si muoverà verso il Sole. Tienilo SPENTO per i test notturni (Luna).'
                .tr(c),
            style: TextStyle(fontSize: 10.5, color: T.warn(c)),
          ),
        ),
      // Spunta: raffreddamento camera (scelta utente, default target -10°C).
      InkWell(
        onTap: () => setState(() => _cool = !_cool),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Icon(_cool ? Icons.check_box : Icons.check_box_outline_blank,
                size: 20, color: _cool ? T.accent(c) : T.muted(c)),
            const SizedBox(width: 8),
            Expanded(
              child: Text('❄️ Raffredda la camera'.tr(c),
                  style: TextStyle(fontSize: 13, color: T.text(c))),
            ),
            if (_cool) ...[
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.remove, size: 18),
                onPressed: () => setState(
                    () => _coolTemp = (_coolTemp - 1).clamp(-40.0, 20.0)),
              ),
              Text('${_coolTemp.toStringAsFixed(0)} °C',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: T.text(c))),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.add, size: 18),
                onPressed: () => setState(
                    () => _coolTemp = (_coolTemp + 1).clamp(-40.0, 20.0)),
              ),
            ],
          ]),
        ),
      ),
      if (_cool)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            'La camera inizia a raffreddare quando armi. Arma in anticipo per darle il tempo di scendere in temperatura.'
                .tr(c),
            style: TextStyle(fontSize: 10.5, color: T.muted(c)),
          ),
        ),
      const SizedBox(height: 10),
      PrimaryButton(
        label: 'ARMA E AVVIA (C2)'.tr(c),
        icon: Icons.play_circle_fill,
        color: T.ok(c),
        onPressed: canStart ? _armAndStart : null,
      ),
    ]);
  }

  Widget _sessionSection(BuildContext c) {
    final hasContacts = widget.contacts != null && widget.contacts!.isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: T.accent(c).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: T.accent(c).withValues(alpha: 0.30)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.timer, size: 18, color: T.accent(c)),
          const SizedBox(width: 8),
          Text('Sessione a timer (1° contatto)'.tr(c),
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700, color: T.text(c))),
        ]),
        const SizedBox(height: 6),
        Text(
          'ATTIVA: il sistema attende il 1° contatto, lo conferma con uno scatto (misura la % di ingresso dell\'ombra) e poi spara ogni fase alla sua finestra.'
              .tr(c),
          style: TextStyle(fontSize: 11.5, color: T.muted(c)),
        ),
        if (!hasContacts)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '⚠️ Nessun contatto calcolato nel pianificatore: in simulazione uso una spaziatura fissa tra le fasi.'
                  .tr(c),
              style: TextStyle(fontSize: 10.5, color: T.warn(c)),
            ),
          ),
        InkWell(
          onTap: () => setState(() => _simulate = !_simulate),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              Icon(_simulate ? Icons.check_box : Icons.check_box_outline_blank,
                  size: 20, color: _simulate ? T.accent(c) : T.muted(c)),
              const SizedBox(width: 8),
              Expanded(
                  child: Text('🧪 Simulazione (prova senza eclissi vera)'.tr(c),
                      style: TextStyle(fontSize: 13, color: T.text(c)))),
              if (_simulate)
                Text('×${_simSpeed.toStringAsFixed(0)}',
                    style: TextStyle(fontSize: 12, color: T.muted(c))),
            ]),
          ),
        ),
        if (_simulate)
          Slider(
            value: _simSpeed,
            min: 10,
            max: 300,
            divisions: 29,
            label: '×${_simSpeed.toStringAsFixed(0)}',
            onChanged: (v) => setState(() => _simSpeed = v),
          ),
        const SizedBox(height: 4),
        PrimaryButton(
          label: _simulate ? 'ATTIVA (simulazione)'.tr(c) : 'ATTIVA sessione'.tr(c),
          icon: Icons.timer,
          color: T.accent(c),
          onPressed: (_sessionBusy || _s.api == null) ? null : _startSession,
        ),
      ]),
    );
  }

  Widget _overrideSection(BuildContext c) {
    final autoOn = _status['auto_enabled'] == true;
    return Column(children: [
      Row(children: [
        Expanded(child: _ovBtn(c, '−EV', Icons.remove, () => _do(
            () => _s.api!.eclipseOverride({'ev': -0.5}).then((_) {}), 'EV −0.5'))),
        const SizedBox(width: 8),
        Expanded(child: _ovBtn(c, '+EV', Icons.add, () => _do(
            () => _s.api!.eclipseOverride({'ev': 0.5}).then((_) {}), 'EV +0.5'))),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: _ovBtn(c, 'Salta blocco'.tr(c), Icons.skip_next, () => _do(
            () => _s.api!.eclipseOverride({'skip': true}).then((_) {}), 'Salto blocco'.tr(c)))),
        const SizedBox(width: 8),
        Expanded(child: _ovBtn(
            c, autoOn ? 'Auto OFF' : 'Auto ON', autoOn ? Icons.pause : Icons.autorenew,
            () => _do(() => _s.api!.eclipseOverride({'freeze': autoOn}).then((_) {}),
                'Auto ${autoOn ? 'OFF' : 'ON'}'))),
      ]),
      const SizedBox(height: 12),
      PrimaryButton(
        label: 'STOP'.tr(c),
        icon: Icons.stop_circle,
        color: T.err(c),
        onPressed: () => _do(() => _s.api!.eclipseStop(), 'Fermato'.tr(c)),
      ),
    ]);
  }

  Widget _ovBtn(BuildContext c, String label, IconData icon, VoidCallback onTap) =>
      SizedBox(
        height: 52,
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            foregroundColor: T.text(c),
            side: BorderSide(color: T.line(c)),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 18),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ]),
        ),
      );

  Widget _logs(BuildContext c) {
    final logs = (_status['logs'] as List?)?.cast<String>() ?? const [];
    if (logs.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: T.panel(c),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: T.line(c)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('LOG', style: TextStyle(fontSize: 10, color: T.muted(c), letterSpacing: 1.4)),
        const SizedBox(height: 6),
        for (final l in logs.reversed.take(12))
          Text(l, style: TextStyle(fontSize: 10.5, color: T.text(c), fontFamily: 'monospace')),
      ]),
    );
  }
}
