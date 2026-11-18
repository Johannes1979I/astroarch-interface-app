import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/api_client.dart';
import '../i18n/strings.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/responsive.dart';

/// Clone della INDI Control Panel di Ekos.
/// Lista device a sinistra, tap -> dettaglio device con tab per group, ogni
/// property modificabile in base al tipo (Switch / Number / Text).
class IndiPanelScreen extends StatelessWidget {
  const IndiPanelScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final devices = s.devices.toList()..sort();
    return Scaffold(
      appBar: AppBar(title: Text('${'INDI Panel'.tr(context)} · ${devices.length}')),
      body: devices.isEmpty
          ? Center(child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Nessun driver INDI connesso.\nAvvia un profilo Ekos sul RPi.'.tr(context),
                  textAlign: TextAlign.center, style: TextStyle(color: T.muted(context))),
            ))
          : AdaptiveListView.separated(
              kind: ContentKind.form,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 80),
              itemCount: devices.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (c, i) {
                final dev = devices[i];
                final propCount = s.deviceProps(dev).length;
                return InkWell(
                  borderRadius: BorderRadius.circular(11),
                  onTap: () => Navigator.push(c, MaterialPageRoute(
                    builder: (_) => IndiDeviceScreen(device: dev),
                  )),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: T.panel(c),
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(color: T.line(c)),
                    ),
                    child: Row(children: [
                      Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: Colors.black26, borderRadius: BorderRadius.circular(9),
                        ),
                        alignment: Alignment.center,
                        child: Icon(_iconFor(dev, s), color: T.accent(c), size: 18),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(dev, style: const TextStyle(fontWeight: FontWeight.w600)),
                            Text('$propCount ${'proprietà'.tr(c)}', style: TextStyle(color: T.muted(c), fontSize: 11)),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, color: T.muted(c)),
                    ]),
                  ),
                );
              },
            ),
    );
  }

  IconData _iconFor(String dev, AppState s) {
    if (s.prop(dev, 'EQUATORIAL_EOD_COORD') != null) return Icons.adjust;
    if (s.prop(dev, 'CCD_EXPOSURE') != null) return Icons.camera_alt;
    if (s.prop(dev, 'ABS_FOCUS_POSITION') != null) return Icons.center_focus_strong;
    if (s.prop(dev, 'FILTER_SLOT') != null) return Icons.color_lens;
    if (s.prop(dev, 'WEATHER_PARAMETERS') != null) return Icons.cloud_queue;
    if (s.prop(dev, 'DOME_SHUTTER') != null) return Icons.house;
    return Icons.settings_input_component;
  }
}

class IndiDeviceScreen extends StatefulWidget {
  final String device;
  const IndiDeviceScreen({super.key, required this.device});
  @override
  State<IndiDeviceScreen> createState() => _IndiDeviceScreenState();
}

class _IndiDeviceScreenState extends State<IndiDeviceScreen> {
  String? _selectedGroup;

