import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../i18n/strings.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/responsive.dart';

class LogsScreen extends StatelessWidget {
  const LogsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final messages = s.messages.reversed.toList();
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [const LiveDot(), const SizedBox(width: 10), Text('Logs'.tr(context))]),
      ),
      body: messages.isEmpty
          ? Center(child: Text('Nessun messaggio'.tr(context), style: TextStyle(color: T.muted(context))))
          : Container(
              color: Colors.black,
              child: AdaptiveListView.builder(
                kind: ContentKind.wide,
                padding: const EdgeInsets.all(10),
                itemCount: messages.length,
                itemBuilder: (c, i) {
                  final m = messages[i];
                  final ts = (m['ts'] as num?)?.toDouble();
                  final time = ts != null
                      ? DateTime.fromMillisecondsSinceEpoch((ts * 1000).toInt())
                      : null;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 11, height: 1.5),
                        children: [
                          TextSpan(
                            text: time == null ? '' : '[${_fmt(time)}] ',
                            style: TextStyle(color: T.ok(c)),
                          ),
                          TextSpan(
                            text: '${m['device'] ?? ''} ',
                            style: TextStyle(color: T.accent2(c)),
                          ),
                          TextSpan(
                            text: '${m['message'] ?? ''}',
                            style: TextStyle(color: T.muted(c)),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }

  String _fmt(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
}
