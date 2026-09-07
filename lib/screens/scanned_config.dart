import 'dart:convert';

/// Risultato dello scan QR — dati di connessione.
class ScannedConfig {
  final String host;
  final int port;
  final String token;
  ScannedConfig({required this.host, required this.port, required this.token});

  static ScannedConfig? tryParse(String raw) {
    raw = raw.trim();
    // 1) JSON nativo della dashboard: {"v":1,"type":"astroarch-bridge","host":"...","port":8765,"token":"..."}
    if (raw.startsWith('{')) {
      try {
        final j = jsonDecode(raw);
        if (j is Map &&
            (j['type'] == 'astroarch-bridge' || j['host'] != null) &&
            j['host'] != null &&
            j['token'] != null) {
          return ScannedConfig(
            host: j['host'].toString(),
            port: j['port'] is num ? (j['port'] as num).toInt() : 8765,
            token: j['token'].toString(),
          );
        }
      } catch (_) {}
    }
    // 2) URL custom: astroarch://config?host=...&port=...&token=...
    // 3) URL http(s) con query token
    try {
      final u = Uri.parse(raw);
      final q = u.queryParameters;
      if (q['token'] != null && (q['host'] != null || u.host.isNotEmpty)) {
        return ScannedConfig(
          host: q['host'] ?? u.host,
          port: int.tryParse(q['port'] ?? '') ?? (u.hasPort ? u.port : 8765),
          token: q['token']!,
        );
      }
    } catch (_) {}
    return null;
  }
}
