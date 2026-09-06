import 'dart:async';
import 'dart:convert';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/api_client.dart';
import '../i18n/strings.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'shell_screen.dart';

/// v0.2.58: vista COMPLETA per il GUIDER INTERNO di Ekos (alternativa a PHD2).
/// Mostrata da GuideScreen quando il bridge riporta `backend == 'internal'`.
///
/// Parita' con la vista PHD2 su cio' che il guider interno espone via DBus:
///   - grafico di drift RA/DEC nel tempo (come il grafico principale di PHD2)
///   - RMS RA/DEC/total, deflessione istantanea, camera/guider/esposizione
///   - log di guida
///   - comandi (start/stop/calibrate/dither/loop)
///
/// NB tecnica: i frame della camera di guida NON passano dalla cache BLOB di
/// KStars (niente setBLOBMode via DBus), quindi la star image non e' ancora
/// qui. Arrivera' con un client INDI dedicato nel bridge (iscrizione allo
/// stream BLOB su :7624, per-client → non disturba il guiding di Ekos).
class EkosGuideView extends StatefulWidget {
  final Future<void> Function()? onReload;
  const EkosGuideView({super.key, this.onReload});
  @override
  State<EkosGuideView> createState() => _EkosGuideViewState();
}

class _EkosGuideViewState extends State<EkosGuideView> {
  Timer? _timer;
  Map<String, dynamic>? _status;
  bool _inflight = false;

  /// Storico dei delta (arcsec) per il grafico: {ra, dec}. Cap a 120 punti
  /// (~4 min a 2s/campione), come la finestra scorrevole di PHD2.
  final List<Map<String, double>> _history = [];
  static const int _maxPoints = 120;

  @override
  void initState() {
    super.initState();
    _tick();
    _timer = Timer.periodic(const Duration(milliseconds: 2000), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _tick() async {
    if (_inflight) return;
    final s = context.read<AppState>();
    if (s.api == null) return;
    _inflight = true;
    try {
      final r = await s.api!.guideEkosStatus();
      if (!mounted) return;
      // Accumula il drift SOLO quando ci sono valori (durante guiding).
      final dra = (r['delta_ra'] as num?)?.toDouble();
      final ddec = (r['delta_dec'] as num?)?.toDouble();
      if (dra != null || ddec != null) {
        _history.add({'ra': dra ?? 0, 'dec': ddec ?? 0});
        if (_history.length > _maxPoints) {
          _history.removeRange(0, _history.length - _maxPoints);
        }
      }
      setState(() => _status = r);
    } catch (_) {
      // transitorio: manteniamo l'ultimo stato noto
    } finally {
      _inflight = false;
    }
  }

  Future<void> _safe(Future Function() fn, String msg) async {
    try {
      await fn();
      if (mounted) showSnack(context, msg);
    } on ApiException catch (e) {
      if (mounted) {
        showSnack(context, '${'Errore: '.tr(context)}${_detail(e.body)}', error: true);
      }
    } catch (e) {
      if (mounted) showSnack(context, '${'Errore: '.tr(context)}$e', error: true);
    }
  }

  String _detail(String body) {
    try {
      final j = jsonDecode(body);
      if (j is Map && j['detail'] != null) return j['detail'].toString();
    } catch (_) {}
    return body;
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<AppState>().api;
    final st = _status?['state']?.toString() ?? '—';
    final rms = (_status?['rms_total'] as num?)?.toDouble();
    final raRms = (_status?['rms_ra'] as num?)?.toDouble();
    final decRms = (_status?['rms_dec'] as num?)?.toDouble();
    final dRa = (_status?['delta_ra'] as num?)?.toDouble();
    final dDec = (_status?['delta_dec'] as num?)?.toDouble();
    final cam = _status?['camera']?.toString();
    final guider = _status?['guider']?.toString();
    final exp = (_status?['exposure'] as num?)?.toDouble();
    final log = (_status?['log'] as List?)?.cast<dynamic>() ?? const [];
    final guiding = st.toUpperCase().contains('GUID');

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.menu), onPressed: openShellDrawer),
        title: Row(children: [
          const LiveDot(),
          const SizedBox(width: 10),
          Text('${'Guide'.tr(context)} · Ekos'),
          const Spacer(),
          Text(st, style: TextStyle(
              color: guiding ? T.ok(context) : T.muted(context), fontSize: 12)),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: 'Ricontrolla guider'.tr(context),
            onPressed: () => widget.onReload?.call(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 80),
        children: [
          // Banner "guida interna"
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: T.accent(context).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: T.accent(context).withValues(alpha: 0.5)),
            ),
            child: Row(children: [
              Icon(Icons.auto_graph, color: T.accent(context), size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(
                'Guida interna di Ekos (AI/GPG). Grafico e dati live qui sotto.'.tr(context),
                style: TextStyle(color: T.muted(context), fontSize: 12),
              )),
            ]),
          ),
          const SizedBox(height: 12),

          // GRAFICO DI DRIFT (come PHD2)
          _chart(context),
          const SizedBox(height: 12),

          // DATI: RMS + deflessione istantanea
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2, mainAxisSpacing: 8, crossAxisSpacing: 8,
            childAspectRatio: 1.7,
            children: [
              StatusCard(header: 'RMS TOTAL'.tr(context),
                  value: rms == null ? '—' : '${rms.toStringAsFixed(2)}″',
                  subtitle: 'target < 1.0″'),
              StatusCard(header: 'STATO'.tr(context), value: st),
              StatusCard(header: 'RA RMS'.tr(context),
                  value: raRms == null ? '—' : '${raRms.toStringAsFixed(2)}″'),
              StatusCard(header: 'DEC RMS'.tr(context),
                  value: decRms == null ? '—' : '${decRms.toStringAsFixed(2)}″'),
              StatusCard(header: 'δ RA'.tr(context),
                  value: dRa == null ? '—' : '${dRa.toStringAsFixed(2)}″'),
              StatusCard(header: 'δ DEC'.tr(context),
                  value: dDec == null ? '—' : '${dDec.toStringAsFixed(2)}″'),
            ],
          ),
          const SizedBox(height: 10),

