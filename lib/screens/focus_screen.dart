import 'dart:async';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/api_client.dart';
import '../i18n/strings.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/responsive.dart';

class FocusScreen extends StatefulWidget {
  const FocusScreen({super.key});
  @override
  State<FocusScreen> createState() => _FocusScreenState();
}

class _FocusScreenState extends State<FocusScreen> {
  // Autofocus run state (bridge iterativo)
  String? _runId;
  Map<String, dynamic>? _runStatus;
  Timer? _pollTimer;

  // AF parameters bridge
  int _stepSize = 50;
  int _nSteps = 9;
  double _exposureSec = 2.0;

  // === Ekos autofocus state ===
  Timer? _ekosPollTimer;
  Map<String, dynamic>? _ekosState;
  Map<String, dynamic>? _ekosCurve;
  // Parametri Ekos (opzionali — se nulli il bridge non li forza,
  // Ekos usa quelli configurati nella sua UI)
  int? _ekStepSize;
  int? _ekMaxTravel;
  double? _ekTolerance;

  Future<void> _safe(Future Function() fn, String okMsg) async {
    try { await fn(); if (mounted) showSnack(context, okMsg); }
    on ApiException catch (e) { if (mounted) showSnack(context, '${'Errore: '.tr(context)}${e.body}', error: true); }
    catch (e) { if (mounted) showSnack(context, '${'Errore: '.tr(context)}$e', error: true); }
  }

  Future<void> _move(int steps, String direction) async {
    final s = context.read<AppState>();
    await _safe(() => s.api!.focuserRel(steps, direction), '$direction $steps');
  }