  Future<void> _connect(bool connect) async {
    final s = context.read<AppState>();
    if (s.api == null) return;
    try {
      if (connect) {
        await s.api!.indiConnect(widget.device);
      } else {
        await s.api!.indiDisconnect(widget.device);
      }
      await Future.delayed(const Duration(milliseconds: 600));
      await s.refreshSnapshot();
      if (mounted) showSnack(context, connect ? 'Connessione…'.tr(context) : 'Disconnesso'.tr(context));
    } catch (e) {
      if (mounted) showSnack(context, '${'Errore: '.tr(context)}$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final props = s.deviceProps(widget.device);
    final groups = props.map((p) => p['group'] as String).toSet().toList()..sort();
    if (_selectedGroup == null && groups.isNotEmpty) _selectedGroup = groups.first;
    final visible = props.where((p) => p['group'] == _selectedGroup).toList();
    // CONNECTION switch
    final connProp = s.prop(widget.device, 'CONNECTION');
    bool? isConnected;
    if (connProp != null) {
      for (final e in (connProp['elements'] as List? ?? [])) {
        if (e['name'] == 'CONNECT') isConnected = e['value'] == true;
      }
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.device),
        actions: [
          if (isConnected == false)
            TextButton.icon(
              onPressed: () => _connect(true),
              icon: Icon(Icons.power_settings_new, color: T.ok(context), size: 18),
              label: Text('CONNECT'.tr(context), style: TextStyle(color: T.ok(context), fontWeight: FontWeight.w700)),
            )
          else if (isConnected == true)
            TextButton.icon(
              onPressed: () => _connect(false),
              icon: Icon(Icons.power_settings_new, color: T.muted(context), size: 18),
              label: Text('DISCONNECT'.tr(context), style: TextStyle(color: T.muted(context), fontWeight: FontWeight.w600)),
            ),
        ],
      ),
      body: Column(
        children: [
          if (isConnected == false)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: T.warn(context).withValues(alpha: 0.12),
              child: Row(children: [
                Icon(Icons.warning_amber, color: T.warn(context), size: 16),
                const SizedBox(width: 8),
                Expanded(child: Text(
                  'Driver non connesso. Tappa CONNECT in alto per attivarlo.'.tr(context),
                  style: TextStyle(color: T.text(context), fontSize: 12),
                )),
              ]),
            ),
          if (groups.length > 1)
            SizedBox(
              height: 46,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                itemCount: groups.length,
                itemBuilder: (c, i) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChipToggle(label: groups[i],
                      selected: _selectedGroup == groups[i],
                      onTap: () => setState(() => _selectedGroup = groups[i])),
                ),
              ),
            ),
          Expanded(
            child: AdaptiveListView.builder(
              kind: ContentKind.form,
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 80),
              itemCount: visible.length,
              itemBuilder: (c, i) => _IndiPropertyTile(device: widget.device, prop: visible[i]),
            ),
          ),
        ],
      ),
    );
  }
}

class _IndiPropertyTile extends StatelessWidget {
  final String device;
  final Map<String, dynamic> prop;
  const _IndiPropertyTile({required this.device, required this.prop});

  Color _stateColor(BuildContext c, String? state) {
    switch (state) {
      case 'Ok': return T.ok(c);
      case 'Busy': return T.accent(c);
      case 'Alert': return T.err(c);
      default: return T.muted(c);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    final type = prop['type'];
    final perm = prop['perm'];
    final state = prop['state'];
    final elements = (prop['elements'] as List? ?? []).cast<Map>();
    final writable = perm == 'rw' || perm == 'wo';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: T.panel(context),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: T.line(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(width: 7, height: 7,
                decoration: BoxDecoration(color: _stateColor(context, state), shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(prop['label'] ?? prop['name'],
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            ),
            Text('$type · $perm',
                style: TextStyle(color: T.muted(context), fontSize: 10, letterSpacing: 1)),
          ]),
          const SizedBox(height: 8),
          if (type == 'Switch')
            _SwitchEditor(device: device, name: prop['name'], rule: prop['rule'],
                elements: elements, writable: writable, api: s.api)
          else if (type == 'Number')
            _NumberEditor(device: device, name: prop['name'], elements: elements,
                writable: writable, api: s.api)
          else if (type == 'Text')
            _TextEditor(device: device, name: prop['name'], elements: elements,
                writable: writable, api: s.api)
          else if (type == 'Light')
            Wrap(spacing: 8, runSpacing: 4, children: [
              for (final e in elements)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 7, height: 7, decoration: BoxDecoration(
                      color: _stateColor(context, e['value']?.toString()), shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text(e['label'] ?? e['name'], style: TextStyle(color: T.muted(context), fontSize: 11)),
                ]),
            ])
          else if (type == 'BLOB')
            Text('BLOB · ${elements.length} ${'stream'.tr(context)}', style: TextStyle(color: T.muted(context), fontSize: 11)),
        ],
      ),
    );
  }
}

