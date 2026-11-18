import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/api_client.dart';
import '../../i18n/strings.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/responsive.dart';

/// Tab Polar Align: routine drift-based 3-step.
class PolarAlignTab extends StatefulWidget {
  const PolarAlignTab({super.key});
  @override
  State<PolarAlignTab> createState() => _PolarAlignTabState();
}

class _PolarAlignTabState extends State<PolarAlignTab> {
  String? _runId;
  Map<String, dynamic>? _runStatus;
  Timer? _pollTimer;
  bool _busy = false;
  double _raOffsetMin = 30;
  double _exposureSec = 5;

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _start(AppState s) async {
    if (s.api == null || _busy) return;

    // Pre-check
    final m = s.mountDevice();
    if (m == null) {
      showSnack(context, 'Mount non connesso'.tr(context), error: true); return;
    }
    final park = s.prop(m, 'TELESCOPE_PARK');
    if (propValue(park, 'PARK') == true) {
      showSnack(context, 'Mount in park: unpark prima di iniziare'.tr(context), error: true);
      return;
    }

    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      backgroundColor: T.panel(context),
      title: Text('Avvia Polar Align?'.tr(context)),
      content: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min,
        children: [
          Text('Routine 3-step drift-based:'.tr(context)),
          const SizedBox(height: 8),
          Text('1. Cattura attuale + plate solve → posizione 1'.tr(context),
              style: TextStyle(color: T.muted(context), fontSize: 12)),
          Text('${'2. Slew '.tr(context)}${_raOffsetMin.toInt()}\'${' RA → cattura + solve → posizione 2'.tr(context)}',
              style: TextStyle(color: T.muted(context), fontSize: 12)),
          Text('${'3. Slew altri '.tr(context)}${_raOffsetMin.toInt()}\'${' RA → cattura + solve → pos. 3'.tr(context)}',
              style: TextStyle(color: T.muted(context), fontSize: 12)),
          const SizedBox(height: 8),
          Text('Calcola errori AZ / ALT dal drift in Dec.'.tr(context),
              style: TextStyle(color: T.muted(context), fontSize: 12)),
          const SizedBox(height: 12),
          Text('Suggerito: punta vicino al meridiano + equatore celeste prima di iniziare'.tr(context),
              style: TextStyle(color: T.warn(context), fontSize: 12, fontStyle: FontStyle.italic)),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text('ANNULLA'.tr(context))),
        ElevatedButton(onPressed: () => Navigator.pop(c, true), child: Text('AVVIA'.tr(context))),
      ],
    ));
    if (ok != true) return;

    setState(() { _busy = true; _runStatus = null; _runId = null; });
    try {
      final r = await s.api!.polarAlignStart(
        raOffsetMin: _raOffsetMin, exposureSec: _exposureSec,
      );
      _runId = r['run_id'] as String?;
      _runStatus = r;
      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _poll());
    } on ApiException catch (e) {
      if (mounted) showSnack(context, '${'Errore: '.tr(context)}${e.body}', error: true);
    } catch (e) {
      if (mounted) showSnack(context, '${'Errore: '.tr(context)}$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _poll() async {
    if (_runId == null) return;
    final s = context.read<AppState>();
    try {
      _runStatus = await s.api!.polarAlignStatus(_runId!);
      setState(() {});
      final st = _runStatus!['status'];
      if (st == 'done' || st == 'failed' || st == 'aborted') {
        _pollTimer?.cancel();
      }
    } catch (_) {}
  }

  Future<void> _abort() async {
    if (_runId == null) return;
    final s = context.read<AppState>();
    try {
      await s.api!.polarAlignAbort(_runId!);
      if (mounted) showSnack(context, 'Abort'.tr(context));
    } catch (_) {}
  }

  bool get _running {
    final st = _runStatus?['status'];
    return st == 'running';
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return AdaptiveListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 80),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: T.accent2(context).withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: T.accent2(context).withValues(alpha: 0.4)),
          ),
          child: Row(children: [
            Icon(Icons.info_outline, color: T.accent2(context), size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(
              'Polar Alignment misura il disallineamento dell\'asse polare della mount via drift in Declinazione tra 3 plate solve in posizioni RA diverse. Richiede mount unparked + camera + driver Astrometry.'.tr(context),
              style: TextStyle(color: T.text(context), fontSize: 12, height: 1.4),
            )),
          ]),
        ),
        SectionLabel('Parametri routine'.tr(context)),
        _slider('RA offset tra step'.tr(context), _raOffsetMin, 5, 120,
            (v) => setState(() => _raOffsetMin = v),
            formatter: (v) => '${v.toInt()}\''),
        _slider('Esposizione cattura'.tr(context), _exposureSec, 1, 30,
            (v) => setState(() => _exposureSec = v),
            formatter: (v) => '${v.toStringAsFixed(0)}s'),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: PrimaryButton(
            label: _running ? 'IN CORSO…'.tr(context) : (_busy ? 'AVVIO…'.tr(context) : 'AVVIA POLAR ALIGN'.tr(context)),
            icon: Icons.explore,
            onPressed: _running || _busy ? null : () => _start(s),
          )),
          const SizedBox(width: 8),
          Expanded(child: GhostButton(
            label: 'ABORT'.tr(context), icon: Icons.stop, danger: true,
            onPressed: _running ? _abort : null,
          )),
        ]),
        if (_runStatus != null) ...[
          SectionLabel('Progresso'.tr(context)),
          _progressCard(),
        ],
      ],
    );
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
        Slider(value: v.clamp(min, max), min: min, max: max,
            onChanged: _running ? null : onChanged),
      ]),
    );
  }

  Widget _progressCard() {
    final r = _runStatus!;
    final st = r['status'];
    final step = r['step'] ?? 0;
    final samples = (r['samples'] as List? ?? []).cast<Map>();
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
          if (st == 'running')
            SizedBox(width: 14, height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: color))
          else
            Icon(st == 'done' ? Icons.check_circle : Icons.error, color: color, size: 16),
          const SizedBox(width: 6),
          Text('${'Polar Align'.tr(context)}: $st',
              style: TextStyle(color: color, fontWeight: FontWeight.w700)),
          const Spacer(),
          Text('${'step'.tr(context)} $step/3',
              style: TextStyle(color: T.muted(context), fontFamily: 'monospace')),
        ]),
        const SizedBox(height: 8),
        for (int i = 0; i < 3; i++) _stepRow(i, samples),
        if (r['az_error_arcmin'] != null) ...[
          const Divider(),
          Row(children: [
            Icon(Icons.straighten, size: 14, color: T.accent(context)),
            const SizedBox(width: 6),
            Text('Errore Polar (drift Dec):'.tr(context),
                style: TextStyle(color: T.muted(context), fontSize: 11)),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            const SizedBox(width: 20),
            Expanded(child: Text('AZ: ${(r['az_error_arcmin'] as num).toStringAsFixed(2)}\'',
                style: TextStyle(color: T.text(context),
                    fontFamily: 'monospace', fontSize: 14, fontWeight: FontWeight.w700))),
            Expanded(child: Text('ALT: ${(r['alt_error_arcmin'] as num).toStringAsFixed(2)}\'',
                style: TextStyle(color: T.text(context),
                    fontFamily: 'monospace', fontSize: 14, fontWeight: FontWeight.w700))),
          ]),
          const SizedBox(height: 6),
          Text(
            ((r['az_error_arcmin'] as num).abs() < 5)
                ? '✅ Allineamento polare ottimo'
                : ((r['az_error_arcmin'] as num).abs() < 15)
                    ? '⚠ Allineamento accettabile, regolazione fine consigliata'
                    : '❌ Allineamento polare scarso, regola le viti AZ/ALT della mount',
            style: TextStyle(color: T.muted(context), fontSize: 11.5,
                fontStyle: FontStyle.italic),
          ),
        ],
        if (r['error'] != null) Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('⚠ ${r['error']}', style: TextStyle(color: T.err(context), fontSize: 11)),
        ),
      ]),
    );
  }

  Widget _stepRow(int idx, List<Map> samples) {
    final done = idx < samples.length;
    final running = (_runStatus?['step'] ?? 0) == idx + 1 && !done;
    final s = done ? samples[idx] : null;
    Color color = done ? T.ok(context) : (running ? T.accent(context) : T.muted(context));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        if (running)
          SizedBox(width: 12, height: 12,
              child: CircularProgressIndicator(strokeWidth: 2, color: color))
        else
          Icon(done ? Icons.check_circle : Icons.radio_button_unchecked,
              color: color, size: 13),
        const SizedBox(width: 8),
        Text('Step ${idx + 1}',
            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
        const SizedBox(width: 10),
        if (done && s != null)
          Expanded(child: Text(
            'RA ${(s['ra_hours'] as num).toStringAsFixed(3)}h · Dec ${(s['dec_deg'] as num).toStringAsFixed(3)}°',
            style: TextStyle(color: T.muted(context), fontFamily: 'monospace', fontSize: 11),
          )),
      ]),
    );
  }
}
