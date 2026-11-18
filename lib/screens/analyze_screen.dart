import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../i18n/strings.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/responsive.dart';

/// Analyze: timeline sessione con metriche aggregate dei frame ricevuti
/// e dei dati PHD2 storici.
class AnalyzeScreen extends StatelessWidget {
  const AnalyzeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final phd2 = s.phd2History;
    return Scaffold(
      appBar: AppBar(title: Text('Analyze'.tr(context))),
      body: AdaptiveListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 80),
        children: [
          SectionLabel('Sessione corrente'.tr(context)),
          // Altezza secondo il contenuto (non piu' 3 colonne fisse a ratio 1.4).
          AdaptiveGrid(
            minTileWidth: 110,
            maxColumns: 6,
            spacing: 6,
            children: [
              StatusCard(header: 'EVENTS WS'.tr(context), value: '${s.wsEventsReceived}'),
              StatusCard(header: 'PROPS'.tr(context), value: '${s.properties.length}'),
              StatusCard(header: 'DEVICES'.tr(context), value: '${s.devices.length}'),
            ],
          ),
          SectionLabel('Ultimo frame'.tr(context)),
          _lastFrameInfo(context, s),
          SectionLabel('PHD2 RMS storico'.tr(context)),
          _phd2Chart(context, phd2),
          SectionLabel('Messaggi INDI'.tr(context)),
          if (s.messages.isEmpty)
            Padding(padding: const EdgeInsets.all(20),
                child: Text('—', style: TextStyle(color: T.muted(context)))),
          for (final m in s.messages.reversed.take(20))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text('${m['device'] ?? ''} ${m['message'] ?? ''}',
                  style: TextStyle(color: T.muted(context), fontSize: 11, fontFamily: 'monospace'),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
        ],
      ),
    );
  }

  Widget _lastFrameInfo(BuildContext c, AppState s) {
    final m = s.lastFrameMeta;
    if (m.isEmpty) {
      return Padding(padding: const EdgeInsets.all(12),
          child: Text('Nessun frame ancora.'.tr(c), style: TextStyle(color: T.muted(c))));
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: T.panel(c), borderRadius: BorderRadius.circular(10),
        border: Border.all(color: T.line(c)),
      ),
      child: Wrap(spacing: 12, runSpacing: 6, children: [
        _kv(c, 'OBJ', m['object']?.toString() ?? '—'),
        _kv(c, 'FILTER', m['filter']?.toString() ?? '—'),
        _kv(c, 'EXP', m['exposure'] == null ? '—' : '${m['exposure']}s'),
        _kv(c, 'HFR', (m['hfr'] as num?)?.toStringAsFixed(2) ?? '—'),
        _kv(c, '★', '${m['stars'] ?? '—'}'),
        _kv(c, 'SIZE', '${m['width'] ?? '—'}×${m['height'] ?? '—'}'),
      ]),
    );
  }

  Widget _kv(BuildContext c, String k, String v) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text('$k ', style: TextStyle(color: T.muted(c), fontSize: 10)),
      Text(v, style: const TextStyle(fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.w600)),
    ]);
  }

  Widget _phd2Chart(BuildContext c, List<Map<String, dynamic>> hist) {
    if (hist.isEmpty) {
      return Container(
        height: 140,
        decoration: BoxDecoration(
          color: T.panel(c), borderRadius: BorderRadius.circular(10),
          border: Border.all(color: T.line(c)),
        ),
        child: Center(child: Text('No PHD2 data'.tr(c), style: TextStyle(color: T.muted(c)))),
      );
    }
    final raSpots = <FlSpot>[];
    final decSpots = <FlSpot>[];
    for (var i = 0; i < hist.length; i++) {
      final ra = (hist[i]['rms_ra'] as num?)?.toDouble() ?? 0;
      final dec = (hist[i]['rms_dec'] as num?)?.toDouble() ?? 0;
      raSpots.add(FlSpot(i.toDouble(), ra));
      decSpots.add(FlSpot(i.toDouble(), dec));
    }
    return Container(
      height: 160,
      padding: const EdgeInsets.fromLTRB(8, 14, 14, 6),
      decoration: BoxDecoration(
        color: T.panel(c), borderRadius: BorderRadius.circular(10),
        border: Border.all(color: T.line(c)),
      ),
      child: LineChart(LineChartData(
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(spots: raSpots, isCurved: true,
              color: T.accent(c), barWidth: 1.5, dotData: const FlDotData(show: false)),
          LineChartBarData(spots: decSpots, isCurved: true,
              color: T.accent2(c), barWidth: 1.5, dotData: const FlDotData(show: false)),
        ],
        minY: 0, maxY: 3,
      )),
    );
  }
}
