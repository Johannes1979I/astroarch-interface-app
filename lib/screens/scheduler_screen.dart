import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/api_client.dart';
import '../i18n/strings.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/responsive.dart';

/// Scheduler temporale multi-target. Lista jobs salvati lato bridge,
/// con valutazione condizioni (twilight, altitudine, weather).
class SchedulerScreen extends StatefulWidget {
  const SchedulerScreen({super.key});
  @override
  State<SchedulerScreen> createState() => _SchedulerScreenState();
}

class _SchedulerScreenState extends State<SchedulerScreen> {
  Map<String, dynamic>? _sky;
  List<Map<String, dynamic>> _jobs = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _refresh(); }

  Future<void> _refresh() async {
    final s = context.read<AppState>();
    if (s.api == null) return;
    setState(() => _loading = true);
    try {
      _sky = await s.api!.schedulerSkyState();
      final j = await s.api!.schedulerJobs();
      _jobs = ((j['jobs'] as List?) ?? []).cast<Map<String, dynamic>>();
    } catch (e) {
      if (mounted) showSnack(context, '${'Errore: '.tr(context)}$e', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Scheduler'.tr(context)),
        actions: [IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh))],
      ),
      body: _loading && _sky == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: AdaptiveListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 80), children: [
                _skyCard(),
                SectionLabel('Jobs pianificati'.tr(context)),
                if (_jobs.isEmpty)
                  Padding(padding: const EdgeInsets.all(20),
                      child: Text('Nessun job. Tap + in basso'.tr(context),
                          style: TextStyle(color: T.muted(context)))),
                for (final j in _jobs) _jobTile(j),
                const SizedBox(height: 14),
                PrimaryButton(label: '+ NUOVO JOB'.tr(context), icon: Icons.add,
                    onPressed: _addJob),
              ]),
            ),
    );
  }

  Widget _skyCard() {
    final sky = _sky ?? {};
    final phase = sky['twilight_phase']?.toString() ?? '—';
    final sunAlt = (sky['sun_alt'] as num?)?.toDouble();
    final moonAlt = (sky['moon_alt'] as num?)?.toDouble();
    final ws = sky['weather_safe'] == true;
    Color phaseColor;
    switch (phase) {
      case 'night': phaseColor = T.ok(context); break;
      case 'astronomical_twilight': phaseColor = T.accent(context); break;
      case 'nautical_twilight':
      case 'civil_twilight':
        phaseColor = T.warn(context); break;
      default: phaseColor = T.err(context);
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: T.panel(context), borderRadius: BorderRadius.circular(11),
        border: Border.all(color: phaseColor.withValues(alpha: 0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.nightlight_round, color: phaseColor, size: 18),
          const SizedBox(width: 8),
          Text(phase.replaceAll('_', ' ').toUpperCase(),
              style: TextStyle(color: phaseColor, fontWeight: FontWeight.w700, letterSpacing: 1)),
          const Spacer(),
          if (ws) Icon(Icons.cloud, color: T.ok(context), size: 14)
          else Icon(Icons.cloud_off, color: T.warn(context), size: 14),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 14, runSpacing: 4, children: [
          _kv('Sun'.tr(context), sunAlt == null ? '—' : '${sunAlt.toStringAsFixed(1)}°'),
          _kv('Moon'.tr(context), moonAlt == null ? '—' : '${moonAlt.toStringAsFixed(1)}°'),
          _kv('Weather'.tr(context), ws ? 'safe'.tr(context) : 'unsafe'.tr(context)),
        ]),
      ]),
    );
  }

  Widget _kv(String k, String v) => Row(mainAxisSize: MainAxisSize.min, children: [
    Text('$k ', style: TextStyle(color: T.muted(context), fontSize: 10)),
    Text(v, style: const TextStyle(fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.w600)),
  ]);

  Widget _jobTile(Map<String, dynamic> j) {
    final s = context.read<AppState>();
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: T.panel(context), borderRadius: BorderRadius.circular(10),
        border: Border.all(color: T.line(context)),
      ),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(j['name']?.toString() ?? j['target_name']?.toString() ?? 'job',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          if (j['ra_hours'] != null && j['dec_deg'] != null)
            Text('RA ${(j['ra_hours'] as num).toStringAsFixed(2)}h · '
                 'Dec ${(j['dec_deg'] as num).toStringAsFixed(1)}°',
                style: TextStyle(color: T.muted(context), fontSize: 10, fontFamily: 'monospace')),
          if (j['start_time'] != null)
            Text('${'start: '.tr(context)}${j['start_time']}',
                style: TextStyle(color: T.muted(context), fontSize: 10)),
          Text('${'alt min: '.tr(context)}${j['min_altitude'] ?? 30}°',
              style: TextStyle(color: T.muted(context), fontSize: 10)),
        ])),
        IconButton(
          icon: Icon(Icons.fact_check_outlined, color: T.accent2(context), size: 18),
          tooltip: 'Verifica condizioni'.tr(context),
          onPressed: () async {
            try {
              final r = await s.api!.schedulerCheckConditions(j['id']);
              if (mounted) {
                showDialog(context: context, builder: (c) => AlertDialog(
                  backgroundColor: T.panel(context),
                  title: Text(r['can_run'] == true ? 'Pronto ad avviare'.tr(context) : 'Non avviabile ora'.tr(context)),
                  content: r['can_run'] == true
                      ? Text('Tutte le condizioni soddisfatte.'.tr(context))
                      : Text((r['issues'] as List).join('\n')),
                  actions: [TextButton(onPressed: () => Navigator.pop(c), child: Text('OK'.tr(context)))],
                ));
              }
            } catch (e) {
              if (mounted) showSnack(context, '${'Errore: '.tr(context)}$e', error: true);
            }
          },
        ),
        IconButton(
          icon: Icon(Icons.delete_outline, color: T.err(context), size: 18),
          onPressed: () async {
            try {
              await s.api!.schedulerDeleteJob(j['id']);
              _refresh();
            } catch (e) {
              if (mounted) showSnack(context, '${'Errore: '.tr(context)}$e', error: true);
            }
          },
        ),
      ]),
    );
  }

  Future<void> _addJob() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context, MaterialPageRoute(builder: (_) => const _AddJobScreen()));
    if (result == null) return;
    final s = context.read<AppState>();
    try {
      await s.api!.schedulerAddJob(result);
      _refresh();
    } catch (e) {
      if (mounted) showSnack(context, '${'Errore: '.tr(context)}$e', error: true);
    }
  }
}

