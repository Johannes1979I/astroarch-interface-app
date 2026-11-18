import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/api_client.dart';
import '../i18n/strings.dart';
import '../state/app_state.dart';
import '../state/capture_job.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/responsive.dart';

/// Schermata di pianificazione e progresso "Osservazione completa":
/// orchestratore Ekos-style con tutte le pre-flight checks.
class ObservationScreen extends StatefulWidget {
  final List<CaptureJob> jobs;
  const ObservationScreen({super.key, required this.jobs});
  @override
  State<ObservationScreen> createState() => _ObservationScreenState();
}

class _ObservationScreenState extends State<ObservationScreen> {
  final _targetCtl = TextEditingController();
  bool _doPlateSolve = true;
  bool _doAutofocus = false;
  bool _doGuideCal = false;
  bool _doGuideStart = true;
  bool _useEkos = true;

  String? _runId;
  Map<String, dynamic>? _runStatus;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    // Pre-popola target dal primo job
    for (final j in widget.jobs) {
      if (j.targetName != null && j.targetName!.isNotEmpty) {
        _targetCtl.text = j.targetName!;
        break;
      }
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _targetCtl.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final s = context.read<AppState>();
    if (s.api == null) return;
    if (_targetCtl.text.trim().isEmpty) {
      showSnack(context, 'Target richiesto'.tr(context), error: true);
      return;
    }
    try {
      final r = await s.api!.observationRun(
        targetName: _targetCtl.text.trim(),
        jobs: widget.jobs.map((j) => j.toJson()).toList(),
        doPlateSolve: _doPlateSolve,
        doAutofocus: _doAutofocus,
        doGuideCalibrate: _doGuideCal,
        doGuideStart: _doGuideStart,
        useEkosCapture: _useEkos,
      );
      setState(() {
        _runId = r['run_id'] as String?;
      });
      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
    } on ApiException catch (e) {
      if (mounted) showSnack(context, '${'Errore: '.tr(context)}${e.body}', error: true);
    } catch (e) {
      if (mounted) showSnack(context, '${'Errore: '.tr(context)}$e', error: true);
    }
  }

  Future<void> _poll() async {
    if (_runId == null) return;
    final s = context.read<AppState>();
    try {
      _runStatus = await s.api!.observationStatus(_runId!);
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
      await s.api!.observationAbort(_runId!);
      if (mounted) showSnack(context, 'Abort richiesto'.tr(context));
    } catch (e) {
      if (mounted) showSnack(context, '${'Errore: '.tr(context)}$e', error: true);
    }
  }

  bool get _running {
    final st = _runStatus?['status'];
    return st == 'running' || st == 'aborting';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Osservazione completa'.tr(context))),
      body: AdaptiveListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 80), children: [
        SectionLabel('Target'.tr(context)),
        Row(children: [
          Expanded(child: TextField(
            controller: _targetCtl,
            enabled: !_running,
            decoration: const InputDecoration(
              hintText: 'M 31, NGC 7000, …',
              prefixIcon: Icon(Icons.gps_fixed, size: 18),
              isDense: true,
            ),
          )),
        ]),
        SectionLabel('Pre-flight checks'.tr(context)),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('Plate solve & sync mount'.tr(context)),
          subtitle: Text('Cattura un frame, risolve, sincronizza la mount'.tr(context),
              style: TextStyle(color: T.muted(context), fontSize: 11)),
          value: _doPlateSolve,
          onChanged: _running ? null : (v) => setState(() => _doPlateSolve = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('Autofocus'.tr(context)),
          subtitle: Text('Esegui autofocus iterativo prima della cattura'.tr(context),
              style: TextStyle(color: T.muted(context), fontSize: 11)),
          value: _doAutofocus,
          onChanged: _running ? null : (v) => setState(() => _doAutofocus = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('Calibrate PHD2'.tr(context)),
          subtitle: Text('Forza nuova calibrazione (~2 min)'.tr(context),
              style: TextStyle(color: T.muted(context), fontSize: 11)),
          value: _doGuideCal,
          onChanged: _running ? null : (v) => setState(() => _doGuideCal = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('Avvia guiding PHD2'.tr(context)),
          subtitle: Text('Aspetta settle prima di catturare'.tr(context),
              style: TextStyle(color: T.muted(context), fontSize: 11)),
          value: _doGuideStart,
          onChanged: _running ? null : (v) => setState(() => _doGuideStart = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('Usa Ekos Capture (raccomandato)'.tr(context)),
          subtitle: Text('I job appaiono nella UI Ekos. Off = comando diretto INDI.'.tr(context),
              style: TextStyle(color: T.muted(context), fontSize: 11)),
          value: _useEkos,
          onChanged: _running ? null : (v) => setState(() => _useEkos = v),
        ),
        const SizedBox(height: 8),
        Text('${'Sequenza: '.tr(context)}${widget.jobs.length} job',
            style: TextStyle(color: T.muted(context), fontSize: 11)),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: PrimaryButton(
            label: _running ? 'IN CORSO…'.tr(context) : 'AVVIA OSSERVAZIONE'.tr(context),
            icon: Icons.play_arrow,
            onPressed: _running ? null : _start,
          )),
          const SizedBox(width: 8),
          Expanded(child: GhostButton(
            label: 'ABORT'.tr(context), icon: Icons.stop, danger: true,
            onPressed: _running ? _abort : null,
          )),
        ]),
        if (_runStatus != null) ...[
          SectionLabel('Pipeline'.tr(context)),
          _phasesTimeline(),
        ],
      ]),
    );
  }

  Widget _phasesTimeline() {
    final phases = (_runStatus?['phases'] as List? ?? []).cast<Map>();
    return Column(children: [
      for (final p in phases) _phaseTile(p),
    ]);
  }

  Widget _phaseTile(Map p) {
    final status = p['status'] ?? 'pending';
    Color color; IconData icon;
    switch (status) {
      case 'done': color = T.ok(context); icon = Icons.check_circle; break;
      case 'failed': color = T.err(context); icon = Icons.error; break;
      case 'running': color = T.accent(context); icon = Icons.sync; break;
      case 'skipped': color = T.muted(context); icon = Icons.fast_forward; break;
      default: color = T.muted(context); icon = Icons.radio_button_unchecked;
    }
    final prettyName = (p['name'] as String).replaceAll('_', ' ').toUpperCase();
    final dt = p['ended_at'] != null && p['started_at'] != null
        ? Duration(milliseconds:
            (((p['ended_at'] as num) - (p['started_at'] as num)) * 1000).toInt())
        : null;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
      decoration: BoxDecoration(
        color: T.panel(context), borderRadius: BorderRadius.circular(9),
        border: Border.all(color: status == 'running' ? color.withValues(alpha: 0.5) : T.line(context)),
      ),
      child: Row(children: [
        if (status == 'running')
          SizedBox(width: 14, height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: color))
        else
          Icon(icon, color: color, size: 16),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(prettyName,
              style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
          if ((p['msg'] as String?)?.isNotEmpty == true)
            Text(p['msg'],
                style: TextStyle(color: T.muted(context), fontSize: 10.5, fontFamily: 'monospace'),
                maxLines: 2, overflow: TextOverflow.ellipsis),
        ])),
        if (dt != null) Text('${dt.inSeconds}s',
            style: TextStyle(color: T.muted(context), fontSize: 10, fontFamily: 'monospace')),
      ]),
    );
  }
}
