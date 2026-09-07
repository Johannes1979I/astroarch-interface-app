import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../api/api_client.dart';
import '../../i18n/strings.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

/// Tab Plate Solve — clone Ekos Align user-friendly per mobile.
/// Comandi via DBus, immagine live via WebSocket /ws/frames.
class PlateSolveTab extends StatefulWidget {
  const PlateSolveTab({super.key});
  @override
  State<PlateSolveTab> createState() => _PlateSolveTabState();
}

class _PlateSolveTabState extends State<PlateSolveTab> {
  Map<String, dynamic>? _full;
  Timer? _pollTimer;
  bool _busy = false;

  // Parametri editabili
  final TextEditingController _expCtl = TextEditingController(text: '5');
  final TextEditingController _gainCtl = TextEditingController(text: '100');
  int _binIndex = 1;
  // Ekos AlignSolverAction enum: 0=Sync, 1=Slew, 2=Nothing
  int _solverAction = 0;       // default: Sync
  int _solverMode = 0;         // 0=StellarSolver, 1=Remote
  bool _showLog = false;

  static const _kBin = 'pl_bin';
  // v2: nuovo enum (0=Sync, 1=Slew, 2=Nothing) — la chiave vecchia 'pl_action'
  // aveva mapping sbagliato, salto a 'pl_action_v2' per non ereditare valori
  // shiftati dalle installazioni precedenti.
  static const _kAction = 'pl_action_v2';
  static const _kMode = 'pl_mode';
  static const _kExp = 'pl_exp';
  static const _kGain = 'pl_gain';

  final List<Map<String, dynamic>> _history = [];