class _AddJobScreen extends StatefulWidget {
  const _AddJobScreen();
  @override
  State<_AddJobScreen> createState() => _AddJobScreenState();
}

class _AddJobScreenState extends State<_AddJobScreen> {
  final _name = TextEditingController();
  final _target = TextEditingController();
  final _raCtl = TextEditingController();
  final _decCtl = TextEditingController();
  final _altCtl = TextEditingController(text: '30');
  bool _resolving = false;
  String? _resolveErr;

  Future<void> _resolveTarget() async {
    final s = context.read<AppState>();
    final name = _target.text.trim();
    if (name.isEmpty) return;
    setState(() {
      _resolving = true; _resolveErr = null;
    });
    try {
      final r = await s.api!.simbadSearch(name);
      _raCtl.text = (r['ra_hours'] as num).toStringAsFixed(4);
      _decCtl.text = (r['dec_deg'] as num).toStringAsFixed(4);
    } on ApiException catch (e) {
      _resolveErr = e.status == 404 ? 'non trovato'.tr(context) : e.body;
    } catch (e) {
      _resolveErr = '$e';
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  void _save() {
    final ra = double.tryParse(_raCtl.text);
    final dec = double.tryParse(_decCtl.text);
    final alt = int.tryParse(_altCtl.text) ?? 30;
    if (_name.text.trim().isEmpty) {
      showSnack(context, 'Manca il nome'.tr(context), error: true); return;
    }
    Navigator.pop(context, {
      'name': _name.text.trim(),
      if (_target.text.trim().isNotEmpty) 'target_name': _target.text.trim(),
      if (ra != null) 'ra_hours': ra,
      if (dec != null) 'dec_deg': dec,
      'min_altitude': alt,
      'require_night': true,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Nuovo job scheduler'.tr(context)),
        actions: [
          TextButton.icon(
            onPressed: _save,
            icon: Icon(Icons.check, color: T.accent(context)),
            label: Text('SALVA'.tr(context),
                style: TextStyle(color: T.accent(context), fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: AdaptiveListView(kind: ContentKind.form, padding: const EdgeInsets.all(14), children: [
        TextField(controller: _name,
            decoration: InputDecoration(labelText: 'Nome job'.tr(context), isDense: true)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: TextField(
            controller: _target,
            decoration: InputDecoration(labelText: 'Target (SIMBAD)'.tr(context),
                hintText: 'M 31', isDense: true),
          )),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: _resolving ? null : _resolveTarget,
            child: _resolving
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                : Text('RISOLVI'.tr(context)),
          ),
        ]),
        if (_resolveErr != null) Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(_resolveErr!, style: TextStyle(color: T.err(context), fontSize: 11)),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: TextField(controller: _raCtl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'RA (h)'.tr(context), isDense: true))),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: _decCtl,
              keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
              decoration: InputDecoration(labelText: 'Dec (°)'.tr(context), isDense: true))),
        ]),
        const SizedBox(height: 12),
        TextField(controller: _altCtl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: 'Altitudine minima (°)'.tr(context), isDense: true)),
      ]),
    );
  }
}
