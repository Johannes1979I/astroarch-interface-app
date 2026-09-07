import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../api/api_client.dart';
import '../app_version.dart';
import '../i18n/strings.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../services/notifications.dart';

/// Schermata Settings: lingua UI + tema + QR di accoppiamento + info.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: Text('Impostazioni'.tr(context))),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _sectionLabel(context, 'Lingua'.tr(context)),
          Container(
            decoration: _cardDeco(context),
            child: Column(children: [
              RadioListTile<AppLocale>(
                value: AppLocale.it,
                groupValue: s.locale,
                onChanged: (v) { if (v != null) s.setLocale(v); },
                title: Text('Italiano (predefinito)'.tr(context)),
                subtitle: Text('Italiano',
                    style: TextStyle(color: T.muted(context), fontSize: 11)),
                secondary: const Text('🇮🇹', style: TextStyle(fontSize: 22)),
              ),
              const Divider(height: 1),
              RadioListTile<AppLocale>(
                value: AppLocale.en,
                groupValue: s.locale,
                onChanged: (v) { if (v != null) s.setLocale(v); },
                title: Text('English'.tr(context)),
                subtitle: Text('English',
                    style: TextStyle(color: T.muted(context), fontSize: 11)),
                secondary: const Text('🇬🇧', style: TextStyle(fontSize: 22)),
              ),
              const Divider(height: 1),
              RadioListTile<AppLocale>(
                value: AppLocale.fr,
                groupValue: s.locale,
                onChanged: (v) { if (v != null) s.setLocale(v); },
                title: Text('Français'.tr(context)),
                subtitle: Text('Français',
                    style: TextStyle(color: T.muted(context), fontSize: 11)),
                secondary: const Text('🇫🇷', style: TextStyle(fontSize: 22)),
              ),
            ]),
          ),
          const SizedBox(height: 18),
          // v0.2.48: dimensione testo (Tucniak: testo piccolo su tablet)
          _sectionLabel(context, 'Dimensione testo'.tr(context)),
          Container(
            decoration: _cardDeco(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(children: [
                Icon(Icons.format_size, color: T.accent(context), size: 20),
                const SizedBox(width: 8),
                Expanded(child: SegmentedButton<double>(
                  segments: [
                    ButtonSegment(value: 1.0, label: Text('Normale'.tr(context))),
                    ButtonSegment(value: 1.15, label: Text('Grande'.tr(context))),
                    ButtonSegment(value: 1.3, label: Text('XL'.tr(context))),
                  ],
                  selected: {_nearestScale(s.textScale)},
                  showSelectedIcon: false,
                  onSelectionChanged: (sel) => s.setTextScale(sel.first),
                )),
              ]),
            ),
          ),
          const SizedBox(height: 18),
          _sectionLabel(context, 'Aspetto'.tr(context)),
          Container(
            decoration: _cardDeco(context),
            child: Column(children: [
              RadioListTile<AppThemeMode>(
                value: AppThemeMode.pro,
                groupValue: s.themeMode,
                onChanged: (v) { if (v != null) s.setThemeMode(v); },
                secondary: Icon(Icons.wb_sunny, color: T.accent(context)),
                title: Text('Tema Pro'.tr(context)),
                subtitle: Text('Ambra/blu, alta leggibilità'.tr(context),
                    style: TextStyle(color: T.muted(context), fontSize: 11)),
              ),
              RadioListTile<AppThemeMode>(
                value: AppThemeMode.night,
                groupValue: s.themeMode,
                onChanged: (v) { if (v != null) s.setThemeMode(v); },
                secondary: Icon(Icons.nightlight_round, color: T.accent(context)),
                title: Text('Tema Notte'.tr(context)),
                subtitle: Text('Luce rossa, non rovina la visione notturna'.tr(context),
                    style: TextStyle(color: T.muted(context), fontSize: 11)),
              ),
              RadioListTile<AppThemeMode>(
                value: AppThemeMode.deepSpace,
                groupValue: s.themeMode,
                onChanged: (v) { if (v != null) s.setThemeMode(v); },
                secondary: Icon(Icons.auto_awesome, color: T.accent(context)),
                title: Text('Tema Deep Space'.tr(context)),
                subtitle: Text('Nebulosa blu/viola con campo stellato'.tr(context),
                    style: TextStyle(color: T.muted(context), fontSize: 11)),
              ),
              const Divider(height: 1),
              RadioListTile<AppThemeMode>(
                value: AppThemeMode.interstellar,
                groupValue: s.themeMode,
                onChanged: (v) { if (v != null) s.setThemeMode(v); },
                secondary: Icon(Icons.rocket_launch, color: T.accent(context)),
                title: const Text('Interstellar'),
                subtitle: Text('Cinematografico blu-ghiaccio · animato'.tr(context),
                    style: TextStyle(color: T.muted(context), fontSize: 11)),
              ),
              RadioListTile<AppThemeMode>(
                value: AppThemeMode.starTrek,
                groupValue: s.themeMode,
                onChanged: (v) { if (v != null) s.setThemeMode(v); },
                secondary: Icon(Icons.travel_explore, color: T.accent(context)),
                title: const Text('Star Trek'),
                subtitle: Text('Console LCARS · animato'.tr(context),
                    style: TextStyle(color: T.muted(context), fontSize: 11)),
              ),
              const Divider(height: 1),
              RadioListTile<AppThemeMode>(
                value: AppThemeMode.osservatorioJupiter,
                groupValue: s.themeMode,
                onChanged: (v) { if (v != null) s.setThemeMode(v); },
                secondary: Icon(Icons.photo_camera_back, color: T.accent(context)),
                title: const Text('Osservatorio Jupiter'),
                subtitle: Text('Foto reale (Iris NGC 7023) · font 13 Misa · deep-sky zoom'.tr(context),
                    style: TextStyle(color: T.muted(context), fontSize: 11)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Text(
                  'Font "13 Misa" © Zane Townsend (Unrender) — uso consentito, ridistribuito con la licenza originale.'.tr(context),
                  style: TextStyle(color: T.muted(context), fontSize: 9.5)),
              ),
              // Disclaimer batteria + copyright (richiesti)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(Icons.battery_alert, size: 13, color: T.warn(context)),
                    const SizedBox(width: 6),
                    Expanded(child: Text(
                      'I temi animati (Interstellar, Star Trek) consumano più batteria e CPU.'.tr(context),
                      style: TextStyle(color: T.warn(context), fontSize: 10.5))),
                  ]),
                  const SizedBox(height: 6),
                  Text(
                    'Interstellar™ e Star Trek™ sono marchi dei rispettivi proprietari. Temi a tema realizzati da fan, non ufficiali e non affiliati. Font Google Fonts (Open Font License).'.tr(context),
                    style: TextStyle(color: T.muted(context), fontSize: 9.5)),
                ]),
              ),
            ]),
          ),
          // Sul web le notifiche di sistema non ci sono: mostrare
          // l'interruttore vorrebbe dire offrire una scelta che non fa
          // niente. Meglio non mostrarlo che mostrarlo inerte.
          if (Notifs.supported) ...[
            const SizedBox(height: 18),
            _sectionLabel(context, 'Notifiche'.tr(context)),
            Container(
              decoration: _cardDeco(context),
              child: SwitchListTile(
                secondary: Icon(Icons.notifications_active, color: T.accent(context)),
                title: Text('Avvisi osservatorio'.tr(context)),
                subtitle: Text('Sequenza finita, stella persa, errori'.tr(context),
                    style: TextStyle(color: T.muted(context), fontSize: 11)),
                value: s.notificationsEnabled,
                onChanged: (v) {
                  s.setNotificationsEnabled(v);
                  Notifs.enabled = v;
                  if (v) Notifs.requestPermission();
                },
              ),
            ),
          ],
          const SizedBox(height: 18),
          _sectionLabel(context, 'Accoppiamento'.tr(context)),
          Container(
            decoration: _cardDeco(context),
            child: ListTile(
              leading: Icon(Icons.qr_code_2, color: T.accent(context)),
              title: Text('Mostra QR di accoppiamento'.tr(context)),
              subtitle: Text(
                  'Per configurare un altro dispositivo'.tr(context),
                  style: TextStyle(color: T.muted(context), fontSize: 11)),
              trailing: Icon(Icons.chevron_right, color: T.muted(context)),
              onTap: s.api == null ? null : () {
                Navigator.push(context, MaterialPageRoute(
                    builder: (_) => const _PairingQrScreen()));
              },
            ),
          ),
          const SizedBox(height: 18),
          _sectionLabel(context, 'Info app'.tr(context)),
          Container(
            decoration: _cardDeco(context),
            child: Column(children: [
              ListTile(
                leading: Icon(Icons.info_outline, color: T.accent(context)),
                title: const Text('Astroarch Interface'),
                subtitle: Text('${'Versione'.tr(context)} $kAppVersion'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(Icons.person_outline, color: T.accent(context)),
                title: const Text('Zarletti-Osservatorio Jupiter'),
                subtitle: Text('${s.host}:${s.port}',
                    style: TextStyle(color: T.muted(context), fontSize: 11,
                        fontFamily: 'monospace')),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(BuildContext c, String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
        child: Text(t.toUpperCase(),
            style: TextStyle(fontSize: 10, color: T.muted(c),
                letterSpacing: 2, fontWeight: FontWeight.w700)),
      );

  BoxDecoration _cardDeco(BuildContext c) => BoxDecoration(
        color: T.panel(c),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: T.line(c)),
      );

  /// Mappa un valore di scala salvato sull'opzione più vicina del segmento
  /// (evita "no segment selected" se il valore persistito non è esatto).
  double _nearestScale(double v) {
    const opts = [1.0, 1.15, 1.3];
    return opts.reduce((a, b) => (v - a).abs() < (v - b).abs() ? a : b);
  }
}

/// Schermata che mostra il QR generato dal bridge (con IP Tailscale).
class _PairingQrScreen extends StatefulWidget {
  const _PairingQrScreen();
  @override
  State<_PairingQrScreen> createState() => _PairingQrScreenState();
}

class _PairingQrScreenState extends State<_PairingQrScreen> {
  Map<String, dynamic>? _data;
  String? _err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = context.read<AppState>();
    if (s.api == null) return;
    try {
      final r = await s.api!.pairingQr();
      if (!mounted) return;
      setState(() { _data = r; _err = null; });
    } on ApiException catch (e) {
      if (mounted) setState(() => _err = e.body);
    } catch (e) {
      if (mounted) setState(() => _err = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('QR di accoppiamento'.tr(context)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _err != null
          ? Center(child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('${'Errore: '.tr(context)}$_err',
                  style: TextStyle(color: T.err(context))),
            ))
          : _data == null
              ? const Center(child: CircularProgressIndicator())
              : _buildBody(_data!),
    );
  }

  Widget _buildBody(Map<String, dynamic> data) {
    final pngB64 = data['png_base64'] as String?;
    final Uint8List? pngBytes = pngB64 == null ? null : base64.decode(pngB64);
    final host = data['host']?.toString() ?? '—';
    final port = data['port']?.toString() ?? '—';
    final token = data['token']?.toString() ?? '—';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Scansiona dall\'app sul nuovo dispositivo'.tr(context),
            textAlign: TextAlign.center,
            style: TextStyle(color: T.muted(context), fontSize: 12)),
        const SizedBox(height: 14),
        if (pngBytes != null) Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(14),
            border: Border.all(color: T.line(context)),
          ),
          child: Image.memory(pngBytes, fit: BoxFit.contain,
              filterQuality: FilterQuality.none),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: T.panel(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: T.line(context)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text('Oppure inserisci a mano'.tr(context).toUpperCase(),
                style: TextStyle(color: T.muted(context),
                    fontSize: 10, letterSpacing: 1.4)),
            const SizedBox(height: 6),
            _kv(context, 'Host', host),
            _kv(context, 'Porta'.tr(context), port),
            const SizedBox(height: 8),
            Text('Token'.toUpperCase(),
                style: TextStyle(color: T.muted(context),
                    fontSize: 10, letterSpacing: 1.4)),
            const SizedBox(height: 4),
            SelectableText(token,
                style: const TextStyle(
                    fontFamily: 'monospace', fontSize: 12)),
            const SizedBox(height: 8),
            Row(children: [
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.copy, size: 16),
                label: Text('Copia token'.tr(context)),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: token));
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('Token copiato'.tr(context)),
                      duration: const Duration(seconds: 2),
                    ));
                  }
                },
              ),
            ]),
          ]),
        ),
        const SizedBox(height: 14),
        Text(
          'L\'host nel QR è l\'IP Tailscale del Raspberry: '
          'il QR funziona da qualsiasi rete con Tailscale attivo. '
          'Per la LAN usa l\'IP locale del Raspberry.'.tr(context),
          textAlign: TextAlign.center,
          style: TextStyle(color: T.muted(context), fontSize: 11),
        ),
      ]),
    );
  }

  Widget _kv(BuildContext c, String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          SizedBox(width: 70, child: Text('$k:',
              style: TextStyle(color: T.muted(c), fontSize: 11))),
          Expanded(child: Text(v,
              style: const TextStyle(
                  fontFamily: 'monospace', fontSize: 13))),
        ]),
      );
}