class _SwitchEditor extends StatelessWidget {
  final String device;
  final String name;
  final String? rule;
  final List<Map> elements;
  final bool writable;
  final ApiClient? api;
  const _SwitchEditor({required this.device, required this.name, this.rule,
    required this.elements, required this.writable, required this.api});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6, runSpacing: 6,
      children: elements.map((e) {
        final selected = e['value'] == true;
        return ChipToggle(
          label: e['label'] ?? e['name'],
          selected: selected,
          onTap: !writable || api == null ? null : () async {
            try {
              if (rule == 'OneOfMany' || rule == 'AtMostOne') {
                final values = {for (final el in elements) el['name'] as String: el['name'] == e['name']};
                await api!.indiSet(device, name, values);
              } else {
                await api!.indiSet(device, name, {e['name']: !selected});
              }
            } catch (err) {
              if (context.mounted) showSnack(context, '${'Errore: '.tr(context)}$err', error: true);
            }
          },
        );
      }).toList(),
    );
  }
}

class _NumberEditor extends StatefulWidget {
  final String device, name;
  final List<Map> elements;
  final bool writable;
  final ApiClient? api;
  const _NumberEditor({required this.device, required this.name, required this.elements,
    required this.writable, required this.api});
  @override
  State<_NumberEditor> createState() => _NumberEditorState();
}

class _NumberEditorState extends State<_NumberEditor> {
  late final Map<String, TextEditingController> _ctls;

  @override
  void initState() {
    super.initState();
    _ctls = {
      for (final e in widget.elements)
        e['name'] as String: TextEditingController(text: '${e['value'] ?? ''}'),
    };
  }

  @override
  void dispose() { for (final c in _ctls.values) { c.dispose(); } super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final e in widget.elements) Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            SizedBox(width: 110, child: Text(e['label'] ?? e['name'],
                style: TextStyle(color: T.muted(context), fontSize: 11), overflow: TextOverflow.ellipsis)),
            Expanded(
              child: TextField(
                controller: _ctls[e['name']],
                enabled: widget.writable,
                keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
              ),
            ),
          ]),
        ),
        if (widget.writable) Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Align(
            alignment: Alignment.centerRight,
            child: PrimaryButton(label: 'SET', small: true, icon: Icons.send,
                onPressed: widget.api == null ? null : () async {
                  try {
                    final values = {for (final entry in _ctls.entries)
                      entry.key: double.tryParse(entry.value.text) ?? 0.0};
                    await widget.api!.indiSet(widget.device, widget.name, values);
                    if (context.mounted) showSnack(context, 'Set'.tr(context));
                  } catch (e) {
                    if (context.mounted) showSnack(context, '${'Errore: '.tr(context)}$e', error: true);
                  }
                }),
          ),
        ),
      ],
    );
  }
}

class _TextEditor extends StatefulWidget {
  final String device, name;
  final List<Map> elements;
  final bool writable;
  final ApiClient? api;
  const _TextEditor({required this.device, required this.name, required this.elements,
    required this.writable, required this.api});
  @override
  State<_TextEditor> createState() => _TextEditorState();
}

class _TextEditorState extends State<_TextEditor> {
  late final Map<String, TextEditingController> _ctls;
  @override
  void initState() {
    super.initState();
    _ctls = {for (final e in widget.elements) e['name'] as String:
      TextEditingController(text: '${e['value'] ?? ''}')};
  }
  @override
  void dispose() { for (final c in _ctls.values) { c.dispose(); } super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final e in widget.elements) Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            SizedBox(width: 110, child: Text(e['label'] ?? e['name'],
                style: TextStyle(color: T.muted(context), fontSize: 11), overflow: TextOverflow.ellipsis)),
            Expanded(
              child: TextField(
                controller: _ctls[e['name']],
                enabled: widget.writable,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
              ),
            ),
          ]),
        ),
        if (widget.writable) Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Align(
            alignment: Alignment.centerRight,
            child: PrimaryButton(label: 'SET', small: true, icon: Icons.send,
                onPressed: widget.api == null ? null : () async {
                  try {
                    final values = {for (final entry in _ctls.entries) entry.key: entry.value.text};
                    await widget.api!.indiSet(widget.device, widget.name, values);
                    if (context.mounted) showSnack(context, 'Set'.tr(context));
                  } catch (e) {
                    if (context.mounted) showSnack(context, '${'Errore: '.tr(context)}$e', error: true);
                  }
                }),
          ),
        ),
      ],
    );
  }
}
