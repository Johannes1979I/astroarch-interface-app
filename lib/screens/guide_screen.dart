import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../api/api_client.dart';
import '../i18n/strings.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/responsive.dart';
import 'shell_screen.dart';
import 'guide_ekos_view.dart';

class GuideScreen extends StatefulWidget {
  const GuideScreen({super.key});
  @override
  State<GuideScreen> createState() => _GuideScreenState();
}

class _GuideScreenState extends State<GuideScreen> {
  // v0.2.57: quale guider usa Ekos ('internal' | 'phd2' | 'linguider' | null).
  // Rilevato al primo build; se 'internal' mostriamo la vista dedicata.
  String? _backend;

  @override
  void initState() {
    super.initState();
    _detectBackend();
  }

  Future<void> _detectBackend() async {
    final s = context.read<AppState>();
    if (s.api == null) return;
    try {
      final r = await s.api!.guideBackend();
      if (mounted) setState(() => _backend = r['backend'] as String?);
    } catch (_) {
      // bridge senza endpoint /backend (vecchio) o errore → fallback PHD2.
      if (mounted) setState(() => _backend = null);
    }
  }

  Future<void> _safe(Future Function() fn, String msg) async {
    try { await fn(); if (mounted) showSnack(context, msg); }
    on ApiException catch (e) {
      if (mounted) showSnack(context,
          '${'Errore: '.tr(context)}${_extractDetail(e.body)}', error: true);
    }
    catch (e) {
      if (mounted) showSnack(context, '${'Errore: '.tr(context)}$e', error: true);
    }
  }

  /// Estrae il campo "detail" dal body JSON di FastAPI, fallback al body.
  String _extractDetail(String body) {
    try {
      final j = jsonDecode(body);
      if (j is Map && j['detail'] != null) return j['detail'].toString();
    } catch (_) {}
    return body;
  }

