import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import '../i18n/strings.dart';
import '../theme/app_theme.dart';
import '../widgets/responsive.dart';

/// Step-by-step diagnostics screen to identify where the bridge -> app
/// connection chain breaks. Executed WITHOUT relying on the full
/// Provider/AppState flow.
class DiagnosticsScreen extends StatefulWidget {
  final String host;
  final int port;
  final String token;
  const DiagnosticsScreen({
    super.key, required this.host, required this.port, required this.token,
  });

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

enum _Status { pending, running, ok, fail }

class _Step {
  final String label;
  _Status status = _Status.pending;
  String detail = '';
  Duration? duration;
  _Step(this.label);
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  final List<_Step> steps = [
    _Step('1. Host resolution (DNS / Tailscale)'),
    _Step('2. HTTP GET /healthz'),
    _Step('3. HTTP GET /api/system/info (Bearer auth)'),
    _Step('4. HTTP GET /api/system/snapshot (verify payload)'),
    _Step('5. WebSocket /ws/state (open)'),
    _Step('6. WebSocket — first message within 5s'),
    _Step('7. WebSocket — receive chunked property_def'),
  ];
  bool running = false;

  String get _baseUrl => 'http://${widget.host}:${widget.port}';
  String get _wsUrl =>
      'ws://${widget.host}:${widget.port}/ws/state?token=${Uri.encodeQueryComponent(widget.token)}';

  Future<void> _run() async {
    setState(() {
      running = true;
      for (final s in steps) {
        s.status = _Status.pending;
        s.detail = '';
        s.duration = null;
      }
    });

    final http.Client client = http.Client();
    try {
      // Step 1: resolution (proxy: attempt TCP connection via HTTP GET)
      await _runStep(0, () async {
        final sw = Stopwatch()..start();
        try {
          final r = await client.get(Uri.parse('$_baseUrl/healthz'))
              .timeout(const Duration(seconds: 4));
          sw.stop();
          steps[0].duration = sw.elapsed;
          steps[0].detail = 'host reached in ${sw.elapsedMilliseconds} ms';
          return r.statusCode > 0;
        } catch (e) {
          steps[0].detail = 'host unreachable: ${_short(e)}';
          return false;
        }
      });
      if (steps[0].status == _Status.fail) return;

      // Step 2: /healthz
      await _runStep(1, () async {
        final sw = Stopwatch()..start();
        final r = await client.get(Uri.parse('$_baseUrl/healthz'))
            .timeout(const Duration(seconds: 5));
        sw.stop();
        steps[1].duration = sw.elapsed;
        steps[1].detail = 'HTTP ${r.statusCode} · ${_short(r.body)}';
        return r.statusCode == 200;
      });
      if (steps[1].status == _Status.fail) return;

      // Step 3: /api/system/info (auth)
      await _runStep(2, () async {
        final sw = Stopwatch()..start();
        final r = await client.get(
          Uri.parse('$_baseUrl/api/system/info'),
          headers: {'Authorization': 'Bearer ${widget.token}'},
        ).timeout(const Duration(seconds: 5));
        sw.stop();
        steps[2].duration = sw.elapsed;
        if (r.statusCode == 401) {
          steps[2].detail = '401 — Token rejected (verify it is correct)';
          return false;
        }
        steps[2].detail = 'HTTP ${r.statusCode} · ${_short(r.body)}';
        return r.statusCode == 200;
      });
      if (steps[2].status == _Status.fail) return;

      // Step 4: REST snapshot
      int devCount = 0;
      int propCount = 0;
      await _runStep(3, () async {
        final sw = Stopwatch()..start();
        final r = await client.get(
          Uri.parse('$_baseUrl/api/system/snapshot'),
          headers: {'Authorization': 'Bearer ${widget.token}'},
        ).timeout(const Duration(seconds: 10));
        sw.stop();
        steps[3].duration = sw.elapsed;
        if (r.statusCode != 200) {
          steps[3].detail = 'HTTP ${r.statusCode}';
          return false;
        }
        try {
          final j = jsonDecode(r.body);
          final devs = (j['devices'] as List?) ?? [];
          final props = (j['properties'] as List?) ?? [];
          devCount = devs.length;
          propCount = props.length;
          final indi = j['connections']?['indi'];
          steps[3].detail = 'devices=$devCount · properties=$propCount · INDI=$indi · payload=${(r.contentLength ?? r.bodyBytes.length)} byte';
          return true;
        } catch (e) {
          steps[3].detail = 'JSON parse failed: $e';
          return false;
        }
      });
      if (steps[3].status == _Status.fail) return;

      // Step 5-7: WebSocket
      WebSocketChannel? ch;
      try {
        await _runStep(4, () async {
          final sw = Stopwatch()..start();
          try {
            ch = WebSocketChannel.connect(Uri.parse(_wsUrl));
            await ch!.ready.timeout(const Duration(seconds: 5));
            sw.stop();
            steps[4].duration = sw.elapsed;
            steps[4].detail = 'opened in ${sw.elapsedMilliseconds} ms';
            return true;
          } catch (e) {
            steps[4].detail = 'WS connect failed: ${_short(e)}';
            return false;
          }
        });
        if (steps[4].status == _Status.fail) return;

        // Fix: Convert the stream into a broadcast stream to allow multiple listeners
        final Stream<dynamic> broadcastStream = ch!.stream.asBroadcastStream();

        // Step 6: first message
        Map<String, dynamic>? firstMsg;
        await _runStep(5, () async {
          final sw = Stopwatch()..start();
          try {
            final raw = await broadcastStream.first.timeout(const Duration(seconds: 5));
            sw.stop();
            steps[5].duration = sw.elapsed;
            if (raw is String) {
              try {
                firstMsg = (jsonDecode(raw) as Map).cast<String, dynamic>();
                steps[5].detail = 'type=${firstMsg!['type']} · in ${sw.elapsedMilliseconds} ms';
                return firstMsg!['type'] == 'snapshot_begin' || firstMsg!['type'] == 'snapshot';
              } catch (e) {
                steps[5].detail = 'Malformed JSON: ${_short(raw)}';
                return false;
              }
            }
            steps[5].detail = 'unknown data type: ${raw.runtimeType}';
            return false;
          } catch (e) {
            steps[5].detail = '5s timeout or error: ${_short(e)}';
            return false;
          }
        });
        if (steps[5].status == _Status.fail) return;

        // Step 7: wait for property_def until snapshot_end or N elements
        await _runStep(6, () async {
          final sw = Stopwatch()..start();
          int gotProps = 0;
          bool endSeen = false;
          try {
            final completer = Completer<void>();
            final sub = broadcastStream.listen((data) {
              if (data is! String) return;
              try {
                final j = jsonDecode(data);
                if (j['type'] == 'property_def') gotProps++;
                if (j['type'] == 'snapshot_end') {
                  endSeen = true;
                  if (!completer.isCompleted) completer.complete();
                }
              } catch (_) {}
            });
            await completer.future.timeout(const Duration(seconds: 12));
            await sub.cancel();
          } on TimeoutException {
            // partial ok: let's see how many we received
          }
          sw.stop();
          steps[6].duration = sw.elapsed;
          steps[6].detail = 'property_def received: $gotProps / $propCount · snapshot_end: ${endSeen ? "✓" : "✗"}';
          return gotProps > 0;
        });
      } finally {
        try { await ch?.sink.close(); } catch (_) {}
      }
    } finally {
      client.close();
      if (mounted) setState(() => running = false);
    }
  }

