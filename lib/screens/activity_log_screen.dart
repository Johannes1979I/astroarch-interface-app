import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../api/api_client.dart';
import '../i18n/strings.dart';
import '../theme/app_theme.dart';
import '../widgets/responsive.dart';

/// Activity log: mostra le ultime chiamate API con timestamp, status, errori.
/// Aggiornamento automatico ogni volta che ApiLog cambia.
class ActivityLogScreen extends StatefulWidget {
  const ActivityLogScreen({super.key});
  @override
  State<ActivityLogScreen> createState() => _ActivityLogScreenState();
}

class _ActivityLogScreenState extends State<ActivityLogScreen> {
  void _onChange() => setState(() {});

  @override
  void initState() {
    super.initState();
    ApiLog.addListener(_onChange);
  }

  @override
  void dispose() {
    ApiLog.removeListener(_onChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = ApiLog.entries;
    return Scaffold(
      appBar: AppBar(
        title: Text('${'Activity Log'.tr(context)} · ${entries.length}'),
        actions: [
          IconButton(onPressed: () => ApiLog.clear(), icon: const Icon(Icons.delete_outline)),
        ],
      ),
      body: entries.isEmpty
          ? Center(child: Text('Nessuna chiamata API ancora.\nInteragisci con l\'app per vedere l\'attività.'.tr(context),
              textAlign: TextAlign.center, style: TextStyle(color: T.muted(context))))
          : AdaptiveListView.separated(
              kind: ContentKind.wide,
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 80),
              itemCount: entries.length,
              separatorBuilder: (_, __) => const SizedBox(height: 4),
              itemBuilder: (c, i) => _entryTile(c, entries[i]),
            ),
    );
  }

  Widget _entryTile(BuildContext c, ApiLogEntry e) {
    Color statusColor;
    if (e.error != null) {
      statusColor = T.err(c);
    } else if (e.ok) {
      statusColor = T.ok(c);
    } else {
      statusColor = T.warn(c);
    }
    return InkWell(
      onTap: () => _showDetail(e),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: T.panel(c),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: T.line(c)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 38,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  e.error != null ? 'ERR' : (e.status?.toString() ?? '—'),
                  style: TextStyle(color: statusColor, fontSize: 10,
                      fontWeight: FontWeight.w700, fontFamily: 'monospace'),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(width: 6),
              Text(e.method,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: T.accent(c))),
              const SizedBox(width: 6),
              Expanded(
                child: Text(e.path,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                    overflow: TextOverflow.ellipsis),
              ),
              Text('${e.duration.inMilliseconds}ms',
                  style: TextStyle(color: T.muted(c), fontSize: 10, fontFamily: 'monospace')),
            ]),
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 44),
              child: Text(
                _fmtTime(e.ts) + ' · ' + (e.error ?? e.body ?? ''),
                style: TextStyle(color: T.muted(c), fontSize: 10),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmtTime(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}.${(t.millisecond ~/ 10).toString().padLeft(2, '0')}';

  void _showDetail(ApiLogEntry e) {
    showModalBottomSheet(
      context: context,
      backgroundColor: T.panel(context),
      builder: (_) => Container(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${e.method}  ${e.path}', style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('${_fmtTime(e.ts)}  ·  ${e.duration.inMilliseconds}ms  ·  ${'status'.tr(context)} ${e.status ?? "?"}',
                  style: TextStyle(color: T.muted(context), fontSize: 11)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF05080e),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  e.error ?? e.body ?? '(no body)',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text:
                      '${e.method} ${e.path}\nstatus: ${e.status}\nerror: ${e.error}\nbody: ${e.body}'));
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.copy, size: 14),
                  label: Text('Copia'.tr(context)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
