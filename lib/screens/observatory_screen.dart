import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/api_client.dart';
import '../i18n/strings.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/responsive.dart';

class ObservatoryScreen extends StatefulWidget {
  const ObservatoryScreen({super.key});
  @override
  State<ObservatoryScreen> createState() => _ObservatoryScreenState();
}

class _ObservatoryScreenState extends State<ObservatoryScreen> {
  Map<String, dynamic>? _data;
  bool _loading = false;

  @override
  void initState() { super.initState(); _refresh(); }

  Future<void> _refresh() async {
    final s = context.read<AppState>();
    if (s.api == null) return;
    setState(() => _loading = true);
    try {
      _data = await s.api!.observatoryStatus();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, '${'Errore: '.tr(context)}${e.body}', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _safe(Future Function() fn, String okMsg) async {
    try { await fn(); await _refresh(); if (mounted) showSnack(context, okMsg); }
    on ApiException catch (e) { if (mounted) showSnack(context, '${'Errore: '.tr(context)}${e.body}', error: true); }
    catch (e) { if (mounted) showSnack(context, '${'Errore: '.tr(context)}$e', error: true); }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final candidates = (_data?['candidates'] as Map?) ?? {};
    final hasAnyConnected =
        ((_data?['weather'] as List?) ?? []).isNotEmpty ||
        ((_data?['dome'] as List?) ?? []).isNotEmpty ||
        ((_data?['dust_cap'] as List?) ?? []).isNotEmpty ||
        ((_data?['flat_panel'] as List?) ?? []).isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        leading: Builder(builder: (c) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(c).openDrawer())),
        title: Text('Observatory'.tr(context)),
        actions: [
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading && _data == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: AdaptiveListView(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 80),
                children: [
                  if (!hasAnyConnected) _emptyHint(s, candidates),
                  _section('Weather'.tr(context), (_data?['weather'] as List? ?? []).cast<Map>()),
                  _domeSection(s),
                  _dustCapSection(s),
                  _flatPanelSection(s),
                  _candidatesSection(s, candidates),
                ],
              ),
            ),
    );
  }

  Widget _emptyHint(AppState s, Map candidates) {
    final hasAny = (candidates['weather'] as List?)?.isNotEmpty == true ||
        (candidates['dome'] as List?)?.isNotEmpty == true ||
        (candidates['dust_cap'] as List?)?.isNotEmpty == true ||
        (candidates['flat_panel'] as List?)?.isNotEmpty == true;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: T.warn(context).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: T.warn(context).withValues(alpha: 0.4)),
      ),
      child: Row(children: [
        Icon(Icons.info_outline, color: T.warn(context), size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(
          hasAny
              ? 'Nessun device meteo/dome connesso. Tappa CONNECT sui driver candidati qui sotto.'.tr(context)
              : 'Nessun driver meteo/dome/flat caricato in questo profilo Ekos.'.tr(context),
          style: TextStyle(color: T.text(context), fontSize: 12),
        )),
      ]),
    );
  }

  Widget _candidatesSection(AppState s, Map candidates) {
    final all = <Map<String, dynamic>>[];
    for (final cat in ['weather', 'dome', 'dust_cap', 'flat_panel']) {
      for (final c in (candidates[cat] as List? ?? [])) {
        final m = (c as Map).cast<String, dynamic>();
        m['category'] = cat;
        all.add(m);
      }
    }
    if (all.isEmpty) return const SizedBox();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionLabel('Driver disponibili nel profilo'.tr(context)),
      for (final c in all) _candidateRow(s, c),
    ]);
  }

  Widget _candidateRow(AppState s, Map<String, dynamic> c) {
    final connected = c['connected'] == true;
    final cat = c['category'] as String? ?? '';
    String catLabel;
    switch (cat) {
      case 'weather': catLabel = 'meteo'; break;
      case 'dome': catLabel = 'dome'; break;
      case 'dust_cap': catLabel = 'dust cap'; break;
      case 'flat_panel': catLabel = 'flat panel'; break;
      default: catLabel = cat;
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      decoration: BoxDecoration(
        color: T.panel(context), borderRadius: BorderRadius.circular(10),
        border: Border.all(color: T.line(context)),
      ),
      child: Row(children: [
        Container(
          width: 8, height: 8,
          decoration: BoxDecoration(
            color: connected ? T.ok(context) : T.muted(context),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(c['device'] ?? '',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          Text('${'candidato '.tr(context)}$catLabel · ${connected ? 'connesso (no proprietà ancora)'.tr(context) : 'non connesso'.tr(context)}',
              style: TextStyle(color: T.muted(context), fontSize: 11)),
        ])),
        TextButton(
          onPressed: () async {
            try {
              if (connected) {
                await s.api!.indiDisconnect(c['device']);
              } else {
                await s.api!.indiConnect(c['device']);
              }
              await Future.delayed(const Duration(milliseconds: 1500));
              await s.refreshSnapshot();
              _refresh();
            } catch (e) {
              if (mounted) showSnack(context, '${'Errore: '.tr(context)}$e', error: true);
            }
          },
          child: Text(connected ? 'DISCONNECT'.tr(context) : 'CONNECT'.tr(context),
              style: TextStyle(
                color: connected ? T.muted(context) : T.ok(context),
                fontWeight: FontWeight.w700, fontSize: 11,
              )),
        ),
      ]),
    );
  }

  Widget _section(String title, List<Map> entries) {
    if (entries.isEmpty) return const SizedBox();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(title),
        for (final w in entries) _weatherCard(w),
      ],
    );
  }

  Widget _weatherCard(Map w) {
    final params = (w['parameters'] as List? ?? []).cast<Map>();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: T.panel(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: T.line(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(w['device'] ?? '—', style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(spacing: 16, runSpacing: 6, children: [
            for (final p in params)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Text('${p['label'] ?? p['name']}: ', style: TextStyle(color: T.muted(context), fontSize: 11)),
                Text('${p['value']}', style: const TextStyle(fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.w600)),
              ]),
          ]),
        ],
      ),
    );
  }

  Widget _domeSection(AppState s) {
    final domes = (_data?['dome'] as List? ?? []).cast<Map>();
    if (domes.isEmpty) return const SizedBox();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel('Dome / Tetto'.tr(context)),
        for (final d in domes) _domeCard(s, d),
      ],
    );
  }

  Widget _domeCard(AppState s, Map d) {
    final dev = d['device'] as String;
    final shutter = d['shutter']?.toString() ?? '—';
    final isOpen = shutter == 'SHUTTER_OPEN';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: T.panel(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: T.line(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Text(dev, style: const TextStyle(fontWeight: FontWeight.w600)),
            const Spacer(),
            StatusBadge(text: isOpen ? 'OPEN'.tr(context) : 'CLOSED'.tr(context),
                color: isOpen ? T.ok(context) : T.warn(context)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: PrimaryButton(label: 'OPEN'.tr(context), icon: Icons.unfold_more, color: T.ok(context),
                onPressed: () => _safe(() => s.api!.domeShutter(dev, true), 'Apertura'.tr(context)))),
            const SizedBox(width: 8),
            Expanded(child: GhostButton(label: 'CLOSE'.tr(context), icon: Icons.unfold_less, danger: true,
                onPressed: () => _safe(() => s.api!.domeShutter(dev, false), 'Chiusura'.tr(context)))),
          ]),
        ],
      ),
    );
  }

  Widget _dustCapSection(AppState s) {
    final caps = (_data?['dust_cap'] as List? ?? []).cast<Map>();
    if (caps.isEmpty) return const SizedBox();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel('Dust cap'.tr(context)),
        for (final c in caps) Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: T.panel(context), borderRadius: BorderRadius.circular(12),
            border: Border.all(color: T.line(context)),
          ),
          child: Row(children: [
            Text(c['device'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
            const Spacer(),
            ChipToggle(label: 'Open'.tr(context), selected: c['parked'] == false,
                onTap: () => _safe(() => s.api!.dustCap(c['device'], false), 'Open'.tr(context))),
            const SizedBox(width: 6),
            ChipToggle(label: 'Park'.tr(context), selected: c['parked'] == true,
                onTap: () => _safe(() => s.api!.dustCap(c['device'], true), 'Park'.tr(context))),
          ]),
        ),
      ],
    );
  }

  Widget _flatPanelSection(AppState s) {
    final panels = (_data?['flat_panel'] as List? ?? []).cast<Map>();
    if (panels.isEmpty) return const SizedBox();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel('Flat panel'.tr(context)),
        for (final p in panels)
          _FlatPanelCard(device: p['device'], on: p['on'] == true, intensity: (p['intensity'] as num?)?.toDouble() ?? 0,
              onChanged: _safe),
      ],
    );
  }
}

