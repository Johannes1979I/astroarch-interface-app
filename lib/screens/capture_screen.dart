import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/api_client.dart';
import '../i18n/strings.dart';
import '../state/app_state.dart';
import '../state/capture_job.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'capture/cooler_panel.dart';
import 'capture/job_form.dart';
import 'capture/sequence_runner.dart';
import 'observation_screen.dart';
import 'shell_screen.dart';

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});
  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  // BUG FIX v0.2.34: inizializzato a stringa vuota qui — viene popolato in
  // initState con AppState.userTargetTemperatureC, persistito su disco.
  // Prima era TextEditingController(text: '-10') hardcoded → il valore
  // tornava sempre a -10°C ad ogni rebuild del widget (cambio schermata).
  final TextEditingController _tempCtl = TextEditingController();
  late final SequenceRunner _runner;
  bool _runnerInited = false;

  // Tracking sequenza VIA EKOS: poll periodico dello stato Capture su DBus
  // così possiamo mostrare l'ABORT in modo persistente anche quando l'app
  // si è chiusa/riaperta a sequenza in corso.
  Timer? _ekosPoll;
  Map<String, dynamic>? _ekosCapStatus;
  bool _ekosBusy = false;        // true mentre sta partendo o c'è un job attivo
  bool _ekosAborting = false;    // tap su ABORT ha già spedito il comando

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      final s = context.read<AppState>();
      s.loadCaptureJobs();
      _runner = SequenceRunner(s);
      _runner.addListener(_onRunnerChange);
      // Carica la T setpoint persistita (fix v0.2.34: prima si resettava
      // sempre a -10 ad ogni cambio schermata).
      _tempCtl.text = s.userTargetTemperatureC.toStringAsFixed(1);
      // Persist on every edit so navigation away preserves the value.
      _tempCtl.addListener(() {
        final v = double.tryParse(_tempCtl.text.replaceAll(',', '.'));
        if (v != null && v != s.userTargetTemperatureC) {
          s.setUserTargetTemperatureC(v);
        }
      });
      setState(() => _runnerInited = true);
    });
    // Start polling Ekos capture status: anche se l'utente non ha appena
    // premuto Avvia, una sequenza potrebbe essere già in corso (lanciata
    // prima, o da KStars sul desktop). Vogliamo mostrare l'ABORT comunque.
    _ekosPoll = Timer.periodic(const Duration(seconds: 3), (_) => _refreshEkosStatus());
    _refreshEkosStatus();
  }

  @override
  void dispose() {
    _ekosPoll?.cancel();
    if (_runnerInited) _runner.removeListener(_onRunnerChange);
    _tempCtl.dispose();
    super.dispose();
  }

  void _onRunnerChange() => setState(() {});

  Future<void> _refreshEkosStatus() async {
    final s = context.read<AppState>();
    if (s.api == null) return;
    try {
      final st = await s.api!.captureEkosStatus();
      if (!mounted) return;
      final active = (st['active_job_id'] as num?)?.toInt() ?? -1;
      final jobs = (st['job_count'] as num?)?.toInt() ?? 0;
      // C'è qualcosa in corso se c'è un active_job_id valido (>=0) E lo
      // stato del job non è "Idle"/"Complete". Lo stato preciso dipende
      // da come Ekos lo riporta, lo trattiamo conservativamente: se
      // active_job_id è valido e ci sono job in queue → sequenza viva.
      setState(() {
        _ekosCapStatus = st;
        _ekosBusy = active >= 0 && jobs > 0;
        if (!_ekosBusy) _ekosAborting = false;
      });
    } catch (_) {}
  }

  Future<void> _abortEkosSequence() async {
    final s = context.read<AppState>();
    if (s.api == null) return;
    // Conferma esplicita: fermare la sequenza Ekos perde l'esposizione in
    // corso (frame parziale viene scartato dal driver).
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: Text('Interrompere la sequenza?'.tr(context)),
      content: Text('La sequenza Ekos verrà fermata immediatamente. '
          'L\'esposizione in corso verrà scartata.'.tr(context)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false),
            child: Text('ANNULLA'.tr(context))),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: T.err(context)),
          onPressed: () => Navigator.pop(c, true),
          child: Text('FERMA SEQUENZA'.tr(context)),
        ),
      ],
    ));
    if (ok != true) return;
    setState(() => _ekosAborting = true);
    try {
      await s.api!.captureEkosAbort();
      if (mounted) showSnack(context, 'Sequenza fermata'.tr(context));
      // Polla subito per riflettere il nuovo stato
      await _refreshEkosStatus();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, '${'Errore: '.tr(context)}${e.body}', error: true);
    } catch (e) {
      if (mounted) showSnack(context, '${'Errore: '.tr(context)}$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final cams = s.cameraDevices;
    final cam = s.effectiveDevice('camera');
    final filterDev = s.effectiveDevice('filter_wheel');
    final filterNames = _filterNames(s, filterDev);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
            icon: const Icon(Icons.menu),
            onPressed: openShellDrawer),
        title: Text(cam == null ? 'Capture'.tr(context) : '${'Capture'.tr(context)} · $cam', overflow: TextOverflow.ellipsis),
        actions: [
          // v0.2.48 (P6): carica una sequenza .esq dal Pi (richiesto da Tucniak)
          IconButton(
            tooltip: 'Carica sequenza dal Pi'.tr(context),
            icon: const Icon(Icons.folder_open),
            onPressed: _loadSequenceFromPi,
          ),
          IconButton(
            tooltip: 'Preset'.tr(context),
            icon: const Icon(Icons.bookmark_border),
            onPressed: _showPresets,
          ),
        ],
      ),
      body: cams.isEmpty
          ? Center(child: Text('Nessuna camera connessa'.tr(context), style: TextStyle(color: T.muted(context))))
          : ListView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 80),
              children: [
                if (cams.length > 1) _devicePicker(s, cams),
                if (cam != null) ...[
                  CoolerPanel(camera: cam, tempCtl: _tempCtl),
                  SectionLabel('Sequenza jobs'.tr(context), /* trailing handled below */),
                  _jobsList(s),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: GhostButton(
                      label: 'NUOVO JOB'.tr(context), icon: Icons.add,
                      onPressed: _runnerInited && _runner.running ? null
                          : () => _editJob(s, null, filterNames),
                    )),
                    const SizedBox(width: 8),
                    Expanded(child: GhostButton(
                      label: 'CANCELLA TUTTI'.tr(context), icon: Icons.delete_outline, danger: true,
                      onPressed: s.captureJobs.isEmpty || (_runnerInited && _runner.running)
                          ? null : () async {
                              final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
                                backgroundColor: T.panel(context),
                                title: Text('Cancella tutti i job?'.tr(context)),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(c, false), child: Text('NO'.tr(context))),
                                  ElevatedButton(onPressed: () => Navigator.pop(c, true), child: Text('CANCELLA'.tr(context))),
                                ],
                              ));
                              if (ok == true) {
                                s.captureJobs.clear();
                                s.saveCaptureJobs();
                                s.notifyListeners();
                              }
                            },
                    )),
                  ]),
                  if (_runnerInited && (_runner.running || _runner.statusMsg != null))
                    _runStatus(),
                  const SizedBox(height: 14),
                  _runControls(s, cam, filterDev),
                ],
              ],
            ),
    );
  }

  Widget _devicePicker(AppState s, List<String> cams) {
    final sel = s.selectedCamera ?? s.primaryCameraAuto ?? (cams.length == 1 ? cams.first : null);
    String roleTag(String c) {
      if (c == s.primaryCameraAuto) return ' · primary';
      if (c == s.guideCameraAuto) return ' · guide';
      return '';
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: T.panel(context), borderRadius: BorderRadius.circular(10),
          border: Border.all(color: T.line(context)),
        ),
        child: Row(children: [
          Icon(Icons.camera_alt, size: 16, color: T.muted(context)),
          const SizedBox(width: 8),
          Text('Camera:'.tr(context), style: TextStyle(color: T.muted(context), fontSize: 11, letterSpacing: 1)),
          const SizedBox(width: 8),
          Expanded(child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: sel, isExpanded: true,
              hint: Text('— scegli —'.tr(context), style: TextStyle(color: T.warn(context), fontSize: 13)),
              dropdownColor: T.panel(context),
              style: TextStyle(color: T.text(context), fontSize: 13, fontWeight: FontWeight.w600),
              items: [
                for (final c in cams)
                  DropdownMenuItem(value: c, child: Text(c + roleTag(c), overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => s.setSelectedDevice('camera', v),
            ),
          )),
        ]),
      ),
    );
  }

  Widget _jobsList(AppState s) {
    if (s.captureJobs.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: T.panel(context), borderRadius: BorderRadius.circular(10),
          border: Border.all(color: T.line(context)),
        ),
        child: Center(
          child: Text('Nessun job · Tap "+ NUOVO JOB" per pianificare'.tr(context),
              style: TextStyle(color: T.muted(context), fontSize: 12)),
        ),
      );
    }
    return ReorderableListView(
      shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: true,
      onReorder: (o, n) => s.reorderCaptureJobs(o, n),
      children: [
        for (int i = 0; i < s.captureJobs.length; i++)
          _jobTile(s, i, s.captureJobs[i]),
      ],
    );
  }

  Widget _jobTile(AppState s, int idx, CaptureJob job) {
    final filterNames = _filterNames(s, s.effectiveDevice('filter_wheel'));
    Color stateColor;
    IconData stateIcon;
    switch (job.status) {
      case CaptureJobStatus.running:
        stateColor = T.accent(context); stateIcon = Icons.play_circle_fill; break;
      case CaptureJobStatus.done:
        stateColor = T.ok(context); stateIcon = Icons.check_circle; break;
      case CaptureJobStatus.failed:
        stateColor = T.err(context); stateIcon = Icons.error; break;
      case CaptureJobStatus.aborted:
        stateColor = T.warn(context); stateIcon = Icons.cancel; break;
      case CaptureJobStatus.paused:
        stateColor = T.warn(context); stateIcon = Icons.pause_circle; break;
      default:
        stateColor = T.muted(context); stateIcon = Icons.radio_button_unchecked;
    }
    return Container(
      key: ValueKey(job.id),
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
      decoration: BoxDecoration(
        color: T.panel(context), borderRadius: BorderRadius.circular(10),
        border: Border.all(color: job.status == CaptureJobStatus.running
            ? T.accent(context).withValues(alpha: 0.5) : T.line(context)),
      ),
      child: Row(children: [
        Icon(stateIcon, color: stateColor, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(job.summary,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          Row(children: [
            Text('gain ${job.gain.toInt()} · off ${job.offset.toInt()} · bin ${job.binX}×${job.binY} · ${job.transferFormat}',
                style: TextStyle(color: T.muted(context), fontSize: 10)),
            if (job.ditherEachFrame) ...[
              const SizedBox(width: 6),
              Icon(Icons.scatter_plot, size: 10, color: T.accent2(context)),
            ],
          ]),
          if (job.status == CaptureJobStatus.running ||
              job.status == CaptureJobStatus.done ||
              job.doneCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: job.count == 0 ? 0 : job.doneCount / job.count,
                  minHeight: 3,
                  backgroundColor: T.line(context),
                  color: stateColor,
                ),
              ),
            ),
          if (job.lastError != null)
            Text('⚠ ${job.lastError}',
                style: TextStyle(color: T.err(context), fontSize: 10)),
        ])),
        Text('${job.doneCount}/${job.count}',
            style: TextStyle(color: T.muted(context), fontFamily: 'monospace', fontSize: 11)),
        PopupMenuButton<String>(
          icon: Icon(Icons.more_vert, color: T.muted(context), size: 18),
          color: T.panel(context),
          onSelected: (v) {
            if (v == 'edit') _editJob(s, idx, filterNames);
            if (v == 'dup') s.duplicateCaptureJob(idx);
            if (v == 'del') s.removeCaptureJob(idx);
          },
          itemBuilder: (c) => [
            PopupMenuItem(value: 'edit', child: Text('Modifica'.tr(context))),
            PopupMenuItem(value: 'dup', child: Text('Duplica'.tr(context))),
            PopupMenuItem(value: 'del', child: Text('Rimuovi'.tr(context))),
          ],
        ),
      ]),
    );
  }

  Future<void> _editJob(AppState s, int? idx, List<String> filters) async {
    final initial = idx == null ? null : s.captureJobs[idx];
    final result = await Navigator.push<CaptureJob>(context, MaterialPageRoute(
      builder: (_) => JobFormScreen(initial: initial, filters: filters),
    ));
    if (result == null) return;
    if (idx == null) { s.addCaptureJob(result); }
    else { s.updateCaptureJob(idx, result); }
  }

  List<String> _filterNames(AppState s, String? filterDev) {
    if (filterDev == null) return [];
    final p = s.prop(filterDev, 'FILTER_NAME');
    if (p == null) return [];
    return (p['elements'] as List? ?? [])
        .map((e) => (e['value'] ?? e['name']).toString())
        .where((x) => x.isNotEmpty).toList();
  }

  Widget _runStatus() {
    final r = _runner;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: T.panel(context), borderRadius: BorderRadius.circular(10),
        border: Border.all(color: T.accent(context).withValues(alpha: 0.4)),
      ),
      child: Row(children: [
        if (r.running)
          SizedBox(width: 14, height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: T.accent(context)))
        else
          Icon(Icons.check_circle, color: T.ok(context), size: 16),
        const SizedBox(width: 8),
        Expanded(child: Text(r.statusMsg ?? '',
            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'))),
      ]),
    );
  }

  Widget _runControls(AppState s, String camera, String? filterDev) {
    if (!_runnerInited) return const SizedBox();
    final hasJobs = s.captureJobs.isNotEmpty;

    // Tre modi di esecuzione, tre stati di "running":
    //   • _runner.running  → modalità DIRETTO (locale)
    //   • _ekosBusy        → sequenza VIA EKOS in corso (anche se lanciata
    //                        da KStars desktop o da una sessione app precedente)
    //
    // L'ABORT deve essere SEMPRE accessibile finché una sequenza è viva.
    final localRunning = _runner.running;
    final ekosRunning = _ekosBusy;
    final anyRunning = localRunning || ekosRunning;

    return Column(children: [
      // Banner stato Ekos: lo mostriamo se sta girando una sequenza via Ekos
      // (con remaining time live). Distinto da quello del _runner locale.
      if (ekosRunning) _ekosRunningBanner(),
      if (ekosRunning) const SizedBox(height: 8),

      Row(children: [
        if (!anyRunning)
          Expanded(child: PrimaryButton(
            label: 'AVVIA SEQUENZA'.tr(context), icon: Icons.play_arrow,
            onPressed: hasJobs ? () => _confirmAndRun(s, camera, filterDev) : null,
          ))
        else if (localRunning && _runner.paused)
          Expanded(child: PrimaryButton(
            label: 'RIPRENDI'.tr(context), icon: Icons.play_arrow,
            onPressed: () => _runner.resume(),
          ))
        else if (localRunning)
          Expanded(child: GhostButton(
            label: 'PAUSA'.tr(context), icon: Icons.pause,
            onPressed: () => _runner.pause(),
          ))
        else
          // Ekos in corso: niente pausa (Ekos non espone pause/resume sequence
          // via DBus in modo affidabile); solo lo stato "in corso".
          Expanded(child: GhostButton(
            label: 'SEQUENZA EKOS IN CORSO'.tr(context),
            icon: Icons.sync, onPressed: null,
          )),
        const SizedBox(width: 8),
        Expanded(child: GhostButton(
          label: _ekosAborting ? 'ABORTING…'.tr(context) : 'FERMA SEQUENZA'.tr(context),
          icon: Icons.stop, danger: true,
          onPressed: !anyRunning || _ekosAborting ? null
              : localRunning
                  ? () => _runner.abort()
                  : () => _abortEkosSequence(),
        )),
      ]),
    ]);
  }

  /// Banner che mostra lo stato della sequenza VIA EKOS in corso:
  /// progresso job attuale e tempo rimanente complessivo.
  Widget _ekosRunningBanner() {
    final st = _ekosCapStatus ?? {};
    final activeId = (st['active_job_id'] as num?)?.toInt() ?? -1;
    final jobs = (st['job_count'] as num?)?.toInt() ?? 0;
    final imgProg = (st['job_image_progress'] as num?)?.toInt();
    final imgCount = (st['job_image_count'] as num?)?.toInt();
    final remOverall = (st['overall_remaining_seconds'] as num?)?.toInt();
    final jobState = st['job_state']?.toString() ?? '—';

    String fmtTime(int? sec) {
      if (sec == null || sec < 0) return '—';
      final h = sec ~/ 3600, m = (sec % 3600) ~/ 60, s = sec % 60;
      return h > 0
          ? '${h}h ${m.toString().padLeft(2,'0')}m ${s.toString().padLeft(2,'0')}s'
          : '${m}m ${s.toString().padLeft(2,'0')}s';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: T.accent(context).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: T.accent(context).withValues(alpha: 0.5)),
      ),
      child: Row(children: [
        SizedBox(width: 18, height: 18,
            child: CircularProgressIndicator(strokeWidth: 2,
                color: T.accent(context))),
        const SizedBox(width: 10),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('SEQUENZA EKOS IN CORSO'.tr(context),
              style: TextStyle(color: T.accent(context), fontSize: 11,
                  letterSpacing: 1.2, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(
            '${'Job'.tr(context)} ${activeId + 1}/$jobs · '
            '${imgProg ?? "?"}/${imgCount ?? "?"} ${'frame'.tr(context)} · '
            '$jobState',
            style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
          ),
          Text('${'Rimanenti'.tr(context)}: ${fmtTime(remOverall)}',
              style: TextStyle(fontSize: 11, fontFamily: 'monospace',
                  color: T.muted(context))),
        ])),
      ]),
    );
  }

  Future<void> _confirmAndRun(AppState s, String camera, String? filterDev) async {
    final n = s.captureJobs.length;
    final totalSec = s.captureJobs.fold<double>(
      0, (acc, j) => acc + (j.count * j.exposureSec) + ((j.count - 1).clamp(0, j.count) * j.delaySec));
    final mins = (totalSec / 60).ceil();

    final choice = await showDialog<String>(context: context, builder: (c) => AlertDialog(
      backgroundColor: T.panel(context),
      title: Text('Avvia sequenza'.tr(context)),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min,
        children: [
          Text('$n ${'job · durata stimata ~'.tr(context)}$mins ${'min'.tr(context)}',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Text('Cosa vuoi che faccia?'.tr(context),
              style: TextStyle(color: T.muted(context), fontSize: 12)),
          const SizedBox(height: 14),
          // Opzione 0: Osservazione completa (pre-flight)
          InkWell(
            onTap: () => Navigator.pop(c, 'observation'),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: T.ok(context).withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: T.ok(context).withValues(alpha: 0.7), width: 1.5),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.auto_awesome, color: T.ok(context), size: 16),
                  const SizedBox(width: 6),
                  Expanded(child: Text('FAI TUTTO TU'.tr(context),
                      style: TextStyle(color: T.ok(context), fontWeight: FontWeight.w700))),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: T.ok(context),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text('CONSIGLIATO', style: TextStyle(
                        color: Colors.black, fontSize: 9, fontWeight: FontWeight.w800)),
                  ),
                ]),
                const SizedBox(height: 4),
                Text('Punta l\'oggetto, verifica la posizione col plate solving, avvia la guida e poi scatta.'.tr(context),
                    style: TextStyle(color: T.muted(context), fontSize: 11)),
                const SizedBox(height: 3),
                Text('→ Usala se parti da zero su un nuovo oggetto.'.tr(context),
                    style: TextStyle(color: T.ok(context), fontSize: 11, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          // Opzione 1: via Ekos
          InkWell(
            onTap: () => Navigator.pop(c, 'ekos'),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: T.accent(context).withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: T.accent(context).withValues(alpha: 0.6)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.star, color: T.accent(context), size: 16),
                  const SizedBox(width: 6),
                  Expanded(child: Text('SCATTA I JOB DI QUESTA APP'.tr(context),
                      style: TextStyle(color: T.accent(context), fontWeight: FontWeight.w700))),
                ]),
                const SizedBox(height: 4),
                Text('Manda a Ekos i job che hai creato qui sopra. Ekos si occupa di dither, autofocus, nomi file e flip al meridiano.'.tr(context),
                    style: TextStyle(color: T.muted(context), fontSize: 11)),
                const SizedBox(height: 3),
                Text('→ Usala se il telescopio è già puntato e in guida.'.tr(context),
                    style: TextStyle(color: T.accent(context), fontSize: 11, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          // Opzione 3: avvia la sequenza GIÀ pianificata in Ekos
          // (nessun clear/load: usa la Capture queue configurata a mano nella
          // UI di Ekos sul desktop). Ideale quando hai già preparato tutto lì.
          InkWell(
            onTap: () => Navigator.pop(c, 'existing'),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: T.ok(context).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: T.ok(context).withValues(alpha: 0.6)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.playlist_play, color: T.ok(context), size: 16),
                  const SizedBox(width: 6),
                  Expanded(child: Text('AVVIA QUELLA GIÀ PRONTA IN EKOS'.tr(context),
                      style: TextStyle(color: T.ok(context), fontWeight: FontWeight.w700))),
                ]),
                const SizedBox(height: 4),
                Text('Preme play sulla sequenza che hai già preparato sul desktop del Pi. Non tocca nulla: né puntamento, né guida, né i tuoi job.'.tr(context),
                    style: TextStyle(color: T.muted(context), fontSize: 11)),
                const SizedBox(height: 3),
                Text('→ Usala se hai già configurato tutto in Ekos.'.tr(context),
                    style: TextStyle(color: T.ok(context), fontSize: 11, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          // Opzione 4 (ultima, avanzata): comando diretto al driver INDI
          InkWell(
            onTap: () => Navigator.pop(c, 'direct'),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: T.line(context)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.bolt, color: T.muted(context), size: 16),
                  const SizedBox(width: 6),
                  Expanded(child: Text('DIRETTO — avanzato'.tr(context),
                      style: TextStyle(color: T.muted(context), fontWeight: FontWeight.w700))),
                ]),
                const SizedBox(height: 4),
                Text('Comanda la camera saltando Ekos: niente dither né autofocus, e la sequenza non compare in Ekos.'.tr(context),
                    style: TextStyle(color: T.muted(context), fontSize: 11)),
                const SizedBox(height: 3),
                Text('→ Solo per prove veloci.'.tr(context),
                    style: TextStyle(color: T.muted(context), fontSize: 11, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          Text(filterDev == null
              ? 'No filter wheel: filter ignorato per ogni job.'.tr(context)
              : '${'Filter wheel: '.tr(context)}$filterDev',
              style: TextStyle(color: T.muted(context), fontSize: 11)),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: Text('ANNULLA'.tr(context))),
      ],
    ));

    if (choice == 'observation') {
      if (!mounted) return;
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => ObservationScreen(jobs: List.of(s.captureJobs)),
      ));
    } else if (choice == 'ekos') {
      await _runViaEkos(s);
    } else if (choice == 'existing') {
      await _runExistingEkos(s);
    } else if (choice == 'direct') {
      await _runner.run(camera: camera, filterWheel: filterDev);
    }
  }

  /// v0.2.56: avvia la sequenza GIÀ caricata nella Capture queue di Ekos
  /// (nessun clear/load dei job dell'app). È la modalità più non-invasiva:
  /// rispetta puntamento, guida PHD2, cooler e la sequenza già pianificata
  /// a mano nella UI di Ekos sul desktop.
  Future<void> _runExistingEkos(AppState s) async {
    if (s.api == null) return;
    try {
      final alive = await s.api!.captureEkosAlive();
      if (alive['alive'] != true) {
        if (!mounted) return;
        showSnack(context, 'Ekos non raggiungibile via DBus'.tr(context), error: true);
        return;
      }
      final r = await s.api!.captureEkosStartExisting();
      if (!mounted) return;
      if (r['ok'] == true && r['started'] == true) {
        final n = r['job_count'] ?? '?';
        final dith = r['auto_dither_enabled'] == true
            ? 'dither ON'.tr(context)
            : 'dither OFF'.tr(context);
        showSnack(context,
            '${'Sequenza Ekos avviata · '.tr(context)}$n ${'job · '.tr(context)}$dith');
        // Refresh immediato del banner "SEQUENZA EKOS IN CORSO" + tasto FERMA.
        Future.delayed(const Duration(milliseconds: 800), _refreshEkosStatus);
      } else {
        showSnack(context, '${'Errore: '.tr(context)}${r['start_response'] ?? r}', error: true);
      }
    } on ApiException catch (e) {
      // 409 = nessuna sequenza caricata in Ekos: messaggio guida esplicito.
      if (mounted) showSnack(context, '${'Errore: '.tr(context)}${e.body}', error: true);
    } catch (e) {
      if (mounted) showSnack(context, '${'Errore: '.tr(context)}$e', error: true);
    }
  }

  Future<void> _runViaEkos(AppState s) async {
    if (s.api == null) return;
    try {
      // Verifica Ekos vivo
      final alive = await s.api!.captureEkosAlive();
      if (alive['alive'] != true) {
        if (!mounted) return;
        showSnack(context, 'Ekos non raggiungibile via DBus'.tr(context), error: true);
        return;
      }
      // Trova target name (dal primo job se presente)
      String? target;
      for (final j in s.captureJobs) {
        if (j.targetName != null && j.targetName!.isNotEmpty) {
          target = j.targetName; break;
        }
      }
      final r = await s.api!.captureEkosRun(
        jobs: s.captureJobs.map((j) => j.toJson()).toList(),
        target: target,
        autoStart: true,
        // v0.2.36: passa override dither config (se l'utente ha toccato il
        // pannello Guide → Dither config). Se nulli, il bridge usa i
        // valori di Ekos (kstarsrc) come default.
        ditherAmount: s.ditherAmountPx,
        ditherSettleTime: s.ditherSettleSec,
        ditherSettlePixels: s.ditherSettlePixels,
        ditherFrequency: s.ditherFrequency,
        ditherRaOnly: s.ditherRaOnly,
      );
      if (!mounted) return;
      if (r['loaded'] == true && r['started'] == true) {
        showSnack(context,
            '${'Sequenza inviata a Ekos · '.tr(context)}${r['jobs_count']} ${'job · train'.tr(context)} "${r['start_response']}"');
        // Forza un refresh immediato dello stato Ekos in modo che il banner
        // "SEQUENZA EKOS IN CORSO" + pulsante FERMA appaiano subito, senza
        // dover aspettare il prossimo tick del polling da 3s.
        Future.delayed(const Duration(milliseconds: 800), _refreshEkosStatus);
      } else {
        showSnack(context, '${'Errore: '.tr(context)}${r['load_response'] ?? r}', error: true);
      }
    } on ApiException catch (e) {
      if (mounted) showSnack(context, '${'Errore: '.tr(context)}${e.body}', error: true);
    } catch (e) {
      if (mounted) showSnack(context, '${'Errore: '.tr(context)}$e', error: true);
    }
  }

  /// v0.2.48 (P6): mostra le sequenze .esq presenti sul Pi e ne carica una
  /// in Ekos (loadSequenceQueue lato bridge). Conferma esplicita prima.
  Future<void> _loadSequenceFromPi() async {
    final s = context.read<AppState>();
    if (s.api == null) return;
    Map<String, dynamic>? res;
    try {
      res = await s.api!.listSequences();
    } catch (e) {
      if (mounted) showSnack(context, '${'Errore: '.tr(context)}$e', error: true);
      return;
    }
    if (!mounted) return;
    final items = (res['items'] as List?) ?? [];
    if (items.isEmpty) {
      showSnack(context, 'Nessuna sequenza .esq trovata sul Pi'.tr(context));
      return;
    }
    showModalBottomSheet(context: context, backgroundColor: T.panel(context),
      builder: (c) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(padding: const EdgeInsets.all(14),
            child: Text('Carica sequenza dal Pi'.tr(context),
                style: TextStyle(color: T.text(context), fontWeight: FontWeight.w700, fontSize: 16))),
        Flexible(child: ListView(shrinkWrap: true, children: [
          for (final it in items)
            ListTile(
              leading: Icon(Icons.queue, color: T.accent(context)),
              title: Text(it['name'] ?? ''),
              subtitle: Text('~/${it['dir'] ?? ''}',
                  style: TextStyle(color: T.muted(context), fontSize: 11, fontFamily: 'monospace')),
              onTap: () async {
                Navigator.pop(c);
                await _confirmLoadSequence(s, it['path'] ?? '', it['name'] ?? '');
              },
            ),
        ])),
      ])));
  }

  Future<void> _confirmLoadSequence(AppState s, String path, String name) async {
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      backgroundColor: T.panel(context),
      title: Text('Caricare questa sequenza?'.tr(context)),
      content: Text('$name\n\n${'Sostituirà la coda Capture attuale in Ekos.'.tr(context)}'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text('ANNULLA'.tr(context))),
        ElevatedButton(onPressed: () => Navigator.pop(c, true), child: Text('CARICA'.tr(context))),
      ],
    ));
    if (ok != true) return;
    try {
      await s.api!.loadSequenceFile(path, autoStart: false);
      if (mounted) showSnack(context, '${'Sequenza caricata: '.tr(context)}$name');
    } on ApiException catch (e) {
      if (mounted) showSnack(context, '${'Errore: '.tr(context)}${e.body}', error: true);
    } catch (e) {
      if (mounted) showSnack(context, '${'Errore: '.tr(context)}$e', error: true);
    }
  }

  Future<void> _showPresets() async {
    final s = context.read<AppState>();
    final presets = await CaptureJobsStore.loadPresets();
    if (!mounted) return;
    showModalBottomSheet(context: context, backgroundColor: T.panel(context), builder: (c) {
      return SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: const Icon(Icons.save),
          title: Text('Salva sequenza corrente come preset'.tr(context)),
          onTap: () async {
            Navigator.pop(c);
            final name = await _askName('Nome preset'.tr(context));
            if (name != null && name.isNotEmpty) {
              await CaptureJobsStore.savePreset(name, s.captureJobs);
              if (mounted) showSnack(context, '${'Preset "'.tr(context)}$name${'" salvato'.tr(context)}');
            }
          },
        ),
        const Divider(),
        if (presets.isEmpty)
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text('Nessun preset salvato'.tr(context), style: TextStyle(color: T.muted(context))),
          )
        else for (final entry in presets.entries)
          ListTile(
            leading: const Icon(Icons.bookmark),
            title: Text(entry.key),
            subtitle: Text('${entry.value.length} ${'job'.tr(context)}'),
            trailing: IconButton(
              icon: Icon(Icons.delete_outline, color: T.err(context), size: 18),
              onPressed: () async {
                await CaptureJobsStore.deletePreset(entry.key);
                if (mounted) Navigator.pop(c);
              },
            ),
            onTap: () {
              s.captureJobs = List.of(entry.value);
              s.saveCaptureJobs();
              s.notifyListeners();
              Navigator.pop(c);
              showSnack(context, '${'Caricato preset "'.tr(context)}${entry.key}"');
            },
          ),
      ]));
    });
  }

  Future<String?> _askName(String label) async {
    final ctl = TextEditingController();
    return showDialog<String>(context: context, builder: (c) => AlertDialog(
      backgroundColor: T.panel(context),
      title: Text(label),
      content: TextField(controller: ctl, autofocus: true,
          decoration: InputDecoration(hintText: 'es. M31 LRGB'.tr(context))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: Text('ANNULLA'.tr(context))),
        ElevatedButton(onPressed: () => Navigator.pop(c, ctl.text.trim()), child: const Text('OK')),
      ],
    ));
  }
}