  @override
  Widget build(BuildContext context) {
    // v0.2.57: se Ekos guida col guider INTERNO, vista dedicata; altrimenti
    // (PHD2, o backend non ancora rilevato) la vista PHD2 storica.
    if (_backend == 'internal') {
      return EkosGuideView(onReload: _detectBackend);
    }
    final s = context.watch<AppState>();
    final live = s.phd2Live;
    final connected = s.phd2Conn == 'connected';
    final st = live['app_state']?.toString() ?? 'Stopped';
    final rms = (live['rms_total'] as num?)?.toDouble();
    final raRms = (live['rms_ra'] as num?)?.toDouble();
    final decRms = (live['rms_dec'] as num?)?.toDouble();
    final snr = (live['snr'] as num?)?.toDouble();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
            icon: const Icon(Icons.menu),
            onPressed: openShellDrawer),
        title: Row(children: [
        const LiveDot(),
        const SizedBox(width: 10),
        Text('${'Guide'.tr(context)} · PHD2'),
        const Spacer(),
        Text(connected ? st : 'offline',
            style: TextStyle(color: connected ? T.ok(context) : T.muted(context), fontSize: 12)),
      ])),
      body: !connected
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'PHD2 non connesso al bridge.\nAvvia PHD2 sul RPi e abilita Server (porta 4400).'.tr(context),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: T.muted(context)),
                ),
              ),
            )
          : AdaptiveListView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 80),
              children: [
                // Vista stella di guida — il riquadro con crosshair che si
                // vede dentro PHD2. Si aggiorna automaticamente.
                const _GuideStarImageCard(),
                const SizedBox(height: 8),
                // v0.2.34: frame completo PHD2 — identico a quello che vedi
                // nella finestra principale di PHD2 sul desktop del RPi.
                const _GuidePhd2FullFrameCard(),
                const SizedBox(height: 10),
                // Altezza secondo il contenuto (non piu' childAspectRatio 1.7):
                // 2 colonne su telefono, fino a 4 su schermo largo.
                AdaptiveGrid(
                  minTileWidth: 150,
                  maxColumns: 4,
                  children: [
                    StatusCard(header: 'RMS TOTAL'.tr(context),
                        value: rms == null ? '—' : '${rms.toStringAsFixed(2)}″',
                        subtitle: 'target < 1.0″'),
                    StatusCard(header: 'SNR',
                        value: snr == null ? '—' : snr.toStringAsFixed(0),
                        subtitle: 'star quality'.tr(context)),
                    StatusCard(header: 'RA RMS'.tr(context),
                        value: raRms == null ? '—' : '${raRms.toStringAsFixed(2)}″'),
                    StatusCard(header: 'DEC RMS'.tr(context),
                        value: decRms == null ? '—' : '${decRms.toStringAsFixed(2)}″'),
                  ],
                ),
                SectionLabel('Errore inseguimento'.tr(context)),
                _chart(s),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: PrimaryButton(label: 'START', icon: Icons.play_arrow,
                      onPressed: () => _safe(() => s.api!.guideStart(), 'Guide started'.tr(context)))),
                  const SizedBox(width: 8),
                  Expanded(child: GhostButton(label: 'STOP', icon: Icons.stop,
                      onPressed: () => _safe(() => s.api!.guideStop(), 'Stopped'.tr(context)))),
                ]),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(child: GhostButton(label: 'DITHER', icon: Icons.scatter_plot,
                      onPressed: () => _safe(() => s.api!.guideDither(amount: 3), 'Dither 3px'.tr(context)))),
                  const SizedBox(width: 8),
                  Expanded(child: GhostButton(label: 'FIND STAR',
                      onPressed: () => _safe(() => s.api!.guideFindStar(), 'Find star'.tr(context)))),
                ]),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(child: GhostButton(label: 'CALIBRATE',
                      icon: Icons.adjust,
                      onPressed: () => _safe(() => s.api!.guideCalibrate(),
                          'Calibration avviata (richiede ~2 min)'.tr(context)))),
                  const SizedBox(width: 8),
                  Expanded(child: GhostButton(label: 'CLEAR CAL',
                      onPressed: () => _safe(() => s.api!.guideClearCalibration(), 'Cal cleared'.tr(context)))),
                ]),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(child: PrimaryButton(label: 'CONNETTI PHD2'.tr(context), icon: Icons.usb,
                      onPressed: () => _safe(() => s.api!.guideConnectEquipment(),
                          'Connessione periferiche PHD2…'.tr(context)))),
                ]),
                SectionLabel('Equipaggiamento PHD2'.tr(context)),
                _equipmentCard(s),
                SectionLabel('Dither config'.tr(context)),
                const _DitherConfigCard(),
              ],
            ),
    );
  }

  Widget _equipmentCard(AppState s) {
    final live = s.phd2Live;
    final pixelScale = (live['pixel_scale'] as num?)?.toDouble();
    final ver = live['version'];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: T.panel(context), borderRadius: BorderRadius.circular(10),
        border: Border.all(color: T.line(context)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.info_outline, color: T.muted(context), size: 14),
          const SizedBox(width: 6),
          Text('PHD2 ${ver ?? "—"}', style: TextStyle(color: T.muted(context), fontSize: 11)),
          const Spacer(),
          if (pixelScale != null) Text('${pixelScale.toStringAsFixed(2)} ″/px',
              style: TextStyle(color: T.muted(context), fontSize: 11, fontFamily: 'monospace')),
        ]),
        if (live['calibrated'] == true) Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('● ${'Calibrated'.tr(context)}', style: TextStyle(color: T.ok(context), fontSize: 11)),
        ),
        if (live['settling'] == true) Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text('● ${'Settling…'.tr(context)}', style: TextStyle(color: T.warn(context), fontSize: 11)),
        ),
      ]),
    );
  }

  /// Grafico di inseguimento stile PHD2: due linee (RA in blu, DEC in
  /// rosso) con asse Y in arcsec SIGNATO ± e linea di mezzeria a 0.
  /// I valori plottati sono `ra_raw` / `dec_raw` (= RADistanceRaw /
  /// DECDistanceRaw che PHD2 manda ad ogni `GuideStep`), che è la
  /// deflezione istantanea per-frame. NON sono i valori RMS aggregati.
  Widget _chart(AppState s) {
    // Filtra solo i punti che hanno effettivamente ra_raw/dec_raw
    // (escludendo gli eventi di stato senza deflezione, es. StarLost).
    final pts = s.phd2History.where((p) =>
        p['ra_raw'] != null || p['dec_raw'] != null).toList();

    if (pts.isEmpty) {
      return Container(
        height: 160,
        decoration: BoxDecoration(
          color: T.panel(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: T.line(context)),
        ),
        child: Center(child: Text(
            'In attesa di dati guide…\n'
            'Avvia il guiding in PHD2 per vedere il grafico.'.tr(context),
            textAlign: TextAlign.center,
            style: TextStyle(color: T.muted(context), fontSize: 12))),
      );
    }

    final raSpots = <FlSpot>[];
    final decSpots = <FlSpot>[];
    double absMax = 1.0;
    for (var i = 0; i < pts.length; i++) {
      final ra = (pts[i]['ra_raw'] as num?)?.toDouble() ?? 0;
      final dec = (pts[i]['dec_raw'] as num?)?.toDouble() ?? 0;
      raSpots.add(FlSpot(i.toDouble(), ra));
      decSpots.add(FlSpot(i.toDouble(), dec));
      final a = ra.abs() > dec.abs() ? ra.abs() : dec.abs();
      if (a > absMax) absMax = a;
    }
    // Asse Y simmetrico ±absMax (arrotondato in alto a multipli di 0.5″,
    // minimo ±1.0″ così il grafico non oscilla per micro-variazioni).
    final yScale = (absMax <= 1.0) ? 1.0
        : (absMax <= 2.0) ? 2.0
        : (absMax <= 4.0) ? 4.0
        : (absMax + 0.5).ceilToDouble();

    return Container(
      height: 180,
      padding: const EdgeInsets.fromLTRB(8, 10, 14, 6),
      decoration: BoxDecoration(
        color: T.panel(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: T.line(context)),
      ),
      child: Column(children: [
        // Legenda + scala
        Row(children: [
          Container(width: 10, height: 2, color: T.accent(context)),
          const SizedBox(width: 4),
          Text('RA', style: TextStyle(color: T.accent(context),
              fontSize: 10, fontWeight: FontWeight.w700)),
          const SizedBox(width: 12),
          Container(width: 10, height: 2, color: T.accent2(context)),
          const SizedBox(width: 4),
          Text('DEC', style: TextStyle(color: T.accent2(context),
              fontSize: 10, fontWeight: FontWeight.w700)),
          const Spacer(),
          Text('Y: ±${yScale.toStringAsFixed(1)}″ · ${pts.length} pts',
              style: TextStyle(color: T.muted(context), fontSize: 10,
                  fontFamily: 'monospace')),
        ]),
        const SizedBox(height: 4),
        Expanded(child: LineChart(
          LineChartData(
            minX: 0, maxX: (raSpots.length - 1).toDouble().clamp(1.0, double.infinity),
            minY: -yScale, maxY: yScale,
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: yScale / 2.0,
              getDrawingHorizontalLine: (v) => FlLine(
                color: v.abs() < 1e-6
                    ? T.muted(context).withValues(alpha: 0.6)
                    : T.line(context).withValues(alpha: 0.4),
                strokeWidth: v.abs() < 1e-6 ? 1.0 : 0.5,
                dashArray: v.abs() < 1e-6 ? null : [2, 4],
              ),
            ),
            titlesData: FlTitlesData(
              leftTitles: AxisTitles(sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: yScale / 2.0,
                getTitlesWidget: (v, _) => Text(
                    v == 0 ? '0' : v.toStringAsFixed(1),
                    style: TextStyle(color: T.muted(context), fontSize: 9,
                        fontFamily: 'monospace')),
              )),
              rightTitles: const AxisTitles(),
              topTitles: const AxisTitles(),
              bottomTitles: const AxisTitles(),
            ),
            borderData: FlBorderData(show: false),
            lineTouchData: const LineTouchData(enabled: false),
            lineBarsData: [
              LineChartBarData(
                spots: raSpots,
                isCurved: false,  // PHD2 usa linee dritte, non interpolate
                color: T.accent(context),
                barWidth: 1.3,
                dotData: const FlDotData(show: false),
              ),
              LineChartBarData(
                spots: decSpots,
                isCurved: false,
                color: T.accent2(context),
                barWidth: 1.3,
                dotData: const FlDotData(show: false),
              ),
            ],
          ),
        )),
      ]),
    );
  }
}


