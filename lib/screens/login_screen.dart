import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_version.dart';
import '../i18n/strings.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'qr_scan_screen.dart';
import 'diagnostics_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _token;
  bool _busy = false;
  String? _err;
  bool _obscureToken = true;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>();
    _host = TextEditingController(text: s.host);
    _port = TextEditingController(text: '${s.port}');
    _token = TextEditingController(text: s.token);
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _scanQr() async {
    final result = await Navigator.push<ScannedConfig>(
      context,
      MaterialPageRoute(builder: (_) => const QrScanScreen()),
    );
    if (result == null || !mounted) return;
    setState(() {
      _host.text = result.host;
      _port.text = '${result.port}';
      _token.text = result.token;
      _err = null;
    });
    showSnack(context, '${'QR letto: '.tr(context)}${result.host}:${result.port}');
  }

  Future<void> _connect() async {
    setState(() { _busy = true; _err = null; });
    final s = context.read<AppState>();
    final host = _host.text.trim();
    final port = int.tryParse(_port.text.trim()) ?? 8765;
    final token = _token.text.trim();
    if (host.isEmpty || token.isEmpty) {
      setState(() {
        _busy = false;
        _err = 'Host e token sono obbligatori'.tr(context);
      });
      return;
    }
    // Se c'è già una bridge attiva, aggiorna i suoi dati. Se non c'è
    // ancora alcuna bridge, ne crea una nuova nella lista.
    if (s.activeBridge == null) {
      // useHttps non e' sempre false: se la app e' servita in HTTPS (la web
      // UI del bridge dietro un reverse proxy, per dire), forzare http
      // significa costruire URL ws:// che il browser blocca come mixed
      // content, e la connessione non parte mai.
      await s.addBridge(name: host, host: host, port: port,
                        token: token, useHttps: AppState.originHttps);
    } else {
      s.host = host;
      s.port = port;
      s.token = token;
      await s.savePrefs();
    }
    final ok = await s.connect();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!ok) {
        _err = s.lastConnectError ?? '${'Bridge non raggiungibile su '.tr(context)}${s.baseUrl}';
      }
    });
  }

  void _openDiagnostics() {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => DiagnosticsScreen(
        host: _host.text.trim(),
        port: int.tryParse(_port.text.trim()) ?? 8765,
        token: _token.text.trim(),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 32),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: 'Astroarch '.tr(context), style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700)),
                      TextSpan(
                        text: 'Interface'.tr(context),
                        style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: T.accent(context)),
                      ),
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  '${'Zarletti-Osservatorio Jupiter'.tr(context)} · v$kAppVersion',
                  style: TextStyle(color: T.muted(context), fontSize: 12),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 36),
                _label('HOST (TAILSCALE / LAN)'),
                TextField(
                  controller: _host,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    hintText: 'es. 100.x.y.z (Tailscale)'.tr(context),
                    // Hint grigia chiara per non sembrare un valore reale
                    hintStyle: TextStyle(
                        color: T.muted(context).withValues(alpha: 0.5),
                        fontStyle: FontStyle.italic),
                  ),
                ),
                const SizedBox(height: 12),
                _label('PORTA'),
                TextField(
                  controller: _port,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: 'es. 8765'.tr(context),
                    hintStyle: TextStyle(
                        color: T.muted(context).withValues(alpha: 0.5),
                        fontStyle: FontStyle.italic),
                  ),
                ),
                const SizedBox(height: 12),
                _label('TOKEN'),
                TextField(
                  controller: _token,
                  obscureText: _obscureToken,
                  decoration: InputDecoration(
                    hintText: '••••••••',
                    suffixIcon: IconButton(
                      icon: Icon(_obscureToken ? Icons.visibility : Icons.visibility_off, size: 18),
                      onPressed: () => setState(() => _obscureToken = !_obscureToken),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _scanQr,
                  icon: Icon(Icons.qr_code_scanner, color: T.accent(context)),
                  label: Text('SCANSIONA QR DALLA DASHBOARD'.tr(context),
                      style: TextStyle(color: T.accent(context), fontWeight: FontWeight.w700, letterSpacing: .4)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: T.accent(context).withValues(alpha: 0.6)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: _busy ? null : _connect,
                        child: _busy
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                            : Text('CONNETTI'.tr(context)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 1,
                      child: OutlinedButton.icon(
                        icon: Icon(Icons.medical_services, size: 16, color: T.accent2(context)),
                        label: Text('TEST'.tr(context),
                            style: TextStyle(color: T.accent2(context), fontWeight: FontWeight.w700)),
                        onPressed: _busy ? null : _openDiagnostics,
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: T.accent2(context).withValues(alpha: 0.6)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_err != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: T.err(context).withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: T.err(context).withValues(alpha: 0.45)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.error_outline, color: T.err(context), size: 16),
                            const SizedBox(width: 6),
                            Text('Errore di connessione'.tr(context),
                                style: TextStyle(color: T.err(context), fontWeight: FontWeight.w700, fontSize: 12)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(_err!, style: TextStyle(color: T.text(context), fontSize: 11.5)),
                        const SizedBox(height: 6),
                        Text('Tap "TEST" per diagnostica step-by-step.'.tr(context),
                            style: TextStyle(color: T.muted(context), fontSize: 10.5)),
                      ],
                    ),
                  ),
                ],
                // (Vecchio link rimosso — il bottone "TEST" sopra apre la Diagnostica)
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: T.accent2(context).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: T.accent2(context).withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.lock_outline, size: 14, color: T.accent2(context)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'WireGuard via Tailscale · cifrato end-to-end'.tr(context),
                          style: TextStyle(color: T.accent2(context), fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Tema: '.tr(context), style: TextStyle(color: T.muted(context), fontSize: 11)),
                    ChipToggle(
                      label: 'Pro'.tr(context),
                      selected: !state.nightMode,
                      onTap: () => state.setNight(false),
                    ),
                    const SizedBox(width: 6),
                    ChipToggle(
                      label: 'Notte'.tr(context),
                      selected: state.nightMode,
                      onTap: () => state.setNight(true),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 0, 0, 6),
        child: Text(t, style: TextStyle(fontSize: 10, color: T.muted(context), letterSpacing: 1.2)),
      );
}
