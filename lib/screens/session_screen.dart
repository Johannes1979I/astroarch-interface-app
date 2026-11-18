import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../i18n/strings.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/responsive.dart';

/// Schermata "Sessione" (v0.2.44): riepilogo della nottata in corso.
/// - durata sessione (da connessione)
/// - capture: frame fatti/totali del job Ekos attivo
/// - guiding: RMS medio/min/max + SNR medio dallo storico phd2History
/// - grafico RMS nel tempo
/// Tutti dati GIA' presenti in AppState / poll ekos_status — niente di nuovo
/// lato bridge. Schermata read-only, nessun comando inviato.
class SessionScreen extends StatefulWidget {
  const SessionScreen({super.key});
  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  Timer? _tick;
  Map<String, dynamic>? _cap;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 3), (_) {
      _refreshCap();
      if (mounted) setState(() {});
    });
    _refreshCap();
  }

  Future<void> _refreshCap() async {
    final s = context.read<AppState>();
    if (s.api == null) return;
    try {
      final st = await s.api!.captureEkosStatus();
      if (mounted) setState(() => _cap = st);
    } catch (_) {}
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String _fmtDur(Duration d) {
    final h = d.inHours, m = d.inMinutes % 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m ${d.inSeconds % 60}s';
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    // Durata sessione
    final dur = s.connectedAt == null
        ? null : DateTime.now().difference(s.connectedAt!);

    // Aggregati guiding dallo storico
    final rmsVals = <double>[];
    final snrVals = <double>[];
    for (final h in s.phd2History) {
      final r = (h['rms_total'] as num?)?.toDouble();
      if (r != null && r > 0) rmsVals.add(r);
      final sn = (h['snr'] as num?)?.toDouble();
      if (sn != null && sn > 0) snrVals.add(sn);
    }
    double? avg(List<double> v) => v.isEmpty ? null : v.reduce((a, b) => a + b) / v.length;
    final rmsAvg = avg(rmsVals);
    final rmsMin = rmsVals.isEmpty ? null : rmsVals.reduce((a, b) => a < b ? a : b);
    final rmsMax = rmsVals.isEmpty ? null : rmsVals.reduce((a, b) => a > b ? a : b);
    final snrAvg = avg(snrVals);

    // Capture
    final done = (_cap?['job_image_progress'] as num?)?.toInt();
    final total = (_cap?['job_image_count'] as num?)?.toInt();
    final activeId = (_cap?['active_job_id'] as num?)?.toInt() ?? -1;
    final hasJob = done != null && total != null && total > 0 && activeId >= 0;

    return Scaffold(
      appBar: AppBar(
        // v0.2.48: aperta da push → freccia indietro automatica (era hamburger).
        title: Row(children: [
          const Icon(Icons.nightlight, size: 18),
          const SizedBox(width: 8),
          Text('Sessione'.tr(context)),
        ]),
      ),
      body: s.api == null
          ? Center(child: Text('Non connesso'.tr(context),
              style: TextStyle(color: T.muted(context))))
          : AdaptiveListView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 80),
              children: [
                // Durata
                _bigStat(context, Icons.timer_outlined, 'Durata sessione'.tr(context),
                    dur == null ? '—' : _fmtDur(dur),
                    '${s.activeBridge?.name ?? ""} · ${s.host}'),
                const SizedBox(height: 12),

                // Capture
                SectionLabel('Acquisizione'.tr(context)),
                Row(children: [
                  Expanded(child: StatusCard(header: 'FRAME'.tr(context),
                      value: hasJob ? '$done/$total' : '—',
                      subtitle: hasJob ? 'job in corso'.tr(context) : 'nessun job'.tr(context))),
                  const SizedBox(width: 8),
                  Expanded(child: StatusCard(header: 'PROGRESSO'.tr(context),
                      value: hasJob ? '${((done / total) * 100).toStringAsFixed(0)}%' : '—',
                      subtitle: 'completato'.tr(context))),
                ]),
                const SizedBox(height: 12),

                // Guiding aggregati
                SectionLabel('Guida (RMS storico)'.tr(context)),
                // Altezza secondo il contenuto (non piu' childAspectRatio 1.9).
                AdaptiveGrid(
                  minTileWidth: 150,
                  maxColumns: 4,
                  children: [
                    StatusCard(header: 'RMS MEDIO'.tr(context),
                        value: rmsAvg == null ? '—' : '${rmsAvg.toStringAsFixed(2)}″',
                        subtitle: '${rmsVals.length} ${'campioni'.tr(context)}'),
                    StatusCard(header: 'SNR MEDIO'.tr(context),
                        value: snrAvg == null ? '—' : snrAvg.toStringAsFixed(0),
                        subtitle: 'qualità stella'.tr(context)),
                    StatusCard(header: 'RMS MIN'.tr(context),
                        value: rmsMin == null ? '—' : '${rmsMin.toStringAsFixed(2)}″',
                        subtitle: 'migliore'.tr(context)),
                    StatusCard(header: 'RMS MAX'.tr(context),
                        value: rmsMax == null ? '—' : '${rmsMax.toStringAsFixed(2)}″',
                        subtitle: 'peggiore'.tr(context)),
                  ],
                ),
                const SizedBox(height: 12),

                // Grafico RMS storico
                SectionLabel('Andamento RMS'.tr(context)),
                _rmsChart(context, rmsVals),
              ],
            ),
    );
  }

  Widget _bigStat(BuildContext c, IconData icon, String label, String value, String sub) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: T.panel(c),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: T.line(c)),
      ),
      child: Row(children: [
        Icon(icon, color: T.accent(c), size: 28),
        const SizedBox(width: 14),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(color: T.muted(c), fontSize: 11, letterSpacing: 1)),
          Text(value, style: TextStyle(color: T.text(c), fontSize: 26, fontWeight: FontWeight.w800)),
          Text(sub, style: TextStyle(color: T.muted(c), fontSize: 11)),
        ]),
      ]),
    );
  }

  Widget _rmsChart(BuildContext c, List<double> rms) {
    if (rms.length < 2) {
      return Container(
        height: 120,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: T.panel(c), borderRadius: BorderRadius.circular(12),
          border: Border.all(color: T.line(c)),
        ),
        child: Text('In attesa di dati guida…'.tr(c),
            style: TextStyle(color: T.muted(c), fontSize: 12)),
      );
    }
    final spots = <FlSpot>[
      for (int i = 0; i < rms.length; i++) FlSpot(i.toDouble(), rms[i]),
    ];
    final maxY = (rms.reduce((a, b) => a > b ? a : b) * 1.2).clamp(0.5, 100.0);
    return Container(
      height: 160,
      padding: const EdgeInsets.fromLTRB(8, 16, 12, 8),
      decoration: BoxDecoration(
        color: T.panel(c), borderRadius: BorderRadius.circular(12),
        border: Border.all(color: T.line(c)),
      ),
      child: LineChart(LineChartData(
        minY: 0, maxY: maxY,
        gridData: FlGridData(show: true, drawVerticalLine: false,
            getDrawingHorizontalLine: (v) => FlLine(color: T.line(c), strokeWidth: 0.5)),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 30,
              getTitlesWidget: (v, m) => Text('${v.toStringAsFixed(1)}',
                  style: TextStyle(color: T.muted(c), fontSize: 9)))),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots, isCurved: false,
            color: T.accent(c), barWidth: 1.5,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(show: true,
                color: T.accent(c).withValues(alpha: 0.12)),
          ),
        ],
      )),
    );
  }
}