  @override
  void initState() {
    super.initState();
    _loadPrefs().then((_) {
      // Sincronizza subito l'azione selezionata con Ekos all'apertura della
      // tab. Così m_CurrentGotoMode è già allineato anche se l'utente non
      // tocca i chip prima di "Acquisisci e Risolvi".
      if (!mounted) return;
      final s = context.read<AppState>();
      _pushActionToEkos(s, _solverAction);
    });
    _startPolling();
  }

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _binIndex = p.getInt(_kBin) ?? 1;
      _solverAction = p.getInt(_kAction) ?? 0;
      _solverMode = p.getInt(_kMode) ?? 0;
      final e = p.getDouble(_kExp);
      if (e != null) _expCtl.text = e.toString();
      final g = p.getDouble(_kGain);
      if (g != null) _gainCtl.text = g.toInt().toString();
    });
  }

  Future<void> _savePrefs() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kBin, _binIndex);
    await p.setInt(_kAction, _solverAction);
    await p.setInt(_kMode, _solverMode);
    final e = double.tryParse(_expCtl.text.replaceAll(',', '.'));
    if (e != null) await p.setDouble(_kExp, e);
    final g = double.tryParse(_gainCtl.text);
    if (g != null) await p.setDouble(_kGain, g);
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
    _poll();
  }

  Future<void> _poll() async {
    final s = context.read<AppState>();
    if (s.api == null) return;
    try {
      final f = await s.api!.alignEkosFullStatus();
      final wasComplete = (_full?['status'] == 'complete');
      final nowComplete = (f['status'] == 'complete');
      _full = f;
      if (mounted) setState(() {});
      if (!wasComplete && nowComplete) {
        final sol = f['solution'] as Map<String, dynamic>?;
        final tgt = f['target'] as Map<String, dynamic>?;
        // v0.2.23: rimosso l'auto-update del target dopo Sync. Era stato
        // aggiunto in v0.2.20 con buone intenzioni, ma in pratica modifica
        // lo stato di Ekos senza che l'utente lo veda — confonde l'utente
        // se poi cambia chip su Slew e si chiede perché ora il target è
        // diverso. Meglio modificarlo SOLO esplicitamente via il dialog
        // "Aggiorna target = mount" o il pulsante apposito.
        if (sol != null) {
          _history.insert(0, {
            'ts': DateTime.now(),
            'ra_hours': sol['ra_hours'],
            'dec_deg': sol['dec_deg'],
            'd_ra': tgt == null ? null : ((sol['ra_hours'] as num) - (tgt['ra_hours'] as num)) * 15 * 3600,
            'd_dec': tgt == null ? null : ((sol['dec_deg'] as num) - (tgt['dec_deg'] as num)) * 3600,
          });
          if (_history.length > 20) _history.removeLast();
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _expCtl.dispose();
    _gainCtl.dispose();
    super.dispose();
  }

  Future<void> _captureAndSolve(AppState s) async {
    if (s.api == null) return;

    // NUOVA LOGICA v0.2.24: l'app possiede il TARGET ATTIVO localmente
    // (in AppState, persistente). Prima di fare captureAndSolve con
    // azione = Slew/Sync ri-spingiamo il target ad Ekos così Ekos ha
    // SEMPRE le coordinate giuste, anche se KStars o un altro flusso
    // l'aveva lasciato stantio.
    //
    // Caso speciale: se l'utente ha scelto Slew ma non ha mai impostato
    // un target attivo nell'app, ci fermiamo per chiederglielo (non
    // possiamo inventarci dove sleware).
    if (_solverAction == 1 /* Slew to target */ &&
        (s.activeTargetRaHours == null || s.activeTargetDecDeg == null)) {
      final choice = await _noTargetDialog(s);
      if (choice == null) return; // cancel
      if (choice == 'use_mount') {
        final mRa = (_full?['mount_coords']?['ra_hours'] as num?)?.toDouble();
        final mDec = (_full?['mount_coords']?['dec_deg'] as num?)?.toDouble();
        if (mRa != null && mDec != null) {
          await s.setActiveTarget(name: 'Mount position', raHours: mRa, decDeg: mDec);
        }
      } else if (choice == 'pick') {
        final picked = await _pickTargetDialog(s);
        if (picked == null) return;
        // _pickTargetDialog ha già fatto setActiveTarget
      }
    }

    // Ri-spingi sempre il target a Ekos (idempotente, costa nulla)
    if (s.activeTargetRaHours != null && s.activeTargetDecDeg != null) {
      try {
        await s.api!.alignEkosSet(
            targetRaHours: s.activeTargetRaHours,
            targetDecDeg: s.activeTargetDecDeg);
      } catch (_) {}
    }

    setState(() => _busy = true);
    try {
      await _savePrefs();
      final exp = double.tryParse(_expCtl.text.replaceAll(',', '.'));
      final gain = double.tryParse(_gainCtl.text);
      await s.api!.alignEkosSet(solverMode: _solverMode);
      await s.api!.alignEkosCaptureAndSolve(
        binIndex: _binIndex,
        solverAction: _solverAction,
        exposureSec: exp,
        gain: gain,
      );
      if (mounted) {
        showSnack(context, '${'Avviato in Ekos · '.tr(context)}${exp ?? "?"}s · bin ${_binIndex+1}×${_binIndex+1} · gain ${gain?.toInt() ?? "auto"}');
      }
    } on ApiException catch (e) {
      if (mounted) showSnack(context, '${'Errore: '.tr(context)}${_extractDetail(e.body)}', error: true);
    } catch (e) {
      if (mounted) showSnack(context, '${'Errore: '.tr(context)}$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Dialog mostrato quando l'utente vuole fare Slew ma non ha mai
  /// impostato un target attivo in app. Tre opzioni: annulla, usa
  /// posizione mount come target, scegli/cerca target.
  Future<String?> _noTargetDialog(AppState s) async {
    final mRa = (_full?['mount_coords']?['ra_hours'] as num?)?.toDouble();
    final mDec = (_full?['mount_coords']?['dec_deg'] as num?)?.toDouble();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Nessun target attivo'.tr(context)),
        content: Text(
          'Hai scelto "Slew to target" ma in app non c\'è un target '
          'attivo. Per evitare slew verso posizioni stantie cosa vuoi fare?'
              .tr(context),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: Text('Annulla'.tr(context)),
          ),
          if (mRa != null && mDec != null)
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'use_mount'),
              child: Text('Usa posizione mount'.tr(context)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'pick'),
            child: Text('Scegli target'.tr(context)),
          ),
        ],
      ),
    );
  }

  /// Dialog di scelta target: SIMBAD search + ingresso manuale RA/Dec
  /// + posizione mount corrente. Ritorna 'ok' se l'utente ha selezionato
  /// (e in tal caso setActiveTarget è già stato chiamato).
  Future<String?> _pickTargetDialog(AppState s) async {
    final simbadCtl = TextEditingController();
    final raCtl = TextEditingController();
    final decCtl = TextEditingController();
    bool busy = false;
    String? err;
    final mRa = (_full?['mount_coords']?['ra_hours'] as num?)?.toDouble();
    final mDec = (_full?['mount_coords']?['dec_deg'] as num?)?.toDouble();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) {
        Future<void> resolveSimbad() async {
          final name = simbadCtl.text.trim();
          if (name.isEmpty || s.api == null) return;
          setSt(() { busy = true; err = null; });
          try {
            final r = await s.api!.simbadSearch(name);
            if (r['ra_hours'] != null && r['dec_deg'] != null) {
              await s.setActiveTarget(
                name: r['name']?.toString() ?? name,
                raHours: (r['ra_hours'] as num).toDouble(),
                decDeg: (r['dec_deg'] as num).toDouble(),
              );
              if (ctx.mounted) Navigator.pop(ctx, 'ok');
            } else {
              setSt(() => err = 'Oggetto non trovato'.tr(context));
            }
          } catch (e) {
            setSt(() => err = '${'Errore: '.tr(context)}$e');
          } finally {
            setSt(() => busy = false);
          }
        }
        Future<void> useManual() async {
          final ra = double.tryParse(raCtl.text.replaceAll(',', '.'));
          final dec = double.tryParse(decCtl.text.replaceAll(',', '.'));
          if (ra == null || dec == null) {
            setSt(() => err = 'RA/Dec non validi'.tr(context));
            return;
          }
          await s.setActiveTarget(name: 'Manuale', raHours: ra, decDeg: dec);
          if (ctx.mounted) Navigator.pop(ctx, 'ok');
        }
        return AlertDialog(
          title: Text('Scegli target'.tr(context)),
          content: SingleChildScrollView(child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // SIMBAD search
            TextField(
              controller: simbadCtl,
              decoration: InputDecoration(
                labelText: 'Cerca su SIMBAD'.tr(context),
                hintText: 'M 13, NGC 7000, Vega…',
                suffixIcon: busy
                    ? const Padding(padding: EdgeInsets.all(12),
                        child: SizedBox(width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2)))
                    : IconButton(
                        icon: const Icon(Icons.search),
                        onPressed: resolveSimbad,
                      ),
              ),
              onSubmitted: (_) => resolveSimbad(),
            ),
            const SizedBox(height: 14),
            Divider(color: T.line(context)),
            const SizedBox(height: 8),
            Text('Oppure inserisci RA/Dec'.tr(context),
                style: TextStyle(color: T.muted(context), fontSize: 11)),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(child: TextField(controller: raCtl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: 'RA (h)'.tr(context),
                    hintText: '16.69'))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: decCtl,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true, signed: true),
                decoration: InputDecoration(labelText: 'Dec (°)'.tr(context),
                    hintText: '36.46'))),
            ]),
            const SizedBox(height: 6),
            SizedBox(width: double.infinity, child: OutlinedButton(
              onPressed: busy ? null : useManual,
              child: Text('Usa queste coordinate'.tr(context)),
            )),
            if (mRa != null && mDec != null) ...[
              const SizedBox(height: 14),
              Divider(color: T.line(context)),
              const SizedBox(height: 8),
              SizedBox(width: double.infinity, child: OutlinedButton.icon(
                icon: const Icon(Icons.my_location, size: 16),
                onPressed: busy ? null : () async {
                  await s.setActiveTarget(name: 'Mount position',
                      raHours: mRa, decDeg: mDec);
                  if (ctx.mounted) Navigator.pop(ctx, 'ok');
                },
                label: Text('${'Usa posizione mount'.tr(context)} '
                    '(${_hms(mRa)} ${_dms(mDec)})',
                    style: const TextStyle(fontSize: 11)),
              )),
            ],
            if (err != null) Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(err!, style: TextStyle(color: T.err(context), fontSize: 12)),
            ),
          ])),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(ctx, null),
              child: Text('Annulla'.tr(context)),
            ),
          ],
        );
      }),
    );
  }

  /// Parsa il body JSON di una ApiException e ritorna solo il campo
  /// "detail" (FastAPI standard), altrimenti il body grezzo.
  /// Senza questo i messaggi d'errore apparivano come
  ///   Errore: {"detail":"could not find star"}
  /// — il fix lo riduce a
  ///   Errore: could not find star
  String _extractDetail(String body) {
    try {
      final j = jsonDecode(body);
      if (j is Map && j['detail'] != null) return j['detail'].toString();
    } catch (_) {}
    return body;
  }

  Future<void> _abort(AppState s) async {
    try {
      await s.api!.alignEkosAbort();
      if (mounted) showSnack(context, 'Abort inviato'.tr(context));
    } catch (e) {
      if (mounted) showSnack(context, '${'Errore: '.tr(context)}$e', error: true);
    }
  }

  // -------------------- BUILD ---------------------------------------------

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final st = _full?['status']?.toString() ?? 'unknown';
    // "inProgress" copre lo stato del modulo Ekos Align (capture+solve in corso).
    // Ma dopo che Ekos completa il solve con azione=Slew, lo status torna a
    // "complete" mentre la MONTATURA è ancora in movimento: durante quella
    // finestra dobbiamo lo stesso bloccare il pulsante (come fa Ekos).
    // INDI espone EQUATORIAL_EOD_COORD.state="Busy" finché lo slew non finisce.
    final mountState = (_full?['mount_coords'] as Map?)?['state']?.toString();
    final mountSlewing = mountState == 'Busy';
    final inProgress = st == 'progress' || st == 'syncing' || st == 'slewing';
    final lockUI = inProgress || mountSlewing;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 80),
      children: [
        _imagePreviewCard(s, st, lockUI, mountSlewing),
        const SizedBox(height: 10),
        // TARGET ATTIVO in cima: l'app possiede il target (persistente),
        // viene ri-spinto a Ekos prima di ogni captureAndSolve.
        // Questo risolve il problema dove KStars "Center & Slew" non
        // aggiorna m_targetCoord di Ekos Align → Slew finiva al target
        // stantio di una sessione precedente.
        _targetSelectorCard(s, lockUI),
        const SizedBox(height: 10),
        _quickParamsCard(lockUI),
        const SizedBox(height: 10),
        _bigActionButton(s, inProgress, mountSlewing),
        const SizedBox(height: 8),
        _solverActionRow(lockUI),
        const SizedBox(height: 10),
        // Mostra la solution SOLO se l'ultimo run è effettivamente completato.
        // Ekos restituisce sempre l'ultima solution riuscita (anche stale dopo
        // un fail successivo): senza questo check vedremmo dati stantii.
        if (_full?['solution'] != null && _full?['status'] == 'complete')
          _solutionResultCard()
        else if (_full?['status'] == 'failed')
          _failedCard()
        else if (_full?['status'] == 'aborted')
          _abortedCard(),
        const SizedBox(height: 10),
        _telescopeInfoCard(),
        const SizedBox(height: 8),
        _targetPlotCard(),
        const SizedBox(height: 8),
        _historyCard(),
        const SizedBox(height: 8),
        ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          title: Text('Avanzate · solver mode, optical train, log'.tr(context),
              style: TextStyle(color: T.muted(context), fontSize: 12)),
          collapsedBackgroundColor: T.panel(context),
          backgroundColor: T.panel(context),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: T.line(context)),
          ),
          collapsedShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: T.line(context)),
          ),
          children: [
            Padding(padding: const EdgeInsets.all(10),
                child: _advancedSection(lockUI)),
          ],
        ),
      ],
    );
  }

  Widget _imagePreviewCard(AppState s, String st, bool inProgress, bool mountSlewing) {
    final hasFrame = s.lastFrameJpeg != null;
    final m = s.lastFrameMeta;

    Color statusColor;
    IconData statusIcon;
    String statusLabel;
    // Se la montatura è in slew (post-solve verso il target) l'HUD lo dice
    // anche se Ekos Align ha già status=complete.
    if (mountSlewing) {
      statusColor = T.accent(context); statusIcon = Icons.sync;
      statusLabel = 'SLEW TO TARGET…'.tr(context);
    } else {
      switch (st) {
        case 'complete':
          statusColor = T.ok(context); statusIcon = Icons.check_circle;
          statusLabel = 'COMPLETE'.tr(context); break;
        case 'failed':
          statusColor = T.err(context); statusIcon = Icons.error;
          statusLabel = 'FAILED'.tr(context); break;
        case 'aborted':
          statusColor = T.warn(context); statusIcon = Icons.cancel;
          statusLabel = 'ABORTED'.tr(context); break;
        case 'progress':
        case 'syncing':
        case 'slewing':
          statusColor = T.accent(context); statusIcon = Icons.sync;
          statusLabel = st.toUpperCase().tr(context); break;
        case 'idle':
          statusColor = T.muted(context); statusIcon = Icons.radio_button_unchecked;
          statusLabel = 'IDLE'.tr(context); break;
        default:
          statusColor = T.err(context); statusIcon = Icons.help_outline;
          statusLabel = 'EKOS NON CONNESSO'.tr(context);
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.black, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withValues(alpha: 0.5), width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: AspectRatio(
        aspectRatio: 16 / 11,
        child: Stack(fit: StackFit.expand, children: [
          if (hasFrame)
            InteractiveViewer(
              minScale: 1, maxScale: 5,
              child: Image.memory(s.lastFrameJpeg!,
                  fit: BoxFit.contain, gaplessPlayback: true),
            )
          else
            Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.image_outlined, size: 42,
                  color: Colors.white.withValues(alpha: 0.3)),
              const SizedBox(height: 8),
              Text('Nessuna immagine ancora\nTappa "ACQUISISCI E RISOLVI"'.tr(context),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 12)),
            ])),
          // Overlay HUD top-left
          Positioned(top: 8, left: 8, child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: Colors.black54,
                borderRadius: BorderRadius.circular(6)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (inProgress)
                SizedBox(width: 10, height: 10, child:
                    CircularProgressIndicator(strokeWidth: 1.5, color: statusColor))
              else
                Icon(statusIcon, color: statusColor, size: 12),
              const SizedBox(width: 5),
              Text(statusLabel, style: TextStyle(color: statusColor,
                  fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1)),
            ]),
          )),
          // HUD top-right metadata
          if (hasFrame) Positioned(top: 8, right: 8, child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: Colors.black54,
                borderRadius: BorderRadius.circular(6)),
            child: Text(
              'HFR ${(m['hfr'] as num?)?.toStringAsFixed(2) ?? '—'} · '
              '★ ${m['stars'] ?? '—'} · '
              '${m['width'] ?? '—'}×${m['height'] ?? '—'}',
              style: const TextStyle(color: Colors.white,
                  fontFamily: 'monospace', fontSize: 9),
            ),
          )),
          // HUD bottom
          if (hasFrame) Positioned(bottom: 6, left: 8, right: 8, child: Row(
            children: [
              if (m['exposure'] != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Colors.black54,
                      borderRadius: BorderRadius.circular(4)),
                  child: Text('${m['exposure']}s',
                      style: const TextStyle(color: Colors.white,
                          fontFamily: 'monospace', fontSize: 9)),
                ),
              const Spacer(),
              if (m['filter'] != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Colors.black54,
                      borderRadius: BorderRadius.circular(4)),
                  child: Text(m['filter'].toString(),
                      style: const TextStyle(color: Colors.white,
                          fontFamily: 'monospace', fontSize: 9)),
                ),
            ],
          )),
        ]),
      ),
    );
  }

  Widget _quickParamsCard(bool inProgress) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: T.panel(context), borderRadius: BorderRadius.circular(12),
        border: Border.all(color: T.line(context)),
      ),
      child: Column(children: [
        Row(children: [
          Expanded(child: _numField(_expCtl, 'TEMPO (s)'.tr(context),
              decimal: true, enabled: !inProgress)),
          const SizedBox(width: 8),
          Expanded(child: _numField(_gainCtl, 'GAIN'.tr(context),
              enabled: !inProgress)),
        ]),
        const SizedBox(height: 10),
        Text('BINNING'.tr(context), style: TextStyle(color: T.muted(context),
            fontSize: 10, letterSpacing: 1.4)),
        const SizedBox(height: 4),
        Row(children: [
          for (int b = 1; b <= 4; b++) ...[
            Expanded(child: ChipToggle(
              label: '${b}×$b', selected: _binIndex == b - 1,
              onTap: inProgress ? null : () => setState(() => _binIndex = b - 1),
            )),
            if (b < 4) const SizedBox(width: 4),
          ],
        ]),
      ]),
    );
  }

  Widget _bigActionButton(AppState s, bool inProgress, bool mountSlewing) {
    // Pulsante disabilitato sia mentre Ekos sta eseguendo capture/solve sia
    // mentre la montatura è in slew verso il target (post-solve).
    // Si riattiva SOLO quando la montatura ha raggiunto il bersaglio, esatto
    // come fa Ekos.
    final disabled = _busy || inProgress || mountSlewing;
    final IconData icon;
    final String label;
    if (mountSlewing) {
      icon = Icons.sync;
      label = 'MONTATURA IN SLEW…'.tr(context);
    } else if (inProgress) {
      icon = Icons.sync;
      label = 'IN CORSO IN EKOS…'.tr(context);
    } else if (_busy) {
      icon = Icons.gps_fixed;
      label = 'INVIO…'.tr(context);
    } else {
      icon = Icons.gps_fixed;
      label = 'ACQUISISCI E RISOLVI'.tr(context);
    }
    return Row(children: [
      Expanded(child: SizedBox(
        height: 56,
        child: ElevatedButton.icon(
          onPressed: disabled ? null : () => _captureAndSolve(s),
          icon: Icon(icon, size: 20),
          label: Text(label,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                letterSpacing: .5),
          ),
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      )),
      const SizedBox(width: 8),
      SizedBox(
        height: 56, width: 56,
        child: OutlinedButton(
          // Abort utile sia durante capture/solve sia per fermare lo slew finale.
          onPressed: (inProgress || mountSlewing) ? () => _abort(s) : null,
          style: OutlinedButton.styleFrom(
            foregroundColor: T.err(context),
            side: BorderSide(color: T.err(context).withValues(alpha: 0.5)),
            padding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Icon(Icons.stop, size: 22),
        ),
      ),
    ]);
  }

  /// Spinge l'azione a Ekos IMMEDIATAMENTE al tap del chip.
  /// Era la causa principale del bug "i pulsanti non funzionano":
  /// inviare setSolverAction insieme a captureAndSolve creava una race
  /// condition (Q_NOREPLY async vs bool sync su due qdbus6 separati).
  /// Inviare l'action subito al cambio chip dà a Ekos tutto il tempo di
  /// aggiornare m_CurrentGotoMode prima che l'utente prema "Acquisisci".
  Future<void> _pushActionToEkos(AppState s, int action) async {
    if (s.api == null) return;
    try {
      await s.api!.alignEkosSet(solverAction: action);
      if (mounted) {
        final labels = {0: 'Sync', 1: 'Slew to target', 2: 'Niente'};
        showSnack(context,
            '${'AZIONE: '.tr(context)}${(labels[action] ?? '?').tr(context)} → Ekos');
      }
    } catch (e) {
      if (mounted) showSnack(context, '${'Errore: '.tr(context)}$e', error: true);
    }
  }

  /// Card che mostra le coordinate TARGET attualmente impostate in Ekos
  /// con warning se sono distanti più di 30° dalla posizione del mount
  /// (= target probabilmente stantio da sessione precedente), e con un
  /// pulsante per impostare target = posizione corrente della montatura.
  /// Card del TARGET ATTIVO posseduto dall'app (AppState.activeTarget*).
  /// Mostra nome + RA/Dec, Δ vs mount, e segnala se il target Ekos diverge
  /// (es. KStars l'ha cambiato). Bottoni: Cambia target, Sincronizza ad
  /// Ekos (rispingi).
  Widget _targetSelectorCard(AppState s, bool lockUI) {
    final mount = _full?['mount_coords'] as Map<String, dynamic>?;
    final ekosTgt = _full?['target'] as Map<String, dynamic>?;
    final mRa = (mount?['ra_hours'] as num?)?.toDouble();
    final mDec = (mount?['dec_deg'] as num?)?.toDouble();
    final tRa = s.activeTargetRaHours;
    final tDec = s.activeTargetDecDeg;
    final hasAppTarget = tRa != null && tDec != null;

    // Δ app-target vs mount: utile per capire se "Slew to target" porterà
    // lontano la montatura
    double? distMount;
    if (hasAppTarget && mRa != null && mDec != null) {
      final dRa = (tRa - mRa) * 15.0 * math.cos(mDec * math.pi / 180.0);
      final dDec = tDec - mDec;
      distMount = math.sqrt(dRa * dRa + dDec * dDec);
    }
    // Δ app-target vs ekos-target: se differiscono, Ekos ha un target
    // diverso dal nostro (es. KStars l'ha sovrascritto) → consigliamo
    // di rispingere.
    double? deltaEkos;
    if (hasAppTarget && ekosTgt != null) {
      final eRa = (ekosTgt['ra_hours'] as num?)?.toDouble();
      final eDec = (ekosTgt['dec_deg'] as num?)?.toDouble();
      if (eRa != null && eDec != null) {
        final dRa = (tRa - eRa) * 15.0 * math.cos(tDec * math.pi / 180.0);
        final dDec = tDec - eDec;
        deltaEkos = math.sqrt(dRa * dRa + dDec * dDec);
      }
    }
    final ekosDrifted = deltaEkos != null && deltaEkos > 0.1;

    final bg = !hasAppTarget
        ? T.muted(context).withValues(alpha: 0.10)
        : ekosDrifted
            ? T.warn(context).withValues(alpha: 0.10)
            : T.ok(context).withValues(alpha: 0.05);
    final border = !hasAppTarget
        ? T.muted(context).withValues(alpha: 0.4)
        : ekosDrifted
            ? T.warn(context).withValues(alpha: 0.5)
            : T.ok(context).withValues(alpha: 0.4);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bg, borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(hasAppTarget ? Icons.flag : Icons.flag_outlined,
              size: 14, color: hasAppTarget
                  ? T.accent(context) : T.muted(context)),
          const SizedBox(width: 6),
          Text('TARGET ATTIVO'.tr(context), style: TextStyle(
              color: T.muted(context), fontSize: 10,
              letterSpacing: 1.4, fontWeight: FontWeight.w700)),
          if (distMount != null) ...[
            const Spacer(),
            Text('${'Δ mount '.tr(context)}${distMount.toStringAsFixed(1)}°',
                style: TextStyle(color: T.muted(context),
                    fontSize: 11, fontFamily: 'monospace')),
          ],
        ]),
        const SizedBox(height: 6),
        if (hasAppTarget) ...[
          if (s.activeTargetName != null) Text(s.activeTargetName!,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 2),
          Row(children: [
            Expanded(child: _smallKv('AR', _hms(tRa))),
            Expanded(child: _smallKv('DEC', _dms(tDec))),
          ]),
          if (ekosDrifted) Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(children: [
              Icon(Icons.warning_amber, size: 14, color: T.warn(context)),
              const SizedBox(width: 4),
              Expanded(child: Text(
                'Target di Ekos differisce di '
                '${deltaEkos.toStringAsFixed(2)}°. Verrà ri-spinto al solve.'
                    .tr(context),
                style: TextStyle(color: T.warn(context), fontSize: 11),
              )),
            ]),
          ),
        ] else Text(
            'Nessun target attivo. Sceglilo prima di "Slew to target".'.tr(context),
            style: TextStyle(color: T.muted(context),
                fontSize: 11, fontStyle: FontStyle.italic)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: OutlinedButton.icon(
            onPressed: lockUI ? null : () => _pickTargetDialog(s),
            icon: const Icon(Icons.edit_location_alt, size: 16),
            label: Text(hasAppTarget
                ? 'CAMBIA TARGET'.tr(context)
                : 'SCEGLI TARGET'.tr(context),
                style: const TextStyle(fontSize: 11,
                    fontWeight: FontWeight.w700, letterSpacing: .3)),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 10),
              foregroundColor: T.accent(context),
              side: BorderSide(color: T.accent(context).withValues(alpha: 0.5)),
            ),
          )),
          if (hasAppTarget) ...[
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(
              onPressed: lockUI ? null : () async {
                try {
                  await s.api!.alignEkosSet(
                      targetRaHours: tRa, targetDecDeg: tDec);
                  if (mounted) {
                    showSnack(context, 'Target spinto a Ekos'.tr(context));
                    await _poll();
                  }
                } catch (e) {
                  if (mounted) showSnack(context,
                      '${'Errore: '.tr(context)}$e', error: true);
                }
              },
              icon: const Icon(Icons.cloud_upload, size: 16),
              label: Text('SYNC EKOS'.tr(context),
                  style: const TextStyle(fontSize: 11,
                      fontWeight: FontWeight.w700, letterSpacing: .3)),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 10),
                foregroundColor: T.accent2(context),
                side: BorderSide(color: T.accent2(context).withValues(alpha: 0.5)),
              ),
            )),
          ],
        ]),
      ]),
    );
  }

  Widget _solverActionRow(bool inProgress) {
    final s = context.read<AppState>();
    return Row(children: [
      Text('AZIONE: '.tr(context), style: TextStyle(color: T.muted(context), fontSize: 10,
          letterSpacing: 1.2, fontWeight: FontWeight.w600)),
      const SizedBox(width: 4),
      Expanded(child: Wrap(spacing: 4, runSpacing: 4, children: [
        // Ekos enum: 0=Sync, 1=Slew, 2=Nothing
        ChipToggle(label: 'Sync'.tr(context), selected: _solverAction == 0,
            onTap: inProgress ? null : () {
              setState(() { _solverAction = 0; });
              _savePrefs();
              _pushActionToEkos(s, 0);
            }),
        ChipToggle(label: 'Slew to target'.tr(context), selected: _solverAction == 1,
            onTap: inProgress ? null : () {
              setState(() { _solverAction = 1; });
              _savePrefs();
              _pushActionToEkos(s, 1);
            }),
        ChipToggle(label: 'Niente'.tr(context), selected: _solverAction == 2,
            onTap: inProgress ? null : () {
              setState(() { _solverAction = 2; });
              _savePrefs();
              _pushActionToEkos(s, 2);
            }),
      ])),
    ]);
  }

  Widget _solutionResultCard() {
    final sol = _full!['solution'] as Map<String, dynamic>;
    final tgt = _full?['target'] as Map<String, dynamic>?;
    final fov = _full?['fov'] as Map<String, dynamic>?;
    String? errStr;
    Color errColor = T.muted(context);
    if (tgt != null) {
      final dRa = ((sol['ra_hours'] as num) - (tgt['ra_hours'] as num)) * 15 * 3600;
      final dDec = ((sol['dec_deg'] as num) - (tgt['dec_deg'] as num)) * 3600;
      final err = math.sqrt(dRa * dRa + dDec * dDec);
      errStr = '${err.toStringAsFixed(1)}″';
      if (err < 50) {
        errColor = T.ok(context);
      } else if (err < 150) {
        errColor = T.warn(context);
      } else {
        errColor = T.err(context);
      }
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: T.ok(context).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: T.ok(context).withValues(alpha: 0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.check_circle, color: T.ok(context), size: 16),
          const SizedBox(width: 6),
          Text('SOLUZIONE TROVATA'.tr(context), style: TextStyle(
              color: T.ok(context), fontSize: 11,
              fontWeight: FontWeight.w700, letterSpacing: 1)),
          if (errStr != null) ...[
            const Spacer(),
            Text('Err '.tr(context), style: TextStyle(color: T.muted(context), fontSize: 10)),
            Text(errStr, style: TextStyle(color: errColor, fontSize: 13,
                fontWeight: FontWeight.w700, fontFamily: 'monospace')),
          ],
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _bigKv('AR'.tr(context), _hms(sol['ra_hours']))),
          const SizedBox(width: 8),
          Expanded(child: _bigKv('DEC'.tr(context), _dms(sol['dec_deg']))),
        ]),
        const SizedBox(height: 4),
        Wrap(spacing: 14, runSpacing: 4, children: [
          _smallKv('AP', '${(sol['orientation_deg'] as num).toStringAsFixed(2)}°'),
          if (fov != null)
            _smallKv('Pix', '${(fov['pixel_scale_arcsec_px'] as num).toStringAsFixed(2)} ″/px'),
          if (fov != null)
            _smallKv('FOV', '${(fov['w_arcmin'] as num).toStringAsFixed(1)}′ × '
                '${(fov['h_arcmin'] as num).toStringAsFixed(1)}′'),
        ]),
      ]),
    );
  }

  Widget _failedCard() {
    final log = (_full?['log'] as List? ?? []).cast<String>();
    final lastErr = log.isEmpty ? null : log.firstWhere(
        (l) => l.toLowerCase().contains('non riuscit') || l.toLowerCase().contains('fail'),
        orElse: () => log.first);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: T.err(context).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: T.err(context).withValues(alpha: 0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.error, color: T.err(context), size: 16),
          const SizedBox(width: 6),
          Text('SOLVE FALLITO'.tr(context), style: TextStyle(
              color: T.err(context), fontSize: 11,
              fontWeight: FontWeight.w700, letterSpacing: 1)),
        ]),
        const SizedBox(height: 6),
        Text('Possibili cause: poche stelle, focus errato, scale hint sbagliato, tempo di esposizione insufficiente, image bianca/saturata.'.tr(context),
            style: TextStyle(color: T.muted(context), fontSize: 11)),
        if (lastErr != null) Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(lastErr,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 10)),
        ),
      ]),
    );
  }

  Widget _abortedCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: T.warn(context).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: T.warn(context).withValues(alpha: 0.4)),
      ),
      child: Row(children: [
        Icon(Icons.cancel, color: T.warn(context), size: 16),
        const SizedBox(width: 8),
        Text('Solve interrotto'.tr(context),
            style: TextStyle(color: T.warn(context),
                fontWeight: FontWeight.w700, fontSize: 12)),
      ]),
    );
  }

  Widget _telescopeInfoCard() {
    final m = _full?['mount_coords'] as Map<String, dynamic>?;
    final tel = _full?['telescope'] as Map<String, dynamic>?;
    final cam = _full?['camera']?.toString();
    final filter = _full?['filter']?.toString();
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: T.panel(context), borderRadius: BorderRadius.circular(10),
        border: Border.all(color: T.line(context)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('TELESCOPIO + STRUMENTAZIONE'.tr(context),
            style: TextStyle(color: T.muted(context),
                fontSize: 10, letterSpacing: 1.4, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(child: _smallKv('Mount RA'.tr(context),
              m == null ? '—' : _hms(m['ra_hours']))),
          Expanded(child: _smallKv('Mount DEC'.tr(context),
              m == null ? '—' : _dms(m['dec_deg']))),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          if (tel != null) Expanded(child: _smallKv('Focale'.tr(context),
              '${(tel['focal_length_mm'] as num).toStringAsFixed(0)}mm f/${(tel['f_ratio'] as num?)?.toStringAsFixed(1) ?? '—'}')),
          if (cam != null) Expanded(child: _smallKv('Cam'.tr(context), cam,
              ellipsis: true)),
          if (filter != null) Expanded(child: _smallKv('Filtro'.tr(context), filter)),
        ]),
      ]),
    );
  }

  Widget _targetPlotCard() {
    final last = _history.isEmpty ? null : _history.first;
    final dRa = (last?['d_ra'] as num?)?.toDouble();
    final dDec = (last?['d_dec'] as num?)?.toDouble();
    if (_history.isEmpty) return const SizedBox();
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: T.panel(context), borderRadius: BorderRadius.circular(10),
        border: Border.all(color: T.line(context)),
      ),
      child: Column(children: [
        Row(children: [
          Text('ERRORE PUNTAMENTO'.tr(context),
              style: TextStyle(color: T.muted(context), fontSize: 10,
                  letterSpacing: 1.4, fontWeight: FontWeight.w700)),
          const Spacer(),
          if (dRa != null && dDec != null)
            Text('dAR ${dRa.toStringAsFixed(1)}″  dDEC ${dDec.toStringAsFixed(1)}″',
                style: TextStyle(color: T.muted(context),
                    fontFamily: 'monospace', fontSize: 10)),
        ]),
        const SizedBox(height: 6),
        AspectRatio(aspectRatio: 1.6, child: CustomPaint(
          painter: _TargetPlotPainter(
            dRa: dRa, dDec: dDec,
            history: _history.take(5).toList(),
            okColor: T.ok(context), warnColor: T.warn(context),
            errColor: T.err(context), mutedColor: T.muted(context),
            textColor: T.text(context), accentColor: T.accent(context),
          ),
        )),
      ]),
    );
  }

  Widget _historyCard() {
    if (_history.isEmpty) return const SizedBox();
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: T.panel(context), borderRadius: BorderRadius.circular(10),
        border: Border.all(color: T.line(context)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${'STORICO SOLVE (ultimi '.tr(context)}${_history.length})',
            style: TextStyle(color: T.muted(context), fontSize: 10,
                letterSpacing: 1.4, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        for (int i = 0; i < _history.length && i < 5; i++) Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            SizedBox(width: 18, child: Text('${i + 1}',
                style: TextStyle(color: T.muted(context),
                    fontFamily: 'monospace', fontSize: 10))),
            Expanded(flex: 3, child: Text(_hms(_history[i]['ra_hours']),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11))),
            Expanded(flex: 3, child: Text(_dms(_history[i]['dec_deg']),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11))),
            Expanded(flex: 2, child: Text(
                _history[i]['d_ra'] == null ? '—'
                    : '${(_history[i]['d_ra'] as double).toStringAsFixed(0)}″',
                textAlign: TextAlign.right,
                style: TextStyle(fontFamily: 'monospace', fontSize: 11,
                    color: _errColor(_history[i])))),
            Expanded(flex: 2, child: Text(
                _history[i]['d_dec'] == null ? '—'
                    : '${(_history[i]['d_dec'] as double).toStringAsFixed(0)}″',
                textAlign: TextAlign.right,
                style: TextStyle(fontFamily: 'monospace', fontSize: 11,
                    color: _errColor(_history[i])))),
          ]),
        ),
      ]),
    );
  }

  Color _errColor(Map<String, dynamic> h) {
    final dRa = (h['d_ra'] as num?)?.toDouble();
    final dDec = (h['d_dec'] as num?)?.toDouble();
    if (dRa == null || dDec == null) return T.muted(context);
    final err = math.sqrt(dRa * dRa + dDec * dDec);
    if (err < 50) return T.ok(context);
    if (err < 150) return T.warn(context);
    return T.err(context);
  }

  Widget _advancedSection(bool inProgress) {
    final log = (_full?['log'] as List? ?? []).cast<String>();
    final train = _full?['opticalTrain']?.toString() ?? '—';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _smallKv('Optical train'.tr(context), train),
      const SizedBox(height: 8),
      Text('MODALITÀ SOLVER'.tr(context),
          style: TextStyle(color: T.muted(context), fontSize: 10, letterSpacing: 1.4)),
      const SizedBox(height: 4),
      Row(children: [
        Expanded(child: ChipToggle(
          label: 'StellarSolver'.tr(context), selected: _solverMode == 0,
          onTap: inProgress ? null : () async {
            setState(() => _solverMode = 0);
            _savePrefs();
            final s = context.read<AppState>();
            if (s.api != null) await s.api!.alignEkosSet(solverMode: 0);
          },
        )),
        const SizedBox(width: 6),
        Expanded(child: ChipToggle(
          label: 'Remote (INDI)'.tr(context), selected: _solverMode == 1,
          onTap: inProgress ? null : () async {
            setState(() => _solverMode = 1);
            _savePrefs();
            final s = context.read<AppState>();
            if (s.api != null) await s.api!.alignEkosSet(solverMode: 1);
          },
        )),
      ]),
      const SizedBox(height: 10),
      InkWell(
        onTap: () => setState(() => _showLog = !_showLog),
        child: Row(children: [
          Icon(_showLog ? Icons.expand_more : Icons.chevron_right,
              size: 16, color: T.muted(context)),
          Text('${'Log Ekos Align ('.tr(context)}${log.length}${' righe)'.tr(context)}',
              style: TextStyle(color: T.muted(context), fontSize: 11)),
        ]),
      ),
      if (_showLog) Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF05080e),
          borderRadius: BorderRadius.circular(6),
        ),
        constraints: const BoxConstraints(maxHeight: 160),
        child: SingleChildScrollView(
          child: Text(log.take(20).join('\n'),
              style: const TextStyle(fontFamily: 'monospace',
                  fontSize: 9.5, color: Color(0xFF9aa3b6), height: 1.4)),
        ),
      ),
    ]);
  }

  // -------------------- HELPERS --------------------------------------------

  Widget _numField(TextEditingController c, String label,
      {bool decimal = false, bool enabled = true}) {
    return Container(
      decoration: BoxDecoration(
        color: enabled ? T.panel(context) : T.line(context).withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: T.line(context)),
      ),
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 2),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(color: T.muted(context),
            fontSize: 9.5, letterSpacing: 1.2)),
        TextField(
          controller: c, enabled: enabled,
          keyboardType: TextInputType.numberWithOptions(decimal: decimal),
          inputFormatters: [
            FilteringTextInputFormatter.allow(decimal ? RegExp(r'[0-9\.]') : RegExp(r'[0-9]')),
          ],
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
              fontFamily: 'monospace'),
          decoration: const InputDecoration(
            isDense: true, border: InputBorder.none,
            enabledBorder: InputBorder.none, focusedBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(vertical: 2),
          ),
        ),
      ]),
    );
  }

  Widget _bigKv(String k, String v) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.2),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(k, style: TextStyle(color: T.muted(context), fontSize: 9, letterSpacing: 1.2)),
      Text(v, style: const TextStyle(fontSize: 16,
          fontWeight: FontWeight.w700, fontFamily: 'monospace')),
    ]),
  );

  Widget _smallKv(String k, String v, {bool ellipsis = false}) => Row(
    mainAxisSize: MainAxisSize.min, children: [
    Text('$k: ', style: TextStyle(color: T.muted(context), fontSize: 10)),
    Flexible(child: Text(v, style: const TextStyle(fontFamily: 'monospace',
            fontSize: 11, fontWeight: FontWeight.w600),
        overflow: ellipsis ? TextOverflow.ellipsis : TextOverflow.clip)),
  ]);

  String _hms(dynamic h) {
    if (h == null) return '—';
    final hours = (h as num).toDouble();
    final hh = hours.floor();
    final mm = ((hours - hh) * 60).floor();
    final ss = (((hours - hh) * 60 - mm) * 60);
    return '${hh.toString().padLeft(2,'0')}:${mm.toString().padLeft(2,'0')}:${ss.toStringAsFixed(0).padLeft(2,'0')}';
  }
  String _dms(dynamic d) {
    if (d == null) return '—';
    final deg = (d as num).toDouble();
    final sign = deg < 0 ? '-' : '+';
    final a = deg.abs();
    final dd = a.floor();
    final mm = ((a - dd) * 60).floor();
    final ss = (((a - dd) * 60 - mm) * 60);
    return '$sign${dd.toString().padLeft(2,'0')}:${mm.toString().padLeft(2,'0')}:${ss.toStringAsFixed(0).padLeft(2,'0')}';
  }
}


