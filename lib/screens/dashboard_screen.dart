import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_version.dart';
import '../i18n/strings.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/ekos_master_toggle.dart';
import '../widgets/launch_apps_card.dart';
import 'connections_screen.dart';
import 'live_view_screen.dart';
import 'shell_screen.dart';

/// Dashboard. v0.2.34: convertita a StatefulWidget per avere un tick
/// periodico (2s) che ricalcola le porzioni time-based dei tile
/// (es. badge "live" del GUIDE che si spegne dopo 5s di silenzio PHD2).
/// AppState resta la fonte di verità, ma quando PHD2 smette di mandare
/// eventi non arrivano notifyListeners e la UI rimarrebbe ferma.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Timer? _tick;
  // v0.2.37: stato live della sequenza Ekos Capture (per il contatore frame).
  // Polling separato ogni 3s di /api/capture/ekos_status.
  Timer? _ekosPoll;
  Map<String, dynamic>? _ekosCap;
  // v0.2.44: spazio disco del Pi (cambia lentamente → poll ogni 30s).
  Timer? _diskPoll;
  Map<String, dynamic>? _disk;
  // v0.2.58: backend guida ('internal'|'phd2'|null) + stato guider interno,
  // per rietichettare il tile GUIDE della home ed evitare confusione con PHD2.
  String? _guideBackend;
  Map<String, dynamic>? _ekosGuide;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) setState(() {});
    });
    _ekosPoll = Timer.periodic(const Duration(seconds: 3), (_) => _refreshEkosCap());
    _refreshEkosCap();
    _diskPoll = Timer.periodic(const Duration(seconds: 30), (_) => _refreshDisk());
    _refreshDisk();
    // v0.2.55: se c'è un frame sul bridge (meta presente) ma non abbiamo
    // ancora il JPEG (es. arrivato mentre eravamo in background / prima
    // dell'apertura), scaricalo via REST per popolare subito il monitor.
    Future.microtask(() {
      final s = context.read<AppState>();
      if (s.lastFrameJpeg == null && s.lastFrameMeta.isNotEmpty) s.fetchLastFrame();
    });
  }

  Future<void> _refreshEkosCap() async {
    final s = context.read<AppState>();
    if (s.api == null) return;
    try {
      final st = await s.api!.captureEkosStatus();
      if (mounted) setState(() => _ekosCap = st);
    } catch (_) {
      // silenzioso: se Ekos non è raggiungibile lasciamo l'ultimo valore
    }
    // v0.2.58: rileva il guider attivo; se interno, prendi anche il suo stato
    try {
      final b = await s.api!.guideBackend();
      final backend = b['backend'] as String?;
      Map<String, dynamic>? eg;
      if (backend == 'internal') {
        eg = await s.api!.guideEkosStatus();
      }
      if (mounted) setState(() { _guideBackend = backend; _ekosGuide = eg; });
    } catch (_) {}
  }

  Future<void> _refreshDisk() async {
    final s = context.read<AppState>();
    if (s.api == null) return;
    try {
      final d = await s.api!.filesDiskUsage();
      if (mounted) setState(() => _disk = d);
    } catch (_) {}
  }

  @override
  void dispose() {
    _tick?.cancel();
    _ekosPoll?.cancel();
    _diskPoll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
            icon: const Icon(Icons.menu),
            onPressed: openShellDrawer),
        title: InkWell(
          // Tap sul titolo = quick switch tra bridge salvate.
          // Long-press = apre la lista completa.
          onTap: state.bridges.length > 1 ? () => _showBridgeSwitcher(context, state) : null,
          onLongPress: () {
            Navigator.push(context, MaterialPageRoute(
                builder: (_) => const ConnectionsScreen()));
          },
          child: Row(children: [
            const LiveDot(),
            const SizedBox(width: 10),
            Flexible(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Dashboard'.tr(context),
                    overflow: TextOverflow.ellipsis),
                if (state.activeBridge != null) Text(
                  state.bridges.length > 1
                      ? '${state.activeBridge!.name} ▾'  // hint cliccabile
                      : state.activeBridge!.name,
                  style: TextStyle(color: T.muted(context), fontSize: 11,
                      fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            )),
          ]),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: () async {
              final ok = await state.refreshSnapshot();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(ok ? 'Snapshot aggiornato'.tr(context) : 'Refresh fallito'.tr(context)),
                  duration: const Duration(seconds: 2),
                ));
              }
            },
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Badge versione app: SEMPRE allineato all'APK installato.
                  // La costante kAppVersion (lib/app_version.dart) deve
                  // essere bumpata ad ogni release insieme a pubspec.yaml.
                  Text('v$kAppVersion',
                      style: TextStyle(color: T.accent(context),
                          fontSize: 11, fontWeight: FontWeight.w700,
                          fontFamily: 'monospace')),
                  Text('${state.devices.length} dev',
                      style: TextStyle(color: T.muted(context), fontSize: 10)),
                ],
              ),
            ),
          ),
        ],
      ),
      // v0.2.44/0.2.45: sfondo a tema dietro al contenuto (deepSpace statico,
      // interstellar/starTrek animati). No-op sui temi non scenici.
      body: StarfieldBackground(
        mode: state.themeMode,
        child: RefreshIndicator(
        onRefresh: () async {
          await state.refreshSnapshot();
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
          children: [
            // v0.2.44: striscia health aggregato del sistema
            _systemHealth(context, state),
            const SizedBox(height: 10),
            // Lancio GUI app sul desktop del RPi (KStars/Ekos, PHD2).
            // Le finestre appaiono sul monitor fisico del RPi.
            // Sta SOPRA il toggle master perche' l'ordine d'uso reale e':
            // prima avvii i programmi, poi attivi il sistema.
            const LaunchAppsCard(),
            const SizedBox(height: 8),
            // Pulsante master Attiva/Disattiva — clone del quadratino
            // Start/Stop Ekos del pannello Setup. Verde=tutto su, rosso=tutto giù.
            const EkosMasterToggle(),
            const SizedBox(height: 12),
            _connectionBanner(context, state),
            const SizedBox(height: 10),
            _targetCard(context, state),
            const SizedBox(height: 12),
            _lastFrame(context, state),
            const SizedBox(height: 12),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.7,
              children: [
                _mountCard(context, state),
                _cameraCard(context, state),
                _guideCard(context, state),
                _focuserCard(context, state),
              ],
            ),
            SectionLabel('Sequenza in corso'.tr(context)),
            _sequenceProgress(context, state),
            SectionLabel('Telemetria osservatorio'.tr(context)),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.6,
              children: [
                _weatherCard(context, state),
                _domeCard(context, state),
              ],
            ),
            const SizedBox(height: 8),
            _diskCard(context, state),
            if (state.messages.isNotEmpty) ...[
              SectionLabel('Ultimi messaggi'.tr(context)),
              ...state.messages.reversed.take(3).map((m) => _msgRow(context, m)),
            ],
          ],
        ),
      ),
      ),
    );
  }

  /// v0.2.44: card spazio disco del Pi + stima frame rimanenti.
  /// Stima: free_bytes / dimensione media frame (dai file recenti, fallback 50MB).
  /// Avvisa in giallo sotto 10GB liberi, rosso sotto 3GB.
  Widget _diskCard(BuildContext c, AppState s) {
    final d = _disk;
    final free = (d?['free_bytes'] as num?)?.toDouble();
    final total = (d?['total_bytes'] as num?)?.toDouble();
    final imgBytes = (d?['images_dir_bytes'] as num?)?.toDouble() ?? 0;
    final imgCount = (d?['images_files_count'] as num?)?.toInt() ?? 0;
    const gb = 1024 * 1024 * 1024;

    // dimensione media frame: da images_dir se ho file, fallback 50MB
    final avgFrame = imgCount > 0 ? (imgBytes / imgCount) : (50.0 * 1024 * 1024);
    final framesLeft = free != null ? (free / avgFrame).floor() : null;

    final freeGb = free != null ? free / gb : null;
    final usedFrac = (free != null && total != null && total > 0)
        ? (1 - free / total).clamp(0.0, 1.0) : 0.0;

    final Color col = freeGb == null ? T.muted(c)
        : (freeGb < 3 ? T.err(c) : (freeGb < 10 ? T.warn(c) : T.ok(c)));

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: T.panel(c),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: T.line(c)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.storage, size: 15, color: T.muted(c)),
          const SizedBox(width: 6),
          Text('DISCO RPi'.tr(c), style: TextStyle(
              color: T.muted(c), fontSize: 10.5, letterSpacing: 1.2)),
          const Spacer(),
          Text(freeGb == null ? '—' : '${freeGb.toStringAsFixed(1)} GB ${'liberi'.tr(c)}',
              style: TextStyle(color: col, fontSize: 13, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: usedFrac, minHeight: 6,
            backgroundColor: T.line(c), color: col,
          ),
        ),
        const SizedBox(height: 6),
        Text(framesLeft == null
            ? 'spazio disco non disponibile'.tr(c)
            : '~$framesLeft ${'frame rimanenti'.tr(c)} (${imgCount} ${'fatti'.tr(c)})',
            style: TextStyle(color: T.muted(c), fontSize: 11)),
      ]),
    );
  }

  /// v0.2.44: striscia di health aggregato — un colpo d'occhio sullo stato
  /// del sistema (INDI, PHD2, frame stream, devices). Verde = tutto ok,
  /// giallo = avvisi. Aggrega solo dati già presenti in AppState (nessuna
  /// chiamata extra). Il disco viene aggiunto in fase C.
  Widget _systemHealth(BuildContext c, AppState s) {
    final checks = <(String, bool, bool)>[ // (label, ok, isWarn-not-err)
      ('INDI', s.indiConn == 'connected', false),
      ('PHD2', s.phd2Conn == 'connected', true),
      ('Stream', s.wsFramesLabel == 'connected', true),
      ('Device', s.devices.isNotEmpty, false),
    ];
    final problems = checks.where((e) => !e.$2).toList();
    final allOk = problems.isEmpty;
    final hasErr = problems.any((e) => !e.$3); // problema "duro" (INDI/Device)
    final col = allOk ? T.ok(c) : (hasErr ? T.err(c) : T.warn(c));
    final title = allOk
        ? 'Sistema operativo'.tr(c)
        : '${problems.length} ${problems.length == 1 ? "avviso".tr(c) : "avvisi".tr(c)}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: col.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: col.withValues(alpha: 0.4)),
      ),
      child: Row(children: [
        Icon(allOk ? Icons.check_circle : Icons.warning_amber_rounded,
            color: col, size: 18),
        const SizedBox(width: 8),
        Text(title, style: TextStyle(color: col, fontWeight: FontWeight.w700, fontSize: 13)),
        const Spacer(),
        // mini-indicatori per ciascun check
        ...checks.map((e) => Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Row(children: [
            Container(width: 7, height: 7, decoration: BoxDecoration(
                color: e.$2 ? T.ok(c) : (e.$3 ? T.warn(c) : T.err(c)),
                shape: BoxShape.circle)),
            const SizedBox(width: 3),
            Text(e.$1, style: TextStyle(color: T.muted(c), fontSize: 10)),
          ]),
        )),
      ]),
    );
  }

  /// Bottom-sheet di quick-switch tra bridge salvate. Apre toccando il
  /// nome della bridge nell'AppBar (se sono >= 2 salvate).
  void _showBridgeSwitcher(BuildContext context, AppState s) {
    showModalBottomSheet(
      context: context,
      backgroundColor: T.panel(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(child: Column(
          mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 6),
        Container(
          width: 36, height: 4,
          decoration: BoxDecoration(
            color: T.muted(context).withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Icon(Icons.cloud_outlined, size: 16, color: T.muted(context)),
            const SizedBox(width: 8),
            Text('Bridge salvate'.tr(context).toUpperCase(),
                style: TextStyle(color: T.muted(context),
                    fontSize: 10, letterSpacing: 1.4,
                    fontWeight: FontWeight.w700)),
            const Spacer(),
            TextButton.icon(
              icon: const Icon(Icons.settings, size: 16),
              label: Text('Gestisci'.tr(context),
                  style: const TextStyle(fontSize: 11)),
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.push(context, MaterialPageRoute(
                    builder: (_) => const ConnectionsScreen()));
              },
            ),
          ]),
        ),
        const Divider(height: 1),
        for (final b in s.bridges) ListTile(
          dense: true,
          leading: Icon(
            s.activeBridgeId == b.id
                ? (s.api != null ? Icons.cloud_done : Icons.cloud_outlined)
                : Icons.cloud,
            color: s.activeBridgeId == b.id
                ? (s.api != null ? T.ok(context) : T.accent(context))
                : T.muted(context),
            size: 22,
          ),
          title: Text(b.name,
              style: TextStyle(
                  fontWeight: s.activeBridgeId == b.id
                      ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 14)),
          subtitle: Text('${b.host}:${b.port}',
              style: TextStyle(color: T.muted(context),
                  fontSize: 11, fontFamily: 'monospace')),
          trailing: s.activeBridgeId == b.id
              ? Icon(Icons.check_circle, color: T.ok(context), size: 18)
              : null,
          onTap: s.activeBridgeId == b.id ? null : () async {
            Navigator.pop(ctx);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('${'Switch a '.tr(context)}${b.name}…'),
              duration: const Duration(seconds: 2),
            ));
            final ok = await s.switchTo(b.id);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(ok
                    ? '${'Connesso a '.tr(context)}${b.name}'
                    : '${'Switch fallito: '.tr(context)}${s.lastConnectError ?? "—"}'),
                backgroundColor: ok ? null : T.err(context),
              ));
            }
          },
        ),
        const SizedBox(height: 8),
      ])),
    );
  }

  Widget _connectionBanner(BuildContext c, AppState s) {
    Color dot(String state) {
      switch (state) {
        case 'connected': return T.ok(c);
        case 'reconnecting':
        case 'connecting':
        case 'pinging':
          return T.warn(c);
        default: return T.err(c);
      }
    }
    Widget pill(String label, String state) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 7, height: 7, decoration: BoxDecoration(color: dot(state), shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text('$label: ', style: TextStyle(color: T.muted(c), fontSize: 10.5)),
        Text(state, style: TextStyle(color: dot(state), fontSize: 10.5, fontWeight: FontWeight.w600)),
      ],
    );

    final allOk = s.indiConn == 'connected' && s.wsStateLabel == 'connected';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: T.panel(c),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: allOk ? T.ok(c).withValues(alpha: 0.3) : T.warn(c).withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 14, runSpacing: 4,
            children: [
              pill('INDI', s.indiConn),
              pill('PHD2', s.phd2Conn),
              pill('WS state', s.wsStateLabel),
              pill('WS frames', s.wsFramesLabel),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                'WS events: ${s.wsEventsReceived}',
                style: TextStyle(color: T.muted(c), fontSize: 10, fontFamily: 'monospace'),
              ),
              const SizedBox(width: 12),
              if (s.lastWsEventType != null)
                Text(
                  'last: ${s.lastWsEventType}',
                  style: TextStyle(color: T.muted(c), fontSize: 10, fontFamily: 'monospace'),
                ),
              const Spacer(),
              if (s.snapshotInProgress)
                Text(
                  'syncing ${s.properties.length}/${s.wsExpectedProperties}…',
                  style: TextStyle(color: T.warn(c), fontSize: 10, fontFamily: 'monospace'),
                )
              else
                Text(
                  '${s.properties.length} props',
                  style: TextStyle(color: T.muted(c), fontSize: 10, fontFamily: 'monospace'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _targetCard(BuildContext c, AppState s) {
    final m = s.mountDevice();
    if (m == null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: T.panel(c),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: T.line(c)),
        ),
        child: Text('Nessun mount connesso ad Ekos'.tr(c),
            style: TextStyle(color: T.muted(c), fontSize: 13)),
      );
    }
    final coord = s.prop(m, 'EQUATORIAL_EOD_COORD');
    final ra = (propValue(coord, 'RA') as num?)?.toDouble();
    final dec = (propValue(coord, 'DEC') as num?)?.toDouble();
    return TargetCard(
      title: m,
      subtitle: coord?['state'] ?? '',
      rows: [
        MapEntry('RA', ra == null ? '—' : _hms(ra)),
        MapEntry('Dec', dec == null ? '—' : _dms(dec)),
        MapEntry('State', coord?['state'] ?? '—'),
        MapEntry('Group', coord?['group'] ?? '—'),
      ],
    );
  }

  Widget _lastFrame(BuildContext c, AppState s) {
    final hasFrame = s.lastFrameJpeg != null;
    return InkWell(
      onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const LiveViewScreen())),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 200,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: T.line(c)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (hasFrame)
              Image.memory(s.lastFrameJpeg!, fit: BoxFit.cover, gaplessPlayback: true)
            else
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.image_outlined, color: T.muted(c), size: 36),
                    const SizedBox(height: 6),
                    Text('In attesa del primo scatto…'.tr(c), style: TextStyle(color: T.muted(c), fontSize: 12)),
                  ],
                ),
              ),
            if (hasFrame)
              Positioned(
                left: 10, top: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
                  child: Text(
                    [
                      s.lastFrameMeta['filter'],
                      if (s.lastFrameMeta['exposure'] != null) '${s.lastFrameMeta['exposure']}s',
                      s.lastFrameMeta['frame_type'],
                    ].whereType<String>().join(' · '),
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                  ),
                ),
              ),
            if (hasFrame)
              Positioned(
                right: 10, bottom: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
                  child: Text(
                    'HFR ${(s.lastFrameMeta['hfr'] ?? 0).toStringAsFixed(2)} · ★ ${s.lastFrameMeta['stars'] ?? 0}',
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _mountCard(BuildContext c, AppState s) {
    final m = s.mountDevice();
    final track = m == null ? null : s.prop(m, 'TELESCOPE_TRACK_STATE');
    final on = (propValue(track, 'TRACK_ON') == true);
    return StatusCard(
      header: 'MOUNT',
      value: on ? 'Tracking' : 'Idle',
      subtitle: m ?? 'no mount',
      badgeColor: on ? T.ok(c) : T.muted(c),
      badgeText: on ? 'on' : 'off',
    );
  }

  Widget _cameraCard(BuildContext c, AppState s) {
    final cam = s.cameraDevice();
    final temp = cam == null ? null : s.prop(cam, 'CCD_TEMPERATURE');
    final t = (propValue(temp, 'CCD_TEMPERATURE_VALUE') as num?)?.toDouble();
    return StatusCard(
      header: 'CAMERA',
      value: t == null ? '—' : '${t.toStringAsFixed(1)} °C',
      subtitle: cam ?? 'no camera',
      badgeColor: T.accent2(c),
      badgeText: cam != null ? 'on' : null,
    );
  }

  Widget _guideCard(BuildContext c, AppState s) {
    // v0.2.58: se Ekos guida col guider INTERNO, il tile mostra "Guida Interna"
    // (niente riferimenti a PHD2, che sarebbero confusivi).
    if (_guideBackend == 'internal') {
      final eg = _ekosGuide ?? const {};
      final st = eg['state']?.toString() ?? '—';
      final rms = (eg['rms_total'] as num?)?.toDouble();
      final guiding = st.toUpperCase().contains('GUID');
      return StatusCard(
        header: 'GUIDE',
        value: (guiding && rms != null)
            ? '${rms.toStringAsFixed(2)}″'
            : (st == '—' ? 'idle' : st.toLowerCase()),
        subtitle: 'Guida Interna',
        badgeColor: guiding ? T.ok(c) : T.muted(c),
        badgeText: guiding ? 'on' : st.toLowerCase(),
      );
    }
    // v0.2.34 fix: il tile prima leggeva solo `rms_total` e `app_state`,
    // che PHD2 popola solo durante guiding attivo. Risultato: il tile
    // appariva fermo/statico anche quando PHD2 era connesso e in loop.
    //
    // Ora mostriamo:
    //   - stato connessione PHD2 (online/offline)
    //   - app_state real-time (Stopped/Looping/Calibrating/Guiding/Settling…)
    //   - RMS + SNR durante guiding
    //   - badge "LIVE" se l'ultimo evento PHD2 è recente (<5s)
    final live = s.phd2Live;
    final connected = s.phd2Conn == 'connected';
    final st = live['app_state']?.toString() ?? '—';
    final rms = (live['rms_total'] as num?)?.toDouble();
    final snr = (live['snr'] as num?)?.toDouble();
    final lastTs = (live['last_event_ts'] as num?)?.toDouble();
    final nowSec = DateTime.now().millisecondsSinceEpoch / 1000.0;
    final isLive = lastTs != null && (nowSec - lastTs) < 5.0;
    final starLost = live['star_lost'] == true;

    String value;
    if (!connected) {
      value = 'offline';
    } else if (rms != null && st == 'Guiding') {
      value = '${rms.toStringAsFixed(2)}″'
          '${snr != null ? ' · SNR ${snr.toStringAsFixed(0)}' : ''}';
    } else if (st == '—') {
      value = 'idle';
    } else {
      value = st;
    }

    Color badge;
    String badgeText;
    if (!connected) {
      badge = T.muted(c); badgeText = 'off';
    } else if (starLost) {
      badge = T.err(c); badgeText = 'lost';
    } else if (st == 'Guiding') {
      badge = T.ok(c); badgeText = isLive ? 'live' : 'on';
    } else if (st == 'Looping' || st == 'Calibrating' || st == 'Settling') {
      badge = T.warn(c); badgeText = st.toLowerCase();
    } else {
      badge = T.muted(c); badgeText = isLive ? 'live' : st.toLowerCase();
    }

    return StatusCard(
      header: 'GUIDE',
      value: value,
      subtitle: 'PHD2 · ${connected ? st : "—"}',
      badgeColor: badge,
      badgeText: badgeText,
    );
  }

  Widget _focuserCard(BuildContext c, AppState s) {
    final f = s.focuserDevice();
    final pos = f == null ? null : s.prop(f, 'ABS_FOCUS_POSITION');
    final v = propValue(pos, 'FOCUS_ABSOLUTE_POSITION');
    return StatusCard(
      header: 'FOCUS',
      value: v == null ? '—' : '$v',
      subtitle: f ?? 'no focuser',
      badgeColor: T.accent(c),
      badgeText: f != null ? 'idle' : null,
    );
  }

  Widget _sequenceProgress(BuildContext c, AppState s) {
    // Cerca CCD_EXPOSURE per progress dell'esposizione corrente
    final cam = s.cameraDevice();
    final exp = cam == null ? null : s.prop(cam, 'CCD_EXPOSURE');
    final remaining = (propValue(exp, 'CCD_EXPOSURE_VALUE') as num?)?.toDouble();

    // v0.2.37: contatore frame del job Ekos in corso (X/Y frames).
    // job_image_progress = scatti GIA' COMPLETATI; job_image_count = totale.
    // Es. mentre scatta il 30°, ne sono completati 29 → "29/200".
    final done = (_ekosCap?['job_image_progress'] as num?)?.toInt();
    final total = (_ekosCap?['job_image_count'] as num?)?.toInt();
    final activeId = (_ekosCap?['active_job_id'] as num?)?.toInt() ?? -1;
    final jobState = _ekosCap?['job_state']?.toString();
    final hasCounter = done != null && total != null && total > 0 && activeId >= 0;
    final overallRemaining = (_ekosCap?['overall_remaining_seconds'] as num?)?.toInt();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: T.panel(c),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: T.line(c)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Esposizione corrente'.tr(c), style: TextStyle(color: T.text(c), fontWeight: FontWeight.w600, fontSize: 13)),
              Text(
                exp?['state'] ?? '—',
                style: TextStyle(color: exp?['state'] == 'Busy' ? T.accent(c) : T.muted(c), fontSize: 11),
              ),
            ],
          ),
          // v0.2.37: riga contatore frame X/Y (solo se c'è un job attivo)
          if (hasCounter) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(children: [
                  Icon(Icons.collections, size: 14, color: T.accent(c)),
                  const SizedBox(width: 6),
                  Text('FRAMES'.tr(c), style: TextStyle(
                      color: T.muted(c), fontSize: 10.5, letterSpacing: 1.2)),
                ]),
                Text('$done/$total',
                    style: TextStyle(color: T.accent(c), fontSize: 16,
                        fontWeight: FontWeight.w700, fontFamily: 'monospace')),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: (done / total).clamp(0.0, 1.0),
                backgroundColor: T.line(c),
                color: T.accent(c),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 6),
          ] else
            const SizedBox(height: 8),
          // Barra esposizione corrente (indeterminata mentre Busy)
          if (!hasCounter)
            LinearProgressIndicator(
              value: exp?['state'] == 'Busy' ? null : 0.0,
              backgroundColor: T.line(c),
              color: T.accent(c),
              minHeight: 5,
            ),
          if (!hasCounter) const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                remaining == null ? 'idle' : '${remaining.toStringAsFixed(0)}s ${'rimanenti'.tr(c)}',
                style: TextStyle(color: T.muted(c), fontSize: 11),
              ),
              if (hasCounter && overallRemaining != null && overallRemaining > 0)
                Text('${_fmtHms(overallRemaining)} ${'al termine'.tr(c)}',
                    style: TextStyle(color: T.muted(c), fontSize: 11)),
            ],
          ),
          if (hasCounter && jobState != null) Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(jobState,
                style: TextStyle(color: T.muted(c), fontSize: 10.5)),
          ),
        ],
      ),
    );
  }

  /// Formatta secondi in "Xh Ym" o "Ym" per il tempo residuo totale.
  String _fmtHms(int secs) {
    final h = secs ~/ 3600;
    final m = (secs % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  Widget _weatherCard(BuildContext c, AppState s) {
    // Cerca un device con WEATHER_PARAMETERS
    String dev = s.findDeviceByProperty('WEATHER_PARAMETERS') ?? '';
    final wp = dev.isEmpty ? null : s.prop(dev, 'WEATHER_PARAMETERS');
    String value = '—';
    String sub = dev.isEmpty ? 'no weather' : dev;
    if (wp != null) {
      final elements = (wp['elements'] as List? ?? []).cast<Map>();
      final temp = elements.firstWhere((e) => '${e['name']}'.contains('TEMP'),
          orElse: () => <String, dynamic>{});
      final v = temp['value'];
      if (v is num) value = '${v.toStringAsFixed(1)} °C';
    }
    return StatusCard(header: 'WEATHER', value: value, subtitle: sub);
  }

  Widget _domeCard(BuildContext c, AppState s) {
    String dev = s.findDeviceByProperty('DOME_SHUTTER') ?? '';
    final p = dev.isEmpty ? null : s.prop(dev, 'DOME_SHUTTER');
    bool open = false;
    for (final e in (p?['elements'] as List? ?? [])) {
      if (e['name'] == 'SHUTTER_OPEN' && e['value'] == true) open = true;
    }
    return StatusCard(
      header: 'DOME',
      value: dev.isEmpty ? '—' : (open ? 'Aperto'.tr(c) : 'Chiuso'.tr(c)),
      subtitle: dev.isEmpty ? 'no dome' : dev,
      badgeColor: open ? T.ok(c) : T.warn(c),
      badgeText: open ? 'open' : 'close',
    );
  }

  Widget _msgRow(BuildContext c, Map<String, dynamic> m) {
    final ts = (m['ts'] as num?)?.toDouble();
    final time = ts != null ? DateTime.fromMillisecondsSinceEpoch((ts * 1000).toInt()) : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(time == null ? '' : '${time.hour.toString().padLeft(2,'0')}:${time.minute.toString().padLeft(2,'0')}',
              style: TextStyle(color: T.muted(c), fontSize: 10, fontFamily: 'monospace')),
          const SizedBox(width: 8),
          Expanded(
            child: Text('${m['device'] ?? ''} ${m['message'] ?? ''}'.trim(),
                style: TextStyle(color: T.text(c), fontSize: 11)),
          ),
        ],
      ),
    );
  }

  String _hms(double hours) {
    final h = hours.floor();
    final m = ((hours - h) * 60).floor();
    final s = (((hours - h) * 60 - m) * 60).round();
    return '${h.toString().padLeft(2,'0')}h ${m.toString().padLeft(2,'0')}m ${s.toString().padLeft(2,'0')}s';
  }

  String _dms(double deg) {
    final sign = deg < 0 ? '-' : '+';
    final a = deg.abs();
    final d = a.floor();
    final m = ((a - d) * 60).floor();
    final s = (((a - d) * 60 - m) * 60).round();
    return '$sign${d.toString().padLeft(2,'0')}° ${m.toString().padLeft(2,'0')}′ ${s.toString().padLeft(2,'0')}″';
  }
}