/// Widget che mostra il riquadro con la stella di guida intercettato da PHD2.
/// Polling ogni 1500 ms (PHD2 espone una nuova frame ~ogni 1-3s di solito).
/// Se PHD2 non ha ancora una stella selezionata (es. utente non ha fatto
/// "Find Star" / "Calibrate"), mostra placeholder con istruzioni.
class _GuideStarImageCard extends StatefulWidget {
  const _GuideStarImageCard();
  @override
  State<_GuideStarImageCard> createState() => _GuideStarImageCardState();
}

class _GuideStarImageCardState extends State<_GuideStarImageCard> {
  Timer? _timer;
  Uint8List? _png;
  int? _w, _h;
  double? _starX, _starY;
  int? _frame;
  String? _err;
  bool _inflight = false;

  @override
  void initState() {
    super.initState();
    _tick();
    _timer = Timer.periodic(const Duration(milliseconds: 1500), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _tick() async {
    if (_inflight) return; // evita overlap se la rete è lenta
    final s = context.read<AppState>();
    if (s.api == null) return;
    _inflight = true;
    try {
      final j = await s.api!.guideStarImage();
      final b64 = j['png_base64'] as String?;
      if (b64 == null) throw Exception('missing png');
      final bytes = base64.decode(b64);
      if (!mounted) return;
      setState(() {
        _png = bytes;
        _w = (j['width'] as num?)?.toInt();
        _h = (j['height'] as num?)?.toInt();
        _starX = (j['star_x'] as num?)?.toDouble();
        _starY = (j['star_y'] as num?)?.toDouble();
        _frame = (j['frame'] as num?)?.toInt();
        _err = null;
      });
    } on ApiException catch (e) {
      // 409 = PHD2 senza stella selezionata o app_state non compatibile
      if (mounted) setState(() => _err = e.status == 409
          ? 'PHD2: nessuna stella selezionata. Premi FIND STAR.'.tr(context)
          : '${'Errore: '.tr(context)}${_extractDetailLocal(e.body)}');
    } catch (e) {
      if (mounted) setState(() => _err = e.toString());
    } finally {
      _inflight = false;
    }
  }

  String _extractDetailLocal(String body) {
    try {
      final j = jsonDecode(body);
      if (j is Map && j['detail'] != null) return j['detail'].toString();
    } catch (_) {}
    return body;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: T.line(context)),
      ),
      clipBehavior: Clip.antiAlias,
      // Limitata in altezza su schermo largo; il LayoutBuilder interno
      // (crosshair) riceve comunque il riquadro reale.
      child: AdaptivePreview(
        aspectRatio: 1.6,
        child: Stack(fit: StackFit.expand, children: [
          if (_png != null)
            InteractiveViewer(
              minScale: 1, maxScale: 6,
              child: LayoutBuilder(builder: (ctx, constraints) {
                // Disegna il PNG ridimensionato al riquadro mantenendo
                // l'aspect ratio del crop di PHD2. Calcolo scale per
                // posizionare il crosshair sul punto giusto.
                final cw = constraints.maxWidth;
                final ch = constraints.maxHeight;
                final iw = (_w ?? 1).toDouble();
                final ih = (_h ?? 1).toDouble();
                final scale = (cw / iw < ch / ih) ? cw / iw : ch / ih;
                final dispW = iw * scale, dispH = ih * scale;
                final offX = (cw - dispW) / 2, offY = (ch - dispH) / 2;
                final crossX = _starX == null
                    ? null : offX + _starX! * scale;
                final crossY = _starY == null
                    ? null : offY + _starY! * scale;
                return Stack(children: [
                  Center(child: Image.memory(_png!,
                      fit: BoxFit.contain, gaplessPlayback: true,
                      filterQuality: FilterQuality.medium)),
                  if (crossX != null && crossY != null)
                    Positioned(
                      left: crossX - 22, top: crossY - 22,
                      width: 44, height: 44,
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _CrosshairPainter(color: T.accent(context)),
                        ),
                      ),
                    ),
                ]);
              }),
            )
          else if (_err != null)
            Center(child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                Icon(Icons.search_off, color: T.muted(context), size: 28),
                const SizedBox(height: 8),
                Text(_err!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: T.muted(context), fontSize: 12)),
              ]),
            ))
          else
            const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          // HUD top-left: frame + crop size
          if (_png != null && _w != null && _h != null) Positioned(
            top: 8, left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: Colors.black54,
                  borderRadius: BorderRadius.circular(6)),
              child: Text(
                '★ ${_starX?.toStringAsFixed(1) ?? "—"}, '
                '${_starY?.toStringAsFixed(1) ?? "—"} · '
                '${_w}×$_h · #${_frame ?? "—"}',
                style: const TextStyle(color: Colors.white,
                    fontFamily: 'monospace', fontSize: 9),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// v0.2.34: Mostra il FRAME COMPLETO della camera di guida PHD2 (non solo
/// il crop intorno alla stella). Internamente chiama /api/guide/full_frame
/// che usa PHD2 `save_image` → FITS → auto-stretch → PNG.
///
/// Polling più lento del crop (4s) perché ogni richiesta scrive/legge un
/// FITS dal disco del RPi (costo I/O).
class _GuidePhd2FullFrameCard extends StatefulWidget {
  const _GuidePhd2FullFrameCard();
  @override
  State<_GuidePhd2FullFrameCard> createState() => _GuidePhd2FullFrameCardState();
}

class _GuidePhd2FullFrameCardState extends State<_GuidePhd2FullFrameCard> {
  Timer? _timer;
  Uint8List? _png;
  int? _w, _h;
  String? _err;
  bool _inflight = false;
  bool _enabled = false; // OFF di default — la richiesta è pesante (FITS)

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _toggle() {
    setState(() => _enabled = !_enabled);
    if (_enabled) {
      _tick();
      _timer = Timer.periodic(const Duration(seconds: 4), (_) => _tick());
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  Future<void> _tick() async {
    if (_inflight) return;
    final s = context.read<AppState>();
    if (s.api == null) return;
    _inflight = true;
    try {
      final j = await s.api!.guideFullFrame(maxDim: 1024);
      final b64 = j['png_base64'] as String?;
      if (b64 == null) throw Exception('missing png');
      final bytes = base64.decode(b64);
      if (!mounted) return;
      setState(() {
        _png = bytes;
        _w = (j['width'] as num?)?.toInt();
        _h = (j['height'] as num?)?.toInt();
        _err = null;
      });
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _err = e.status == 409
            ? 'PHD2: camera non in loop. Premi LOOP per attivare il flusso.'.tr(context)
            : '${'Errore: '.tr(context)}${_extractDetailLocalFF(e.body)}');
      }
    } catch (e) {
      if (mounted) setState(() => _err = e.toString());
    } finally {
      _inflight = false;
    }
  }

  String _extractDetailLocalFF(String body) {
    try {
      final j = jsonDecode(body);
      if (j is Map && j['detail'] != null) return j['detail'].toString();
    } catch (_) {}
    return body;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: T.panel(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: T.line(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          onTap: _toggle,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(children: [
              Icon(_enabled ? Icons.videocam : Icons.videocam_off,
                  color: _enabled ? T.ok(context) : T.muted(context), size: 18),
              const SizedBox(width: 8),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Frame completo PHD2'.tr(context),
                      style: TextStyle(color: T.text(context),
                          fontWeight: FontWeight.w600, fontSize: 13)),
                  Text(_enabled
                      ? 'Refresh ogni 4s · via save_image'.tr(context)
                      : 'Tap per attivare (richiede camera in loop)'.tr(context),
                      style: TextStyle(color: T.muted(context), fontSize: 10.5)),
                ],
              )),
              Switch(value: _enabled, onChanged: (_) => _toggle()),
            ]),
          ),
        ),
        if (_enabled) Container(
          color: Colors.black,
          child: AdaptivePreview(
            aspectRatio: (_w != null && _h != null && _w! > 0 && _h! > 0)
                ? _w! / _h! : 1.5,
            child: Stack(fit: StackFit.expand, children: [
              if (_png != null)
                InteractiveViewer(minScale: 1, maxScale: 8,
                    child: Image.memory(_png!, fit: BoxFit.contain,
                        gaplessPlayback: true,
                        filterQuality: FilterQuality.medium))
              else if (_err != null)
                Center(child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(_err!, textAlign: TextAlign.center,
                      style: TextStyle(color: T.muted(context), fontSize: 12)),
                ))
              else
                const Center(child: CircularProgressIndicator(strokeWidth: 2)),
              if (_png != null && _w != null && _h != null) Positioned(
                top: 6, left: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(color: Colors.black54,
                      borderRadius: BorderRadius.circular(6)),
                  child: Text('${_w}×$_h',
                      style: const TextStyle(color: Colors.white,
                          fontFamily: 'monospace', fontSize: 9)),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// v0.2.36: pannello "Dither config".
/// Override dei parametri dither persistiti in AppState e inviati al
/// bridge via /ekos_run come campi top-level (`ditherAmount`,
/// `ditherSettleTime`, `ditherSettlePixels`, `ditherFrequency`,
/// `ditherRaOnly`). Se l'utente lascia "Auto", il valore corrispondente
/// non viene inviato e il bridge usa quello di Ekos (kstarsrc [Guide]).
class _DitherConfigCard extends StatefulWidget {
  const _DitherConfigCard();
  @override
  State<_DitherConfigCard> createState() => _DitherConfigCardState();
}

class _DitherConfigCardState extends State<_DitherConfigCard> {
  Map<String, dynamic>? _ekos; // valori letti da /api/capture/ekos_dither_settings
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadEkosDefaults();
  }

  Future<void> _loadEkosDefaults() async {
    final s = context.read<AppState>();
    if (s.api == null) return;
    setState(() => _loading = true);
    try {
      final r = await s.api!.ekosDitherSettings();
      if (mounted) setState(() => _ekos = r);
    } catch (_) {
      // silent — l'utente vede comunque i propri valori; senza Ekos non
      // popoliamo i fallback ma il pannello funziona lo stesso
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _syncFromEkos() async {
    await _loadEkosDefaults();
    final s = context.read<AppState>();
    if (_ekos != null) {
      s.setDitherConfig(
        amountPx: (_ekos!['amount'] as num?)?.toDouble(),
        settleSec: (_ekos!['settle_time'] as num?)?.toDouble(),
        settlePixels: (_ekos!['settle_pixels'] as num?)?.toDouble(),
        frequency: (_ekos!['frequency'] as num?)?.toInt(),
        raOnly: _ekos!['ra_only'] as bool?,
      );
      if (mounted) showSnack(context, 'Sincronizzato con Ekos'.tr(context));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final ekosAmount = (_ekos?['amount'] as num?)?.toDouble();
    final ekosSettle = (_ekos?['settle_time'] as num?)?.toDouble();
    final ekosFreq = (_ekos?['frequency'] as num?)?.toInt();

    final curAmount = s.ditherAmountPx ?? ekosAmount ?? 3.0;
    final curSettle = s.ditherSettleSec ?? ekosSettle ?? 10.0;
    final curSettlePx = s.ditherSettlePixels ?? 1.5;
    final curFreq = s.ditherFrequency ?? ekosFreq ?? 1;
    final curRaOnly = s.ditherRaOnly ?? false;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: T.panel(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: T.line(context)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.scatter_plot, size: 14, color: T.muted(context)),
          const SizedBox(width: 6),
          Expanded(child: Text(
            'Parametri inviati al bridge ad ogni Avvia Sequenza'.tr(context),
            style: TextStyle(color: T.muted(context), fontSize: 11),
          )),
          if (_loading)
            const SizedBox(width: 14, height: 14,
                child: CircularProgressIndicator(strokeWidth: 2)),
        ]),
        const SizedBox(height: 8),

        // PIXEL DITHER
        _slider(context,
          label: 'Pixel del dither'.tr(context),
          valueLabel: '${curAmount.toStringAsFixed(1)} px',
          subtitle: ekosAmount == null
              ? 'Default Ekos non disponibile'.tr(context)
              : '${'Default Ekos'.tr(context)}: ${ekosAmount.toStringAsFixed(1)} px',
          value: curAmount,
          min: 0.5, max: 15.0, divisions: 29,
          isOverride: s.ditherAmountPx != null,
          onChanged: (v) => s.setDitherConfig(amountPx: v),
          onReset: () => s.setDitherConfig(amountPx: null,
              settleSec: s.ditherSettleSec, settlePixels: s.ditherSettlePixels,
              frequency: s.ditherFrequency, raOnly: s.ditherRaOnly,
              reset: false),
        ),

        // SETTLE TIME
        _slider(context,
          label: 'Tempo di settling minimo'.tr(context),
          valueLabel: '${curSettle.toStringAsFixed(0)} s',
          subtitle: ekosSettle == null
              ? 'Default Ekos non disponibile'.tr(context)
              : '${'Default Ekos'.tr(context)}: ${ekosSettle.toStringAsFixed(0)} s',
          value: curSettle,
          min: 3, max: 120, divisions: 39,
          isOverride: s.ditherSettleSec != null,
          onChanged: (v) => s.setDitherConfig(settleSec: v),
          onReset: () => s.setDitherConfig(settleSec: null),
        ),

        // SETTLE PIXELS (max RMS tollerata)
        _slider(context,
          label: 'Max errore in settling'.tr(context),
          valueLabel: '${curSettlePx.toStringAsFixed(1)} px',
          subtitle: '${'Default'.tr(context)}: 1.5 px',
          value: curSettlePx,
          min: 0.3, max: 5.0, divisions: 47,
          isOverride: s.ditherSettlePixels != null,
          onChanged: (v) => s.setDitherConfig(settlePixels: v),
          onReset: () => s.setDitherConfig(settlePixels: null),
        ),

        // FREQUENCY
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 2),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Dither ogni N scatti'.tr(context),
                  style: TextStyle(color: T.text(context), fontWeight: FontWeight.w600, fontSize: 12)),
              Text(ekosFreq == null
                      ? 'Default Ekos non disponibile'.tr(context)
                      : '${'Default Ekos'.tr(context)}: ogni $ekosFreq',
                  style: TextStyle(color: T.muted(context), fontSize: 11)),
            ])),
            DropdownButton<int>(
              value: curFreq,
              underline: const SizedBox(),
              items: const [
                DropdownMenuItem(value: 1, child: Text('ogni 1')),
                DropdownMenuItem(value: 2, child: Text('ogni 2')),
                DropdownMenuItem(value: 3, child: Text('ogni 3')),
                DropdownMenuItem(value: 5, child: Text('ogni 5')),
                DropdownMenuItem(value: 10, child: Text('ogni 10')),
              ],
              onChanged: (v) {
                if (v != null) s.setDitherConfig(frequency: v);
              },
            ),
            if (s.ditherFrequency != null) IconButton(
              icon: Icon(Icons.refresh, size: 18, color: T.muted(context)),
              tooltip: 'Reset a default Ekos'.tr(context),
              onPressed: () => s.setDitherConfig(frequency: null),
            ),
          ]),
        ),

        // RA ONLY
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text('Solo RA'.tr(context), style: const TextStyle(fontSize: 13)),
          subtitle: Text('Dither solo in ascensione retta'.tr(context),
              style: TextStyle(color: T.muted(context), fontSize: 11)),
          value: curRaOnly,
          onChanged: (v) => s.setDitherConfig(raOnly: v),
        ),

        const SizedBox(height: 4),
        Row(children: [
          Expanded(child: GhostButton(
            label: 'SINCRONIZZA DA EKOS',
            icon: Icons.sync,
            onPressed: _loading ? null : _syncFromEkos,
            small: true,
          )),
          const SizedBox(width: 8),
          Expanded(child: GhostButton(
            label: 'RESET TUTTO',
            icon: Icons.restart_alt,
            small: true,
            onPressed: () => s.setDitherConfig(reset: true),
          )),
        ]),
      ]),
    );
  }

  Widget _slider(BuildContext context, {
    required String label, required String valueLabel, required String subtitle,
    required double value, required double min, required double max,
    required int divisions, required bool isOverride,
    required ValueChanged<double> onChanged,
    required VoidCallback onReset,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(label, style: TextStyle(
              color: T.text(context), fontWeight: FontWeight.w600, fontSize: 12))),
          Text(valueLabel, style: TextStyle(
              color: isOverride ? T.accent(context) : T.muted(context),
              fontWeight: FontWeight.w700, fontSize: 12, fontFamily: 'monospace')),
          if (isOverride) IconButton(
            icon: Icon(Icons.close, size: 14, color: T.muted(context)),
            tooltip: 'Reset a default Ekos'.tr(context),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            onPressed: onReset,
          ),
        ]),
        Text(subtitle, style: TextStyle(color: T.muted(context), fontSize: 10.5)),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2.5,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min, max: max, divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ]),
    );
  }
}

class _CrosshairPainter extends CustomPainter {
  final Color color;
  _CrosshairPainter({required this.color});
  @override
  void paint(Canvas c, Size s) {
    final cx = s.width / 2, cy = s.height / 2;
    final r = s.width * 0.35;
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    // Cerchio centrale
    c.drawCircle(Offset(cx, cy), r, p);
    // Tick orizzontale/verticale
    c.drawLine(Offset(0, cy), Offset(cx - r * 0.5, cy), p);
    c.drawLine(Offset(cx + r * 0.5, cy), Offset(s.width, cy), p);
    c.drawLine(Offset(cx, 0), Offset(cx, cy - r * 0.5), p);
    c.drawLine(Offset(cx, cy + r * 0.5), Offset(cx, s.height), p);
  }
  @override
  bool shouldRepaint(covariant _CrosshairPainter old) => old.color != color;
}