class _TargetPlotPainter extends CustomPainter {
  final double? dRa, dDec;
  final List<Map<String, dynamic>> history;
  final Color okColor, warnColor, errColor, mutedColor, textColor, accentColor;
  _TargetPlotPainter({
    this.dRa, this.dDec, required this.history,
    required this.okColor, required this.warnColor, required this.errColor,
    required this.mutedColor, required this.textColor, required this.accentColor,
  });

  @override
  void paint(Canvas c, Size s) {
    final cx = s.width / 2, cy = s.height / 2;
    final r = math.min(s.width, s.height) * 0.45;
    const maxArcsec = 200.0;
    final scale = r / maxArcsec;

    final ringPaint = Paint()..style = PaintingStyle.fill;
    ringPaint.color = errColor.withValues(alpha: 0.18);
    c.drawCircle(Offset(cx, cy), 150 * scale, ringPaint);
    ringPaint.color = warnColor.withValues(alpha: 0.25);
    c.drawCircle(Offset(cx, cy), 100 * scale, ringPaint);
    ringPaint.color = okColor.withValues(alpha: 0.30);
    c.drawCircle(Offset(cx, cy), 50 * scale, ringPaint);

    final ringStroke = Paint()..style = PaintingStyle.stroke
      ..strokeWidth = 0.8..color = mutedColor.withValues(alpha: 0.4);
    c.drawCircle(Offset(cx, cy), 50 * scale, ringStroke);
    c.drawCircle(Offset(cx, cy), 100 * scale, ringStroke);
    c.drawCircle(Offset(cx, cy), 150 * scale, ringStroke);

    final axis = Paint()..color = mutedColor.withValues(alpha: 0.5)..strokeWidth = 0.5;
    c.drawLine(Offset(cx - r, cy), Offset(cx + r, cy), axis);
    c.drawLine(Offset(cx, cy - r), Offset(cx, cy + r), axis);

    final histPaint = Paint()..color = mutedColor.withValues(alpha: 0.5);
    for (final h in history.skip(1)) {
      final x = (h['d_ra'] as num?)?.toDouble();
      final y = (h['d_dec'] as num?)?.toDouble();
      if (x == null || y == null) continue;
      c.drawCircle(Offset(cx + x * scale, cy - y * scale), 3.5, histPaint);
    }

    if (dRa != null && dDec != null) {
      final dot = Paint()..color = accentColor;
      c.drawCircle(Offset(cx + dRa! * scale, cy - dDec! * scale), 6, dot);
      final cross = Paint()..color = accentColor..strokeWidth = 1.5;
      final px = cx + dRa! * scale;
      final py = cy - dDec! * scale;
      c.drawLine(Offset(px - 10, py), Offset(px + 10, py), cross);
      c.drawLine(Offset(px, py - 10), Offset(px, py + 10), cross);
    }
  }

  @override
  bool shouldRepaint(covariant _TargetPlotPainter old) =>
      old.dRa != dRa || old.dDec != dDec || old.history.length != history.length;
}
