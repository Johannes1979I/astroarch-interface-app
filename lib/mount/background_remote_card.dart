import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../i18n/strings.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'gamepad_input.dart';

/// Pannello "In background" della schermata Telecomando: attivazione del
/// servizio di accessibilita', associazione, scelta dei tasti.
class BackgroundRemoteCard extends StatefulWidget {
  final bool invertNS;
  final bool invertEW;
  const BackgroundRemoteCard({super.key, required this.invertNS, required this.invertEW});

  @override
  State<BackgroundRemoteCard> createState() => _BackgroundRemoteCardState();
}

class _BackgroundRemoteCardState extends State<BackgroundRemoteCard> {
  static const _kMode = 'remote_bg_mode';

  RemoteStatus _st = const RemoteStatus();
  String _mode = 'dpad';
  bool _busy = false;
  Timer? _poll;
  AppLifecycleListener? _life;

  @override
  void initState() {
    super.initState();
    _loadMode();
    _refresh();
    // Lo stato cambia anche fuori dall'app (impostazioni di accessibilita',
    // "Disattiva" nella notifica): lo si rilegge spesso, costa pochissimo.
    _poll = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
    _life = AppLifecycleListener(onResume: _refresh);
  }

  @override
  void dispose() {
    _poll?.cancel();
    _life?.dispose();
    super.dispose();
  }

  Future<void> _loadMode() async {
    final p = await SharedPreferences.getInstance();
    final m = p.getString(_kMode) ?? 'dpad';
    if (mounted) setState(() => _mode = m);
    await RemoteService.options(mode: m);
  }

  Future<void> _refresh() async {
    try {
      final st = await RemoteService.status();
      if (mounted) setState(() => _st = st);
    } catch (_) {}
  }

  Future<void> _setMode(String m) async {
    setState(() => _mode = m);
    final p = await SharedPreferences.getInstance();
    await p.setString(_kMode, m);
    await RemoteService.options(mode: m);
  }

  Future<void> _associate() async {
    final app = context.read<AppState>();
    final api = app.api;
    if (api == null) {
      showSnack(context, 'Bridge non connesso'.tr(context), error: true);
      return;
    }
    final host = Uri.tryParse(api.baseUrl)?.host ?? api.baseUrl;
    final mount = app.mountDevice() ?? 'Mount';
    setState(() => _busy = true);
    try {
      await RemoteService.associate(
        baseUrl: api.baseUrl, token: api.token, label: '$mount · $host',
        mode: _mode, invertNS: widget.invertNS, invertEW: widget.invertEW,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
      await _refresh();
    }
  }

  Future<void> _dissociate() async {
    await RemoteService.dissociate();
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (!GamepadInput.supported) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionLabel('In background'.tr(context)),
      Text('Associato, il controller muove la montatura anche con questa schermata chiusa o con altre app aperte (schermo acceso). In background funzionano solo i tasti, non la levetta.'
              .tr(context),
          style: TextStyle(color: T.muted(context), fontSize: 12)),
      const SizedBox(height: 10),
      if (!_st.serviceEnabled) ..._enableSteps() else _associationRow(),
      const SizedBox(height: 12),
      Text('Tasti in background'.tr(context),
          style: TextStyle(color: T.muted(context), fontSize: 12)),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, children: [
        ChipToggle(label: 'Croce · STOP = B'.tr(context), selected: _mode == 'dpad',
            onTap: () => _setMode('dpad')),
        ChipToggle(label: 'Y/A/X/B · STOP = RB'.tr(context), selected: _mode == 'buttons',
            onTap: () => _setMode('buttons')),
      ]),
      if (_mode == 'buttons')
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('Y = Nord, A = Sud, X = Ovest, B = Est'.tr(context),
              style: TextStyle(color: T.muted(context), fontSize: 12)),
        ),
      if (_st.serviceEnabled)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            '${'Ultimo tasto visto dal servizio'.tr(context)}: ${_st.lastKey ?? '—'}',
            style: TextStyle(color: T.muted(context), fontSize: 11, fontFamily: 'monospace'),
          ),
        ),
      if (_st.associated && _st.lastError != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('${'Errore: '.tr(context)}${_st.lastError}',
              style: TextStyle(color: T.err(context), fontSize: 12)),
        ),
    ]);
  }

  List<Widget> _enableSteps() => [
        Text('Serve attivare una volta il servizio "Astroarch Telecomando" fra i servizi di accessibilità di Android.'
                .tr(context),
            style: const TextStyle(fontSize: 13)),
        const SizedBox(height: 8),
        PrimaryButton(
          label: 'APRI IMPOSTAZIONI ACCESSIBILITÀ'.tr(context),
          icon: Icons.accessibility_new,
          onPressed: RemoteService.openAccessibilitySettings,
        ),
        const SizedBox(height: 8),
        Text('Se la voce è grigia o bloccata: Info app → menu ⋮ → "Consenti impostazioni con limitazioni", poi riprova.'
                .tr(context),
            style: TextStyle(color: T.muted(context), fontSize: 12)),
        const SizedBox(height: 6),
        GhostButton(
          label: 'INFO APP'.tr(context), icon: Icons.info_outline, small: true,
          onPressed: RemoteService.openAppSettings,
        ),
      ];

  Widget _associationRow() {
    if (!_st.associated) {
      return PrimaryButton(
        label: 'ASSOCIA'.tr(context), icon: Icons.link,
        onPressed: _busy ? null : _associate,
      );
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: T.panel(context), borderRadius: BorderRadius.circular(10),
        border: Border.all(color: T.ok(context)),
      ),
      child: Row(children: [
        Icon(Icons.link, color: T.ok(context)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Associato'.tr(context), style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(_st.label, style: TextStyle(color: T.muted(context), fontSize: 12)),
        ])),
        GhostButton(label: 'DISSOCIA'.tr(context), danger: true, small: true,
            onPressed: _dissociate),
      ]),
    );
  }
}