  Future<void> _runStep(int idx, Future<bool> Function() fn) async {
    setState(() => steps[idx].status = _Status.running);
    try {
      final ok = await fn();
      if (mounted) setState(() => steps[idx].status = ok ? _Status.ok : _Status.fail);
    } catch (e) {
      if (mounted) setState(() {
        steps[idx].status = _Status.fail;
        if (steps[idx].detail.isEmpty) steps[idx].detail = _short(e);
      });
    }
  }

  String _short(Object o) {
    final s = o.toString();
    return s.length > 200 ? '${s.substring(0, 200)}…' : s;
  }

  Color _colorFor(_Status s) {
    switch (s) {
      case _Status.pending: return T.muted(context);
      case _Status.running: return T.warn(context);
      case _Status.ok: return T.ok(context);
      case _Status.fail: return T.err(context);
    }
  }

  IconData _iconFor(_Status s) {
    switch (s) {
      case _Status.pending: return Icons.radio_button_unchecked;
      case _Status.running: return Icons.sync;
      case _Status.ok: return Icons.check_circle;
      case _Status.fail: return Icons.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Connection Diagnostics'.tr(context)),
        actions: [
          TextButton.icon(
            onPressed: running ? null : _run,
            icon: Icon(running ? Icons.sync : Icons.play_arrow,
                color: running ? T.muted(context) : T.accent(context)),
            label: Text(running ? 'RUNNING'.tr(context) : 'START'.tr(context),
                style: TextStyle(color: running ? T.muted(context) : T.accent(context),
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: Column(
        children: [
          // Target + START TEST button always visible at the top
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            color: T.panel(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${'Target: '.tr(context)}${widget.host}:${widget.port}',
                    style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600)),
                Text('${'Token: '.tr(context)}${widget.token.substring(0, widget.token.length.clamp(0, 8))}…',
                    style: TextStyle(fontFamily: 'monospace', color: T.muted(context), fontSize: 11)),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity, height: 46,
                  child: ElevatedButton.icon(
                    onPressed: running ? null : _run,
                    icon: running
                        ? const SizedBox(width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                        : const Icon(Icons.play_arrow, color: Colors.black),
                    label: Text(running ? 'TEST IN PROGRESS…'.tr(context) : 'START TEST'.tr(context),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: AdaptiveListView.separated(
              kind: ContentKind.form,
              padding: const EdgeInsets.all(14),
              itemCount: steps.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (c, i) {
                final s = steps[i];
                final color = _colorFor(s.status);
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: T.panel(context),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: T.line(context)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(_iconFor(s.status), color: color, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.label.tr(context),
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            if (s.detail.isNotEmpty) Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(s.detail,
                                  style: TextStyle(color: T.muted(context), fontSize: 11, fontFamily: 'monospace')),
                            ),
                            if (s.duration != null) Text('${s.duration!.inMilliseconds} ms',
                                style: TextStyle(color: T.muted(context), fontSize: 10)),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
