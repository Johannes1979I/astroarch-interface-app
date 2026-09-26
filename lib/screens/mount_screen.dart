import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/api_client.dart';
import '../i18n/strings.dart';
import '../mount/slew_controller.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'mount_remote_screen.dart';
import 'shell_screen.dart';

class MountScreen extends StatefulWidget {
  const MountScreen({super.key});
  @override
  State<MountScreen> createState() => _MountScreenState();
}

class _MountScreenState extends State<MountScreen> {
  final TextEditingController _searchCtl = TextEditingController();
  Map<String, dynamic>? _searchResult;
  bool _searching = false;
  String? _searchErr;
  String? _selectedRate;
  bool _slewing = false;
  // Frecce a schermo: stesso movimento protetto del telecomando, cosi' un
  // dito che scivola via o la rete che cade non lasciano la montatura in moto.
  late final SlewController _slewCtl;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    _slewCtl = SlewController(send: (dir, active, {bool beat = false}) async {
      final api = app.api;
      if (api == null) return;
      await api.mountSlewGuarded(
          dir: dir, active: active, ttlMs: SlewController.ttlMs, beat: beat);
    });
  }

  @override
  void dispose() {
    _slewCtl.dispose();
    _searchCtl.dispose();
    super.dispose();
  }

  Future<void> _safeCall(Future Function() fn, String okMsg) async {
    try {
      await fn();
      if (mounted) showSnack(context, okMsg);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, '${'Errore: '.tr(context)}${e.body}', error: true);
    } catch (e) {
      if (mounted) showSnack(context, '${'Errore: '.tr(context)}$e', error: true);
    }
  }

  Future<void> _search() async {
    final s = context.read<AppState>();
    final name = _searchCtl.text.trim();
    if (name.isEmpty || s.api == null) return;
    setState(() {
      _searching = true;
      _searchErr = null;
      _searchResult = null;
    });
    try {
      _searchResult = await s.api!.simbadSearch(name);
    } on ApiException catch (e) {
      _searchErr = e.status == 404 ? 'Oggetto non trovato'.tr(context) : '${'Errore: '.tr(context)}${e.body}';
    } catch (e) {
      _searchErr = '$e';
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _gotoSearchResult({required String action}) async {
    final s = context.read<AppState>();
    final r = _searchResult;
    if (r == null) return;
    final ra = (r['ra_hours'] as num).toDouble();
    final dec = (r['dec_deg'] as num).toDouble();
    await _safeCall(
      () => s.api!.mountGoto(ra, dec, action: action),
      action == 'sync' ? '${'Sync su '.tr(context)}${r['name']}' : '${'GoTo '.tr(context)}${r['name']}',
    );
  }

  void _slew(String dir) {
    setState(() => _slewing = true);
    _slewCtl.press(dir);
  }

  void _slewStop(String dir) {
    _slewCtl.release(dir);
    setState(() => _slewing = _slewCtl.moving);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final m = s.mountDevice();
    final coord = m == null ? null : s.prop(m, 'EQUATORIAL_EOD_COORD');
    final track = m == null ? null : s.prop(m, 'TELESCOPE_TRACK_STATE');
    final mode = m == null ? null : s.prop(m, 'TELESCOPE_TRACK_MODE');
    final park = m == null ? null : s.prop(m, 'TELESCOPE_PARK');
    final pier = m == null ? null : s.prop(m, 'TELESCOPE_PIER_SIDE');
    final rates = m == null ? null : s.prop(m, 'TELESCOPE_SLEW_RATE');

    final isTracking = (propValue(track, 'TRACK_ON') == true);
    final isParked = (propValue(park, 'PARK') == true);
    final selectedMode = _selectedSwitch(mode);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
            icon: const Icon(Icons.menu),
            onPressed: openShellDrawer),
        title: Text(m == null ? 'Mount'.tr(context) : '${'Mount'.tr(context)} · $m'),
      ),
      body: m == null
          ? Center(child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Nessun mount connesso ad Ekos.'.tr(context),
                  textAlign: TextAlign.center, style: TextStyle(color: T.muted(context))),
            ))
          : ListView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 80),
              children: [
                _coordsCard(coord),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: _badgeBox('PIER', _pierLabel(pier))),
                  const SizedBox(width: 8),
                  Expanded(child: _badgeBox('STATE', coord?['state'] ?? '—')),
                ]),
                SectionLabel('Cerca oggetto (SIMBAD)'.tr(context)),
                _searchBar(),
                if (_searchResult != null) _searchResultCard(),
                if (_searchErr != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(_searchErr!,
                        style: TextStyle(color: T.err(context), fontSize: 12)),
                  ),
                SectionLabel('GoTo manuale RA/Dec'.tr(context)),
                _gotoForm(),
                SectionLabel('Slew manuale'.tr(context)),
                Center(child: _joypad()),
                const SizedBox(height: 8),
                if (rates != null) Center(child: _rateChips(rates)),
                const SizedBox(height: 10),
                GhostButton(
                  label: 'TELECOMANDO (CONTROLLER)'.tr(context),
                  icon: Icons.sports_esports,
                  onPressed: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => const MountRemoteScreen())),
                ),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: GhostButton(
                    label: isParked ? 'UNPARK' : 'PARK',
                    onPressed: () => _safeCall(
                      () => isParked ? s.api!.mountUnpark() : s.api!.mountPark(),
                      isParked ? 'Unparking…'.tr(context) : 'Parking…'.tr(context)),
                  )),
                  const SizedBox(width: 6),
                  Expanded(child: GhostButton(label: 'SYNC', onPressed: _syncToCurrent)),
                  const SizedBox(width: 6),
                  Expanded(child: GhostButton(label: 'STOP', danger: true,
                    onPressed: () => _safeCall(() => s.api!.mountAbort(), 'Abort'))),
                ]),
                SectionLabel('Tracking'.tr(context)),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  ChipToggle(label: 'Sidereal'.tr(context),
                    selected: selectedMode == 'TRACK_SIDEREAL' && isTracking,
                    onTap: () => _safeCall(
                      () => s.api!.mountTrack(on: true, mode: 'TRACK_SIDEREAL'), 'Sidereal'.tr(context))),
                  ChipToggle(label: 'Lunar'.tr(context),
                    selected: selectedMode == 'TRACK_LUNAR' && isTracking,
                    onTap: () => _safeCall(
                      () => s.api!.mountTrack(on: true, mode: 'TRACK_LUNAR'), 'Lunar'.tr(context))),
                  ChipToggle(label: 'Solar'.tr(context),
                    selected: selectedMode == 'TRACK_SOLAR' && isTracking,
                    onTap: () => _safeCall(
                      () => s.api!.mountTrack(on: true, mode: 'TRACK_SOLAR'), 'Solar'.tr(context))),
                  ChipToggle(label: 'Off'.tr(context),
                    selected: !isTracking,
                    onTap: () => _safeCall(
                      () => s.api!.mountTrack(on: false), 'Tracking off'.tr(context))),
                ]),
              ],
            ),
    );
  }

  Widget _searchBar() {
    return Row(children: [
      Expanded(
        child: TextField(
          controller: _searchCtl,
          onSubmitted: (_) => _search(),
          decoration: InputDecoration(
            hintText: 'M 31, NGC 7000, Vega…'.tr(context),
            prefixIcon: const Icon(Icons.search, size: 18),
            isDense: true,
          ),
        ),
      ),
      const SizedBox(width: 8),
      SizedBox(
        height: 44,
        child: ElevatedButton(
          onPressed: _searching ? null : _search,
          child: _searching
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
              : Text('CERCA'.tr(context)),
        ),
      ),
    ]);
  }

  Widget _searchResultCard() {
    final r = _searchResult!;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: T.panel(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: T.accent(context).withValues(alpha: 0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.gps_fixed, color: T.accent(context), size: 16),
          const SizedBox(width: 6),
          Text(r['name'].toString(), style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 6),
        Text('RA  ${r['ra_str']}',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
        Text('Dec ${r['dec_str']}',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: PrimaryButton(label: 'GOTO + TRACK', icon: Icons.gps_fixed,
              onPressed: () => _gotoSearchResult(action: 'track'))),
          const SizedBox(width: 6),
          Expanded(child: GhostButton(label: 'SLEW', icon: Icons.send,
              onPressed: () => _gotoSearchResult(action: 'slew'))),
          const SizedBox(width: 6),
          Expanded(child: GhostButton(label: 'SYNC',
              onPressed: () => _gotoSearchResult(action: 'sync'))),
        ]),
      ]),
    );
  }

  Widget _coordsCard(Map<String, dynamic>? coord) {
    final ra = (propValue(coord, 'RA') as num?)?.toDouble();
    final dec = (propValue(coord, 'DEC') as num?)?.toDouble();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: T.panel(context), borderRadius: BorderRadius.circular(14),
        border: Border.all(color: T.line(context)),
      ),
      child: Row(children: [
        Expanded(child: _coordCol('RA', ra == null ? '—' : _hms(ra))),
        Expanded(child: _coordCol('Dec', dec == null ? '—' : _dms(dec))),
      ]),
    );
  }

  Widget _coordCol(String label, String val) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: TextStyle(color: T.muted(context), fontSize: 10, letterSpacing: 1.4)),
          const SizedBox(height: 4),
          Text(val, style: const TextStyle(fontSize: 17, fontFamily: 'monospace', fontWeight: FontWeight.w600)),
        ],
      );

  Widget _badgeBox(String l, String v) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: T.panel(context), borderRadius: BorderRadius.circular(10),
          border: Border.all(color: T.line(context)),
        ),
        child: Row(children: [
          Text(l, style: TextStyle(color: T.muted(context), fontSize: 10, letterSpacing: 1.2)),
          const Spacer(),
          Text(v, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        ]),
      );

  Widget _gotoForm() {
    final raCtl = TextEditingController();
    final decCtl = TextEditingController();
    return Column(children: [
      Row(children: [
        Expanded(child: TextField(
          controller: raCtl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: 'RA (h)'.tr(context), hintText: '0.7178', isDense: true),
        )),
        const SizedBox(width: 8),
        Expanded(child: TextField(
          controller: decCtl,
          keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
          decoration: InputDecoration(labelText: 'Dec (°)'.tr(context), hintText: '+41.269', isDense: true),
        )),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: GhostButton(label: 'GOTO', icon: Icons.gps_fixed,
            onPressed: () => _doGoto(raCtl.text, decCtl.text, 'track'))),
        const SizedBox(width: 6),
        Expanded(child: GhostButton(label: 'SLEW', icon: Icons.send,
            onPressed: () => _doGoto(raCtl.text, decCtl.text, 'slew'))),
      ]),
    ]);
  }

  Future<void> _doGoto(String raT, String decT, String action) async {
    final ra = double.tryParse(raT);
    final dec = double.tryParse(decT);
    if (ra == null || dec == null) {
      showSnack(context, 'RA/Dec non valido'.tr(context), error: true);
      return;
    }
    final s = context.read<AppState>();
    await _safeCall(() => s.api!.mountGoto(ra, dec, action: action),
        '${action.toUpperCase()}: ${ra}h ${dec}°');
  }

  Future<void> _syncToCurrent() async {
    final s = context.read<AppState>();
    final m = s.mountDevice();
    final coord = m == null ? null : s.prop(m, 'EQUATORIAL_EOD_COORD');
    final ra = (propValue(coord, 'RA') as num?)?.toDouble();
    final dec = (propValue(coord, 'DEC') as num?)?.toDouble();
    if (ra == null || dec == null) return;
    await _safeCall(() => s.api!.mountGoto(ra, dec, action: 'sync'), 'Sync');
  }

  Color get _arrowBg => Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF1A212D) : const Color(0xFF1F0A0A);

  Widget _arrow({double? top, double? bottom, double? left, double? right,
      required String label, required String dir}) {
    return Positioned(
      top: top, bottom: bottom, left: left, right: right,
      child: GestureDetector(
        onTapDown: (_) => _slew(dir),
        onTapCancel: () => _slewStop(dir),
        onTapUp: (_) => _slewStop(dir),
        child: Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
            color: _slewing ? T.accent(context).withValues(alpha: 0.15) : _arrowBg,
            border: Border.all(color: T.line(context)),
            borderRadius: BorderRadius.circular(11),
          ),
          alignment: Alignment.center,
          child: Text(label, style: TextStyle(color: T.text(context), fontSize: 16)),
        ),
      ),
    );
  }

  Widget _joypad() {
    return SizedBox(width: 200, height: 200, child: Stack(children: [
      Container(decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [_arrowBg, const Color(0xFF0C1220)]),
        border: Border.all(color: T.line(context)),
      )),
      _arrow(top: 6, left: 80, label: '▲', dir: 'N'),
      _arrow(bottom: 6, left: 80, label: '▼', dir: 'S'),
      _arrow(left: 6, top: 80, label: '◀', dir: 'W'),
      _arrow(right: 6, top: 80, label: '▶', dir: 'E'),
      Center(child: Container(
        width: 56, height: 56,
        decoration: BoxDecoration(
          color: T.panel(context), shape: BoxShape.circle,
          border: Border.all(color: T.line(context)),
        ),
        child: Center(child: Text(_selectedRate ?? '·',
            style: TextStyle(color: T.muted(context), fontSize: 11))),
      )),
    ]));
  }

  Widget _rateChips(Map<String, dynamic> rates) {
    final elements = (rates['elements'] as List? ?? []).cast<Map>();
    return Wrap(spacing: 6, runSpacing: 6, children: elements.map((e) {
      final label = (e['label'] ?? e['name']) as String;
      final selected = e['value'] == true;
      if (selected && _selectedRate != label) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _selectedRate = label);
        });
      }
      return ChipToggle(
        label: label, selected: selected,
        onTap: () async {
          final s = context.read<AppState>();
          await _safeCall(() => s.api!.mountSlewRate(e['name'] as String), 'Rate ${e['name']}');
        },
      );
    }).toList());
  }

  String? _selectedSwitch(Map<String, dynamic>? prop) {
    if (prop == null) return null;
    for (final e in (prop['elements'] as List? ?? [])) {
      if (e['value'] == true) return e['name'];
    }
    return null;
  }

  String _pierLabel(Map<String, dynamic>? prop) {
    final w = propValue(prop, 'PIER_WEST');
    final e = propValue(prop, 'PIER_EAST');
    if (w == true) return 'West';
    if (e == true) return 'East';
    return '—';
  }

  String _hms(double hours) {
    final h = hours.floor();
    final m = ((hours - h) * 60).floor();
    final s = (((hours - h) * 60 - m) * 60).round();
    return '${h.toString().padLeft(2,'0')}h ${m.toString().padLeft(2,'0')}m ${s.toString().padLeft(2,'0')}s';
  }

  String _dms(double deg) {
    final sign = deg < 0 ? '-' : '+';
    final a = deg.abs();
    final d = a.floor();
    final m = ((a - d) * 60).floor();
    final s = (((a - d) * 60 - m) * 60).round();
    return '$sign${d.toString().padLeft(2,'0')}° ${m.toString().padLeft(2,'0')}′ ${s.toString().padLeft(2,'0')}″';
  }
}