class _FlatPanelCard extends StatefulWidget {
  final String device;
  final bool on;
  final double intensity;
  final Future<void> Function(Future Function() fn, String okMsg) onChanged;
  const _FlatPanelCard({required this.device, required this.on, required this.intensity, required this.onChanged});
  @override
  State<_FlatPanelCard> createState() => _FlatPanelCardState();
}

class _FlatPanelCardState extends State<_FlatPanelCard> {
  late double _v = widget.intensity;
  late bool _on = widget.on;

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: T.panel(context), borderRadius: BorderRadius.circular(12),
        border: Border.all(color: T.line(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Text(widget.device, style: const TextStyle(fontWeight: FontWeight.w600)),
            const Spacer(),
            Switch(value: _on, onChanged: (v) {
              setState(() => _on = v);
              widget.onChanged(() => s.api!.flatPanel(widget.device, on: v), v ? 'Panel on'.tr(context) : 'Panel off'.tr(context));
            }),
          ]),
          Slider(value: _v, min: 0, max: 255, onChanged: (v) => setState(() => _v = v),
              onChangeEnd: (v) => widget.onChanged(
                () => s.api!.flatPanel(widget.device, on: _on, intensity: v), '${'Intensity '.tr(context)}${v.round()}')),
          Text('${'Intensity '.tr(context)}${_v.round()} / 255',
              style: TextStyle(color: T.muted(context), fontSize: 11)),
        ],
      ),
    );
  }
}