  Future<void> _startAutofocus(AppState s) async {
    if (s.api == null) return;
    try {
      final r = await s.api!.focuserAutofocusStart(
        stepSize: _stepSize, nSteps: _nSteps, exposureSec: _exposureSec,
      );
      _runId = r['run_id'] as String?;
      _runStatus = r;
      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _pollStatus());
      setState(() {});
      if (mounted) showSnack(context, 'Autofocus avviato'.tr(context));
    } on ApiException catch (e) {
      if (mounted) showSnack(context, '${'Errore: '.tr(context)}${e.body}', error: true);
    } catch (e) {
      if (mounted) showSnack(context, '${'Errore: '.tr(context)}$e', error: true);
    }
  }

  Future<void> _pollStatus() async {
    if (_runId == null) return;
    final s = context.read<AppState>();
    try {
      _runStatus = await s.api!.focuserAutofocusStatus(_runId!);
      setState(() {});
      final st = _runStatus!['status'];
      if (st == 'done' || st == 'failed' || st == 'aborted') {
        _pollTimer?.cancel();
      }
    } catch (_) {}
  }

  Future<void> _abortAutofocus() async {
    if (_runId == null) return;
    final s = context.read<AppState>();
    try {
      await s.api!.focuserAutofocusAbort(_runId!);
      if (mounted) showSnack(context, 'Abort autofocus'.tr(context));
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    // Pollo lo stato di Ekos Focus ogni 1.5s. Cattura sia info live
    // (camera/focuser/filter) sia la V-curve via signal newHFR
    // intercettato dal bridge.
    _ekosPollTimer = Timer.periodic(
        const Duration(milliseconds: 1500), (_) => _pollEkosFocus());
    Future.microtask(_pollEkosFocus);
  }

  Future<void> _pollEkosFocus() async {
    final s = context.read<AppState>();
    if (s.api == null) return;
    try {
      final st = await s.api!.focuserEkosState();
      final cv = await s.api!.focuserEkosCurve();
      if (!mounted) return;
      setState(() {
        _ekosState = st;
        _ekosCurve = cv;
      });
    } catch (_) {}
  }

  Future<void> _startEkosAutofocus(AppState s) async {
    if (s.api == null) return;
    try {
      await s.api!.focuserEkosCurveReset();
      await s.api!.focuserEkosStart(
        stepSize: _ekStepSize,
        maxTravel: _ekMaxTravel,
        tolerance: _ekTolerance,
      );
      if (mounted) showSnack(context, 'Autofocus Ekos avviato'.tr(context));
      _pollEkosFocus();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, '${'Errore: '.tr(context)}${_extractDetail(e.body)}', error: true);
    } catch (e) {
      if (mounted) showSnack(context, '${'Errore: '.tr(context)}$e', error: true);
    }
  }

  Future<void> _abortEkosAutofocus(AppState s) async {
    if (s.api == null) return;
    try {
      await s.api!.focuserEkosAbort();
      if (mounted) showSnack(context, 'Abort Ekos AF'.tr(context));
      _pollEkosFocus();
    } catch (e) {
      if (mounted) showSnack(context, '${'Errore: '.tr(context)}$e', error: true);
    }
  }

  String _extractDetail(String body) {
    try {
      final j = body.startsWith('{') ? body : null;
      if (j == null) return body;
      final m = RegExp(r'"detail"\s*:\s*"([^"]+)"').firstMatch(body);
      return m?.group(1) ?? body;
    } catch (_) { return body; }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _ekosPollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final f = s.focuserDevice();
    final pos = f == null ? null : s.prop(f, 'ABS_FOCUS_POSITION');
    final temp = f == null ? null : s.prop(f, 'FOCUS_TEMPERATURE');
    final position = (propValue(pos, 'FOCUS_ABSOLUTE_POSITION') as num?)?.toInt();
    final maxPos = _max(pos, 'FOCUS_ABSOLUTE_POSITION');
    final t = (propValue(temp, 'TEMPERATURE') as num?)?.toDouble();

    return Scaffold(
      appBar: AppBar(title: Text(f == null ? 'Focus'.tr(context) : '${'Focus'.tr(context)} · $f')),
      body: f == null
          ? Center(child: Text('Nessun focuser connesso'.tr(context), style: TextStyle(color: T.muted(context))))
          : AdaptiveListView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 80),
              children: [
                // Altezza secondo il contenuto (non piu' 3 colonne fisse a
                // ratio 1.7): 2-3 colonne su telefono, fino a 6 su monitor.
                AdaptiveGrid(
                  minTileWidth: 110,
                  maxColumns: 6,
                  spacing: 6,
                  children: [
                    StatusCard(header: 'POSITION'.tr(context), value: position?.toString() ?? '—',
                        subtitle: maxPos == null ? null : '${'max'.tr(context)} ${maxPos.toInt()}'),
                    StatusCard(header: 'TEMP'.tr(context),
                        value: t == null ? '—' : '${t.toStringAsFixed(1)}°', subtitle: 'sensor'.tr(context)),
                    StatusCard(header: 'STATE'.tr(context), value: pos?['state'] ?? '—',
                        subtitle: pos?['state'] == 'Busy' ? 'moving'.tr(context) : 'idle'.tr(context),
                        badgeColor: pos?['state'] == 'Busy' ? T.accent(context) : T.muted(context),
                        badgeText: pos?['state'] == 'Busy' ? 'mov' : 'idle'),
                  ],
                ),
                SectionLabel('Movimento manuale (rel)'.tr(context)),
                Row(children: [
                  Expanded(child: GhostButton(label: '−1000', small: true, onPressed: () => _move(1000, 'in'))),
                  const SizedBox(width: 4),
                  Expanded(child: GhostButton(label: '−100', small: true, onPressed: () => _move(100, 'in'))),
                  const SizedBox(width: 4),
                  Expanded(child: GhostButton(label: '−10', small: true, onPressed: () => _move(10, 'in'))),
                ]),
                const SizedBox(height: 4),
                Row(children: [
                  Expanded(child: GhostButton(label: '+10', small: true, onPressed: () => _move(10, 'out'))),
                  const SizedBox(width: 4),
                  Expanded(child: GhostButton(label: '+100', small: true, onPressed: () => _move(100, 'out'))),
                  const SizedBox(width: 4),
                  Expanded(child: GhostButton(label: '+1000', small: true, onPressed: () => _move(1000, 'out'))),
                ]),
                SectionLabel('Posizione assoluta'.tr(context)),
                _absInput(s, position),
                // ====== EKOS AUTOFOCUS (preferito) ======
                SectionLabel('Autofocus Ekos'.tr(context)),
                _ekosInfoCard(s),
                const SizedBox(height: 8),
                _ekosLastFrameCard(s),
                const SizedBox(height: 8),
                _ekosParamsCard(),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: PrimaryButton(
                    label: _isEkosAfRunning()
                        ? 'EKOS AUTOFOCUS IN CORSO…'.tr(context)
                        : 'AVVIA AUTOFOCUS EKOS'.tr(context),
                    icon: Icons.auto_awesome,
                    onPressed: _isEkosAfRunning() ? null
                        : () => _startEkosAutofocus(s),
                  )),
                  const SizedBox(width: 8),
                  Expanded(child: GhostButton(
                    label: 'ABORT'.tr(context), icon: Icons.stop, danger: true,
                    onPressed: _isEkosAfRunning()
                        ? () => _abortEkosAutofocus(s) : null,
                  )),
                ]),
                const SizedBox(height: 8),
                if (_ekosCurve != null) _ekosVCurveCard(),
                const SizedBox(height: 4),
                if (_ekosCurve != null) _ekosLogCard(),

                // ====== AUTOFOCUS ITERATIVO BRIDGE (legacy/manuale) ======
                SectionLabel('Autofocus iterativo (bridge)'.tr(context)),
                _autofocusParams(),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: PrimaryButton(
                    label: _isAfRunning() ? 'IN CORSO…'.tr(context) : 'AVVIA AUTOFOCUS'.tr(context),
                    icon: Icons.center_focus_strong,
                    onPressed: _isAfRunning() ? null : () => _startAutofocus(s),
                  )),
                  const SizedBox(width: 8),
                  Expanded(child: GhostButton(
                    label: 'ABORT'.tr(context), icon: Icons.stop, danger: true,
                    onPressed: _isAfRunning() ? _abortAutofocus : null,
                  )),
                ]),
                if (_runStatus != null) ...[
                  const SizedBox(height: 12),
                  _runStatusCard(),
                  SectionLabel('V-Curve'.tr(context)),
                  _vCurveChart(),
                ],
                SectionLabel('Manuale rapido'.tr(context)),
                Row(children: [
                  Expanded(child: GhostButton(
                    label: 'ABORT motion'.tr(context), icon: Icons.stop, danger: true,
                    onPressed: () => _safe(() => s.api!.focuserAbort(), 'Abort'.tr(context)),
                  )),
                ]),
              ],
            ),
    );
  }

  bool _isAfRunning() {
    final st = _runStatus?['status'];
    return st == 'running' || st == 'aborting';
  }

  // === EKOS UI helpers ===

  bool _isEkosAfRunning() {
    // status_label di Ekos: idle/complete/failed/aborted/waiting/progress/
    // frame_adjusted/framing/changing. "Running" = progress|framing|
    // waiting|frame_adjusted|changing.
    final lbl = _ekosCurve?['last_status_label']?.toString()
        ?? _ekosState?['status_label']?.toString() ?? '';
    return lbl == 'progress' || lbl == 'framing' || lbl == 'waiting'
        || lbl == 'frame_adjusted' || lbl == 'changing';
  }

  Widget _ekosInfoCard(AppState s) {
    final e = _ekosState;
    if (e == null) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: T.panel(context), borderRadius: BorderRadius.circular(10),
          border: Border.all(color: T.line(context)),
        ),
        child: Row(children: [
          const SizedBox(width: 14, height: 14,
              child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 10),
          Text('Lettura impostazioni da Ekos…'.tr(context),
              style: TextStyle(color: T.muted(context), fontSize: 12)),
        ]),
      );
    }
    final canAf = e['can_autofocus'] == true;
    final statusLbl = (e['status_label'] ?? 'unknown').toString();
    Color statusColor;
    switch (statusLbl) {
      case 'complete': statusColor = T.ok(context); break;
      case 'failed': case 'aborted': statusColor = T.err(context); break;
      case 'progress': case 'framing': case 'waiting':
      case 'frame_adjusted': case 'changing':
        statusColor = T.accent(context); break;
      default: statusColor = T.muted(context);
    }
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: T.panel(context), borderRadius: BorderRadius.circular(10),
        border: Border.all(color: T.line(context)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('IMPOSTAZIONI EKOS (live)'.tr(context),
              style: TextStyle(color: T.muted(context), fontSize: 10,
                  letterSpacing: 1.4, fontWeight: FontWeight.w700)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: statusColor.withValues(alpha: 0.6)),
            ),
            child: Text(statusLbl.toUpperCase(),
                style: TextStyle(color: statusColor, fontSize: 10,
                    fontWeight: FontWeight.w700, letterSpacing: .8)),
          ),
        ]),
        const SizedBox(height: 6),
        _kv('Camera', e['camera']?.toString() ?? '—'),
        _kv('Focuser', e['focuser']?.toString() ?? '—'),
        _kv('Filter wheel', e['filter_wheel']?.toString() ?? '—'),
        _kv('Filter', e['filter']?.toString() ?? '—'),
        const SizedBox(height: 4),
        Row(children: [
          Icon(canAf ? Icons.check_circle : Icons.error,
              size: 12, color: canAf ? T.ok(context) : T.err(context)),
          const SizedBox(width: 4),
          Text(canAf
              ? 'Ekos pronto per autofocus'.tr(context)
              : 'Ekos NON pronto (manca camera/focuser?)'.tr(context),
              style: TextStyle(fontSize: 11,
                  color: canAf ? T.ok(context) : T.err(context))),
          const Spacer(),
          if (e['monitor_running'] == true)
            Text('● live'.tr(context), style: TextStyle(
                fontSize: 10, color: T.ok(context))),
        ]),
      ]),
    );
  }

  Widget _ekosLastFrameCard(AppState s) {
    // Riusa il frame BLOB intercept (lo stesso flusso usato da Plate Solve).
    // Durante l'autofocus Ekos cattura sulla camera primaria, e il bridge
    // intercetta i BLOB via enableBLOB Also.
    final hasFrame = s.lastFrameJpeg != null;
    final m = s.lastFrameMeta;
    return Container(
      decoration: BoxDecoration(
        color: Colors.black, borderRadius: BorderRadius.circular(10),
        border: Border.all(color: T.line(context)),
      ),
      clipBehavior: Clip.antiAlias,
      // Limitata in altezza su schermo largo.
      child: AdaptivePreview(
        aspectRatio: 1.7,
        child: Stack(fit: StackFit.expand, children: [
          if (hasFrame)
            InteractiveViewer(minScale: 1, maxScale: 5,
              child: Image.memory(s.lastFrameJpeg!, fit: BoxFit.contain,
                  gaplessPlayback: true))
          else
            Center(child: Text('Nessuna immagine ancora'.tr(context),
                style: TextStyle(color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 12))),
          if (hasFrame) Positioned(top: 6, right: 6, child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(color: Colors.black54,
                borderRadius: BorderRadius.circular(4)),
            child: Text(
              'HFR ${(m['hfr'] as num?)?.toStringAsFixed(2) ?? "—"} · '
              '★ ${m['stars'] ?? "—"}',
              style: const TextStyle(color: Colors.white,
                  fontFamily: 'monospace', fontSize: 9),
            ),
          )),
        ]),
      ),
    );
  }

  Widget _ekosParamsCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: T.panel(context), borderRadius: BorderRadius.circular(10),
        border: Border.all(color: T.line(context)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('PARAMETRI EKOS (override opzionali)'.tr(context),
              style: TextStyle(color: T.muted(context), fontSize: 10,
                  letterSpacing: 1.4, fontWeight: FontWeight.w700)),
          const Spacer(),
          if (_ekStepSize != null || _ekMaxTravel != null || _ekTolerance != null)
            TextButton(
              onPressed: () => setState(() {
                _ekStepSize = null; _ekMaxTravel = null; _ekTolerance = null;
              }),
              child: Text('USA QUELLI DI EKOS'.tr(context),
                  style: TextStyle(fontSize: 10, color: T.accent(context))),
            ),
        ]),
        const SizedBox(height: 4),
        Text(
          (_ekStepSize == null && _ekMaxTravel == null && _ekTolerance == null)
              ? 'L\'autofocus usa i parametri configurati in Ekos sul desktop.'.tr(context)
              : 'Override attivi: l\'app li imposta in Ekos prima di Start.'.tr(context),
          style: TextStyle(color: T.muted(context), fontSize: 11,
              fontStyle: FontStyle.italic),
        ),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(child: _slider('Step size'.tr(context),
              (_ekStepSize ?? 250).toDouble(), 50, 1000,
              (v) => setState(() => _ekStepSize = v.toInt()),
              formatter: (v) => v.toStringAsFixed(0))),
        ]),
        Row(children: [
          Expanded(child: _slider('Max travel'.tr(context),
              (_ekMaxTravel ?? 10000).toDouble(), 1000, 50000,
              (v) => setState(() => _ekMaxTravel = v.toInt()),
              formatter: (v) => v.toStringAsFixed(0))),
        ]),
        Row(children: [
          Expanded(child: _slider('Tolerance (%)'.tr(context),
              (_ekTolerance ?? 1.0), 0.1, 10.0,
              (v) => setState(() => _ekTolerance = v),
              formatter: (v) => '${v.toStringAsFixed(1)}%')),
        ]),
      ]),
    );
  }

  Widget _ekosVCurveCard() {
    final samples = (_ekosCurve?['samples'] as List? ?? []).cast<Map>();
    if (samples.isEmpty) {
      return Container(
        height: 140,
        decoration: BoxDecoration(
          color: T.panel(context), borderRadius: BorderRadius.circular(10),
          border: Border.all(color: T.line(context)),
        ),
        child: Center(child: Text('V-curve apparirà qui durante l\'autofocus'.tr(context),
            style: TextStyle(color: T.muted(context), fontSize: 12))),
      );
    }
    final spots = <FlSpot>[];
    double minHfr = double.infinity, maxHfr = 0;
    int? minPos, maxPos;
    for (final s in samples) {
      final p = (s['position'] as num?)?.toInt();
      final h = (s['hfr'] as num?)?.toDouble();
      if (p == null || h == null) continue;
      spots.add(FlSpot(p.toDouble(), h));
      if (h < minHfr) minHfr = h;
      if (h > maxHfr) maxHfr = h;
      if (minPos == null || p < minPos) minPos = p;
      if (maxPos == null || p > maxPos) maxPos = p;
    }
    if (spots.isEmpty) {
      return const SizedBox();
    }
    final best = samples.reduce((a, b) =>
        ((a['hfr'] as num) < (b['hfr'] as num)) ? a : b);
    final bestPos = (best['position'] as num).toInt();
    final bestHfr = (best['hfr'] as num).toDouble();

    return Container(
      height: 200,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: T.panel(context), borderRadius: BorderRadius.circular(10),
        border: Border.all(color: T.line(context)),
      ),
      child: Column(children: [
        Row(children: [
          Text('V-CURVE EKOS · ${spots.length} pt'.tr(context),
              style: TextStyle(color: T.muted(context), fontSize: 10,
                  letterSpacing: 1.4, fontWeight: FontWeight.w700)),
          const Spacer(),
          Text('best: pos $bestPos HFR ${bestHfr.toStringAsFixed(2)}',
              style: TextStyle(color: T.ok(context), fontSize: 11,
                  fontFamily: 'monospace', fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 4),
        Expanded(child: LineChart(LineChartData(
          minY: 0,
          maxY: maxHfr * 1.15,
          gridData: const FlGridData(show: false),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(sideTitles: SideTitles(
              showTitles: true, reservedSize: 28,
              getTitlesWidget: (v, _) => Text(v.toStringAsFixed(1),
                  style: TextStyle(color: T.muted(context), fontSize: 9,
                      fontFamily: 'monospace')),
            )),
            bottomTitles: AxisTitles(sideTitles: SideTitles(
              showTitles: true, reservedSize: 18,
              getTitlesWidget: (v, _) => Text(v.toInt().toString(),
                  style: TextStyle(color: T.muted(context), fontSize: 9,
                      fontFamily: 'monospace')),
            )),
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
          ),
          borderData: FlBorderData(show: false),
          extraLinesData: ExtraLinesData(verticalLines: [
            VerticalLine(x: bestPos.toDouble(),
                color: T.ok(context).withValues(alpha: 0.7),
                strokeWidth: 1.5, dashArray: [4, 3]),
          ]),
          lineBarsData: [LineChartBarData(
            spots: spots,
            isCurved: false,
            color: T.accent(context),
            barWidth: 1.5,
            dotData: FlDotData(show: true,
              getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
                  radius: 3, color: T.accent(context),
                  strokeWidth: 0)),
          )],
        ))),
      ]),
    );
  }

  Widget _ekosLogCard() {
    final log = (_ekosCurve?['log_tail'] as List? ?? []).cast<String>();
    if (log.isEmpty) return const SizedBox();
    return Container(
      padding: const EdgeInsets.all(8),
      constraints: const BoxConstraints(maxHeight: 100),
      decoration: BoxDecoration(
        color: const Color(0xFF05080e),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: T.line(context)),
      ),
      child: SingleChildScrollView(
        reverse: true,
        child: Text(log.join('\n'),
            style: const TextStyle(fontFamily: 'monospace',
                fontSize: 10, color: Color(0xFF9aa3b6), height: 1.4)),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(children: [
          SizedBox(width: 100, child: Text('$k:',
              style: TextStyle(color: T.muted(context), fontSize: 11))),
          Expanded(child: Text(v,
              style: const TextStyle(fontSize: 12,
                  fontFamily: 'monospace', fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis)),
        ]),
      );

  Widget _autofocusParams() {
    return Column(children: [
      Row(children: [
        Expanded(child: _slider('Step size'.tr(context), _stepSize.toDouble(), 5, 500,
            (v) => setState(() => _stepSize = v.toInt()), formatter: (v) => v.toStringAsFixed(0))),
      ]),
      Row(children: [
        Expanded(child: _slider('N step (dispari)'.tr(context), _nSteps.toDouble(), 5, 21,
            (v) => setState(() => _nSteps = (v.toInt() % 2 == 0 ? v.toInt() + 1 : v.toInt())),
            formatter: (v) => '${v.toInt()}')),
      ]),
      Row(children: [
        Expanded(child: _slider('Esposizione (s)'.tr(context), _exposureSec, 0.5, 10,
            (v) => setState(() => _exposureSec = v),
            formatter: (v) => '${v.toStringAsFixed(1)}s')),
      ]),
    ]);
  }

  Widget _slider(String label, double v, double min, double max,
      ValueChanged<double> onChanged, {required String Function(double) formatter}) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      decoration: BoxDecoration(
        color: T.panel(context), borderRadius: BorderRadius.circular(10),
        border: Border.all(color: T.line(context)),
      ),
      child: Column(children: [
        Row(children: [
          Text(label.toUpperCase(),
              style: TextStyle(color: T.muted(context), fontSize: 10, letterSpacing: 1.2)),
          const Spacer(),
          Text(formatter(v),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
          ),
          child: Slider(value: v.clamp(min, max), min: min, max: max, onChanged: onChanged),
        ),
      ]),
    );
  }

  Widget _runStatusCard() {
    final r = _runStatus!;
    final samples = (r['samples'] as List? ?? []);
    final stepIdx = r['step_idx'] ?? 0;
    final n = r['n_steps'] ?? _nSteps;
    final st = r['status'];
    Color color;
    switch (st) {
      case 'done': color = T.ok(context); break;
      case 'failed': color = T.err(context); break;
      case 'running': color = T.accent(context); break;
      default: color = T.muted(context);
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: T.panel(context), borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(st == 'running' ? Icons.sync : (st == 'done' ? Icons.check_circle : Icons.info),
              color: color, size: 16),
          const SizedBox(width: 6),
          Text('${'Run'.tr(context)}: $st', style: TextStyle(color: color, fontWeight: FontWeight.w700)),
          const Spacer(),
          Text('$stepIdx/$n', style: TextStyle(color: T.muted(context), fontFamily: 'monospace')),
        ]),
        if (r['best_pos'] != null) Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            '${'Best position'.tr(context)}: ${r['best_pos']} (HFR ${(r['best_hfr'] as num).toStringAsFixed(2)})',
            style: TextStyle(color: T.ok(context), fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
        if (r['error'] != null) Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('⚠ ${r['error']}', style: TextStyle(color: T.err(context), fontSize: 11)),
        ),
        const SizedBox(height: 4),
        Text('${samples.length} ${'sample raccolti'.tr(context)}',
            style: TextStyle(color: T.muted(context), fontSize: 11)),
      ]),
    );
  }

  Widget _vCurveChart() {
    final samples = (_runStatus?['samples'] as List? ?? []).cast<Map>();
    if (samples.isEmpty) {
      return Container(
        height: 180,
        decoration: BoxDecoration(
          color: T.panel(context), borderRadius: BorderRadius.circular(10),
          border: Border.all(color: T.line(context)),
        ),
        child: Center(child: Text('No data yet'.tr(context), style: TextStyle(color: T.muted(context)))),
      );
    }
    final spots = <FlSpot>[];
    double minHfr = double.infinity;
    double maxHfr = 0;
    for (final s in samples) {
      final p = (s['pos'] as num?)?.toDouble();
      final h = (s['hfr'] as num?)?.toDouble();
      if (p == null || h == null || h <= 0) continue;
      spots.add(FlSpot(p, h));
      if (h < minHfr) minHfr = h;
      if (h > maxHfr) maxHfr = h;
    }
    if (spots.isEmpty) {
      return SizedBox(height: 180, child: Center(child: Text('No HFR detected'.tr(context),
          style: TextStyle(color: T.muted(context)))));
    }
    final bestPos = (_runStatus?['best_pos'] as num?)?.toDouble();
    return Container(
      height: 180,
      padding: const EdgeInsets.fromLTRB(10, 14, 14, 6),
      decoration: BoxDecoration(
        color: T.panel(context), borderRadius: BorderRadius.circular(10),
        border: Border.all(color: T.line(context)),
      ),
      child: LineChart(LineChartData(
        gridData: const FlGridData(show: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 28,
              getTitlesWidget: (v, _) => Text(v.toStringAsFixed(1),
                  style: TextStyle(color: T.muted(context), fontSize: 9)))),
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 18,
              getTitlesWidget: (v, _) => Text(v.toStringAsFixed(0),
                  style: TextStyle(color: T.muted(context), fontSize: 9)))),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots, isCurved: true, color: T.accent(context), barWidth: 2,
            dotData: FlDotData(show: true, getDotPainter: (s, p, b, i) =>
                FlDotCirclePainter(color: T.accent(context), radius: 3, strokeWidth: 0)),
          ),
        ],
        extraLinesData: bestPos == null ? null : ExtraLinesData(verticalLines: [
          VerticalLine(x: bestPos, color: T.ok(context), strokeWidth: 1, dashArray: [4, 4]),
        ]),
      )),
    );
  }

  Widget _absInput(AppState s, int? cur) {
    final ctl = TextEditingController(text: cur?.toString() ?? '');
    return Row(children: [
      Expanded(child: TextField(
        controller: ctl, keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: 'Posizione'.tr(context), isDense: true),
      )),
      const SizedBox(width: 8),
      SizedBox(width: 100, child: PrimaryButton(label: 'GO', icon: Icons.send, small: true,
          onPressed: () async {
            final v = int.tryParse(ctl.text);
            if (v == null) {
              showSnack(context, 'Numero non valido'.tr(context), error: true);
              return;
            }
            await _safe(() => s.api!.focuserAbs(v), '${'Vai a'.tr(context)} $v');
          })),
    ]);
  }

  num? _max(Map<String, dynamic>? prop, String name) {
    for (final e in (prop?['elements'] as List? ?? [])) {
      if (e['name'] == name) return e['max'] as num?;
    }
    return null;
  }
}