          // INFO camera/guider/esposizione
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: T.panel(context),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: T.line(context)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _infoRow(context, 'Camera'.tr(context), cam ?? '—'),
              _infoRow(context, 'Guider'.tr(context), guider ?? '—'),
              _infoRow(context, 'Esposizione'.tr(context),
                  exp == null ? '—' : '${exp.toStringAsFixed(1)} s'),
            ]),
          ),
          const SizedBox(height: 12),

          // COMANDI
          Row(children: [
            Expanded(child: PrimaryButton(label: 'START', icon: Icons.play_arrow,
                onPressed: api == null ? null
                    : () => _safe(() => api.guideEkosStart(), 'Guida avviata'.tr(context)))),
            const SizedBox(width: 8),
            Expanded(child: GhostButton(label: 'STOP', icon: Icons.stop,
                onPressed: api == null ? null
                    : () => _safe(() => api.guideEkosStop(), 'Fermato'.tr(context)))),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: GhostButton(label: 'DITHER', icon: Icons.scatter_plot,
                onPressed: api == null ? null
                    : () => _safe(() => api.guideEkosDither(), 'Dither'.tr(context)))),
            const SizedBox(width: 8),
            Expanded(child: GhostButton(label: 'LOOP', icon: Icons.loop,
                onPressed: api == null ? null
                    : () => _safe(() => api.guideEkosLoop(), 'Loop avviato'.tr(context)))),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: GhostButton(label: 'CALIBRATE', icon: Icons.adjust,
                onPressed: api == null ? null
                    : () => _safe(() => api.guideEkosCalibrate(),
                        'Calibrazione avviata'.tr(context)))),
          ]),
          const SizedBox(height: 14),

          // LOG di guida
          if (log.isNotEmpty) ...[
            Text('LOG'.tr(context), style: TextStyle(
                color: T.muted(context), fontSize: 11, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: T.panel(context),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: T.line(context)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: log.map((l) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Text(l.toString(), style: TextStyle(
                      color: T.muted(context), fontSize: 11, fontFamily: 'monospace')),
                )).toList(),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Nota onesta su star image
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: T.panel(context),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: T.line(context)),
            ),
            child: Row(children: [
              Icon(Icons.info_outline, color: T.muted(context), size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(
                "Immagine live della stella: in arrivo nella prossima versione "
                "(client INDI dedicato). Per ora usa il grafico qui sopra."
                    .tr(context),
                style: TextStyle(color: T.muted(context), fontSize: 11),
              )),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(BuildContext context, String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(children: [
      Text(k, style: TextStyle(color: T.muted(context), fontSize: 12)),
      const Spacer(),
      Text(v, style: TextStyle(
          color: T.text(context), fontSize: 12, fontWeight: FontWeight.w600)),
    ]),
  );

  /// Grafico di inseguimento stile PHD2: RA (accent) e DEC (accent2), asse Y
  /// in arcsec signato ± con mezzeria a 0. Alimentato da `_history` (delta).
  Widget _chart(BuildContext context) {
    if (_history.isEmpty) {
      return Container(
        height: 180,
        decoration: BoxDecoration(
          color: T.panel(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: T.line(context)),
        ),
        child: Center(child: Text(
            'In attesa di dati guide…\nAvvia il guiding per vedere il grafico.'.tr(context),
            textAlign: TextAlign.center,
            style: TextStyle(color: T.muted(context), fontSize: 12))),
      );
    }

    final raSpots = <FlSpot>[];
    final decSpots = <FlSpot>[];
    double absMax = 1.0;
    for (var i = 0; i < _history.length; i++) {
      final ra = _history[i]['ra'] ?? 0;
      final dec = _history[i]['dec'] ?? 0;
      raSpots.add(FlSpot(i.toDouble(), ra));
      decSpots.add(FlSpot(i.toDouble(), dec));
      final a = ra.abs() > dec.abs() ? ra.abs() : dec.abs();
      if (a > absMax) absMax = a;
    }
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
          Text('Y: ±${yScale.toStringAsFixed(1)}″ · ${_history.length} pts',
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
                spots: raSpots, isCurved: false,
                color: T.accent(context), barWidth: 1.3,
                dotData: const FlDotData(show: false),
              ),
              LineChartBarData(
                spots: decSpots, isCurved: false,
                color: T.accent2(context), barWidth: 1.3,
                dotData: const FlDotData(show: false),
              ),
            ],
          ),
        )),
      ]),
    );
  }
}
