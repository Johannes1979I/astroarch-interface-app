import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../i18n/strings.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});
  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  Map<String, dynamic>? _profiles;
  Map<String, dynamic>? _drivers;
  bool _loading = true;

  @override
  void initState() { super.initState(); _refresh(); }

  Future<void> _refresh() async {
    final s = context.read<AppState>();
    if (s.api == null) return;
    setState(() => _loading = true);
    try {
      _profiles = await s.api!.setupProfiles();
      _drivers = await s.api!.setupActiveDrivers();
    } catch (e) {
      if (mounted) showSnack(context, '${'Errore: '.tr(context)}$e', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleDriver(AppState s, String name, bool currentlyConnected) async {
    try {
      if (currentlyConnected) {
        await s.api!.indiDisconnect(name);
      } else {
        await s.api!.indiConnect(name);
      }
      await Future.delayed(const Duration(seconds: 1));
      await s.refreshSnapshot();
      _refresh();
    } catch (e) {
      if (mounted) showSnack(context, '${'Errore: '.tr(context)}$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final profiles = (_profiles?['profiles'] as List? ?? []);
    final drivers = (_drivers?['drivers'] as List? ?? []);
    return Scaffold(
      appBar: AppBar(
        title: Text('Setup · Profili'.tr(context)),
        actions: [IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh))],
      ),
      body: _loading && _profiles == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 80), children: [
                SectionLabel('Profili Ekos disponibili'.tr(context)),
                if (profiles.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text('Nessun profilo letto da Ekos.\nLo switch profili richiede DBus Ekos (avvio futuro).'.tr(context),
                        style: TextStyle(color: T.muted(context), fontSize: 12)),
                  )
                else for (final p in profiles)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: T.panel(context), borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: T.line(context)),
                    ),
                    child: Row(children: [
                      Icon(Icons.bookmarks_outlined, color: T.accent(context), size: 16),
                      const SizedBox(width: 8),
                      Text(p['name'] ?? 'profilo',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ]),
                  ),
                SectionLabel('Driver INDI attivi (toggle)'.tr(context)),
                if (drivers.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text('Nessun driver caricato'.tr(context),
                        style: TextStyle(color: T.muted(context))),
                  )
                else for (final d in drivers)
                  _driverTile(s, d),
              ]),
            ),
    );
  }

  Widget _driverTile(AppState s, Map d) {
    final connected = d['connected'] == true;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      decoration: BoxDecoration(
        color: T.panel(context), borderRadius: BorderRadius.circular(10),
        border: Border.all(color: T.line(context)),
      ),
      child: Row(children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(
          color: connected ? T.ok(context) : T.muted(context),
          shape: BoxShape.circle,
        )),
        const SizedBox(width: 10),
        Expanded(child: Text(d['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600))),
        TextButton(
          onPressed: () => _toggleDriver(s, d['name'], connected),
          child: Text(connected ? 'DISCONNECT'.tr(context) : 'CONNECT'.tr(context),
              style: TextStyle(color: connected ? T.muted(context) : T.ok(context),
                  fontWeight: FontWeight.w700, fontSize: 11)),
        ),
      ]),
    );
  }
}
