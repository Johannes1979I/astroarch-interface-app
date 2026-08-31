import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/api_client.dart';
import '../i18n/strings.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/transitions.dart';
import '../widgets/common.dart';
import '../services/notification_watcher.dart';
import 'dashboard_screen.dart';
import 'mount_screen.dart';
import 'capture_screen.dart';
import 'guide_screen.dart';
import 'focus_screen.dart';
import 'align_screen.dart';
import 'observatory_screen.dart';
import 'indi_panel_screen.dart';
import 'files_screen.dart';
import 'logs_screen.dart';
import 'live_view_screen.dart';
import 'sky_screen.dart';
import 'session_screen.dart';
import 'activity_log_screen.dart';
import 'connections_screen.dart';
import 'setup_screen.dart';
import 'settings_screen.dart';
import 'analyze_screen.dart';
import 'scheduler_screen.dart';

/// Key globale dello Scaffold di Shell, usata dalle schermate annidate
/// per aprire il drawer (Scaffold.of() trova lo Scaffold locale, non Shell).
final GlobalKey<ScaffoldState> shellScaffoldKey = GlobalKey<ScaffoldState>();

/// Helper per aprire il drawer dalla AppBar di qualsiasi schermata.
void openShellDrawer() => shellScaffoldKey.currentState?.openDrawer();

/// Shell con bottom nav (5 tab) + drawer per le altre sezioni.
class ShellScreen extends StatefulWidget {
  const ShellScreen({super.key});
  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

/// Breakpoints for adapting the app shell.
///
/// Collected here, with names, instead of being scattered across widgets:
/// changing where the app switches shape must cost one line. The values are
/// a reasonable starting point, not a final choice: `rail` sits just above a
/// phone in landscape, `twoPane` just below an 11" iPad in landscape.
class ShellLayout {
  /// Above this width the bottom bar becomes a side navigation rail.
  static const double rail = 700;

  /// Above this width two screens sit side by side.
  static const double twoPane = 1100;

  /// Above this width the rail also shows its labels.
  static const double railExtended = 1400;

  /// Maximum width of the single column on large screens: without this cap
  /// a screen designed for a phone stretches across a whole iPad, with
  /// controls as wide as the display.
  static const double maxSingleColumn = 620;

  const ShellLayout._();
}

/// A destination of the main navigation.
///
/// Declared once and consumed both by the bottom bar and by the side rail,
/// so the two cannot drift apart.
class _Dest {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final Widget screen;
  const _Dest(this.icon, this.selectedIcon, this.label, this.screen);
}

const List<_Dest> _destinations = [
  _Dest(Icons.dashboard_outlined, Icons.dashboard, 'Dash', DashboardScreen()),
  _Dest(Icons.adjust_outlined, Icons.adjust, 'Mount', MountScreen()),
  _Dest(Icons.gps_fixed_outlined, Icons.gps_fixed, 'Align', AlignScreen()),
  _Dest(Icons.camera_alt_outlined, Icons.camera_alt, 'Capture', CaptureScreen()),
  _Dest(Icons.center_focus_strong_outlined, Icons.center_focus_strong, 'Guide',
      GuideScreen()),
];

class _ShellScreenState extends State<ShellScreen> {
  int _idx = 0;

  /// Screen of the second pane, shown only above `twoPane`.
  /// It starts on Capture: next to the dashboard, that is the pair needed
  /// most often during a session.
  int _secondIdx = 3;

  /// The second pane can be closed: on a laptop in landscape a single
  /// column reads better than two narrow ones.
  bool _twoPaneEnabled = true;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    // Banner connessione: mostrato quando la WS di stato NON è connessa.
    final wsDown = s.api != null && s.wsStateLabel != 'connected';

    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final useRail = width >= ShellLayout.rail;
      final canSplit = width >= ShellLayout.twoPane;
      final splitting = canSplit && _twoPaneEnabled;

      return Scaffold(
        key: shellScaffoldKey,
        drawer: const _AppDrawer(),
        body: SafeArea(
          child: Row(children: [
            if (useRail)
              _NavRail(
                index: _idx,
                extended: width >= ShellLayout.railExtended,
                onSelected: _selectPrimary,
              ),
            Expanded(
              child: Column(children: [
                // Watcher invisibile per le notifiche locali (v0.2.44).
                const NotificationWatcher(),
                if (wsDown) _ConnectionBanner(label: s.wsStateLabel),
                Expanded(
                  child: splitting
                      ? Row(children: [
                          Expanded(child: _primaryPane(s)),
                          const VerticalDivider(width: 1, thickness: 1),
                          Expanded(
                            child: _SecondaryPane(
                              index: _secondIdx,
                              primaryIndex: _idx,
                              onSelected: _selectSecondary,
                              onClose: () =>
                                  setState(() => _twoPaneEnabled = false),
                            ),
                          ),
                        ])
                      : _constrain(_primaryPane(s), useRail),
                ),
              ]),
            ),
          ]),
        ),
        // FAB ABORT di emergenza: sempre raggiungibile da tutte le schermate.
        // Apre un bottom-sheet con gli stop critici (sequenza/guida/montatura).
        floatingActionButton: canSplit && !_twoPaneEnabled
            ? _ReopenSplitFab(onPressed: () => setState(() => _twoPaneEnabled = true))
            : _EmergencyStopFab(),
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
        bottomNavigationBar: useRail
            ? null
            : NavigationBar(
                selectedIndex: _idx,
                onDestinationSelected: _selectPrimary,
                destinations: [
                  for (final d in _destinations)
                    NavigationDestination(
                      icon: Icon(d.icon),
                      selectedIcon: Icon(d.selectedIcon),
                      label: d.label.tr(context),
                    ),
                ],
              ),
      );
    });
  }

  /// Picks the screen for the primary pane.
  ///
  /// If that screen is already open in the other pane, the two swap rather
  /// than showing it twice. A duplicate adds nothing to look at and doubles
  /// whatever work the screen does on its own: the Ekos internal-guider
  /// view, for one, asks the bridge for its status every two seconds, and
  /// each of those calls becomes a handful of `qdbus6` processes on the
  /// Raspberry.
  void _selectPrimary(int i) => setState(() {
        if (i == _secondIdx) _secondIdx = _idx;
        _idx = i;
      });

  /// Like `_selectPrimary`, from the second pane's side.
  void _selectSecondary(int i) => setState(() {
        if (i == _idx) _idx = _secondIdx;
        _secondIdx = i;
      });

  /// The active screen, with the themed transition on tab change.
  Widget _primaryPane(AppState s) {
    // v0.2.46: transizione a tema al cambio tab (teletrasporto Star Trek /
    // risucchio Gargantua Interstellar). Istantaneo su Pro/Notte.
    return AnimatedSwitcher(
      duration: ThemedTransitions.durationFor(s.themeMode),
      transitionBuilder: (child, anim) =>
          ThemedTransitions.build(s.themeMode, child, anim),
      // layout: la nuova schermata sopra; evita salti durante lo switch
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [...previous, if (current != null) current],
      ),
      child: KeyedSubtree(
        key: ValueKey(_idx),
        child: _destinations[_idx].screen,
      ),
    );
  }

  /// On large screens the single column keeps a readable width instead of
  /// stretching: the screens are laid out for a phone.
  Widget _constrain(Widget child, bool wide) {
    if (!wide) return child;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: ShellLayout.maxSingleColumn),
        child: child,
      ),
    );
  }
}

/// Side rail: replaces the bottom bar from tablet size upwards.
class _NavRail extends StatelessWidget {
  final int index;
  final bool extended;
  final ValueChanged<int> onSelected;
  const _NavRail({
    required this.index,
    required this.extended,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return NavigationRail(
      selectedIndex: index,
      extended: extended,
      labelType:
          extended ? NavigationRailLabelType.none : NavigationRailLabelType.all,
      onDestinationSelected: onSelected,
      // No menu button here: every screen's AppBar already has one, and
      // two identical icons side by side confuse rather than help.
      destinations: [
        for (final d in _destinations)
          NavigationRailDestination(
            icon: Icon(d.icon),
            selectedIcon: Icon(d.selectedIcon),
            label: Text(d.label.tr(context)),
          ),
      ],
    );
  }
}

/// The second side-by-side pane, with its own screen selector.
///
/// The screens are self-contained widgets reading state from the Provider:
/// two instances coexist and stay in sync on their own, without either of
/// them having to know it is part of a split view.
class _SecondaryPane extends StatelessWidget {
  final int index;

  /// Screen open in the primary pane: its chip here does not open a second
  /// copy, it swaps the two panes, and the icon says so.
  final int primaryIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback onClose;
  const _SecondaryPane({
    required this.index,
    required this.primaryIndex,
    required this.onSelected,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Material(
        color: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (var i = 0; i < _destinations.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Tooltip(
                        message: i == primaryIndex
                            ? 'Scambia i pannelli'.tr(context)
                            : _destinations[i].label.tr(context),
                        child: ChoiceChip(
                          label: Text(_destinations[i].label.tr(context)),
                          avatar: i == primaryIndex
                              ? const Icon(Icons.swap_horiz, size: 16)
                              : null,
                          selected: i == index,
                          onSelected: (_) => onSelected(i),
                        ),
                      ),
                    ),
                ]),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Chiudi pannello'.tr(context),
              onPressed: onClose,
            ),
          ]),
        ),
      ),
      const Divider(height: 1),
      Expanded(
        child: KeyedSubtree(
          key: ValueKey('second_$index'),
          child: _destinations[index].screen,
        ),
      ),
    ]);
  }
}

/// Reopens the second pane after it has been closed.
class _ReopenSplitFab extends StatelessWidget {
  final VoidCallback onPressed;
  const _ReopenSplitFab({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.small(
      onPressed: onPressed,
      tooltip: 'Riapri il secondo pannello'.tr(context),
      child: const Icon(Icons.vertical_split),
    );
  }
}

class _AppDrawer extends StatelessWidget {
  const _AppDrawer();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text.rich(
              TextSpan(children: [
                const TextSpan(text: 'Astroarch ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                TextSpan(text: 'Interface', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: T.accent(context))),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 14),
              child: Text(
                'Zarletti-Osservatorio Jupiter\n${state.host}:${state.port}',
                style: TextStyle(color: T.muted(context), fontSize: 11),
              ),
            ),
            _section(context, 'Connessione'.tr(context)),
            _statusTile(context, 'INDI', state.indiConn),
            _statusTile(context, 'PHD2', state.phd2Conn),
            _statusTile(context, 'WS state'.tr(context), state.wsStateLabel),
            _statusTile(context, 'WS frames'.tr(context), state.wsFramesLabel),
            const SizedBox(height: 8),
            _section(context, 'Moduli'.tr(context)),
            _navTile(context, Icons.dashboard, 'Dashboard'.tr(context), () => Navigator.pop(context)),
            _navTile(context, Icons.center_focus_strong, 'Live View'.tr(context), () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const LiveViewScreen()));
            }),
            _navTile(context, Icons.public, 'Planetario'.tr(context), () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SkyScreen()));
            }),
            _navTile(context, Icons.tune, 'Focus'.tr(context), () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const FocusScreen()));
            }),
            _navTile(context, Icons.cloud_outlined, 'Observatory'.tr(context), () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const ObservatoryScreen()));
            }),
            _navTile(context, Icons.calendar_month, 'Scheduler'.tr(context), () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SchedulerScreen()));
            }),
            _navTile(context, Icons.bookmarks_outlined, 'Setup / Profili'.tr(context), () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SetupScreen()));
            }),
            _navTile(context, Icons.analytics_outlined, 'Analyze'.tr(context), () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const AnalyzeScreen()));
            }),
            _navTile(context, Icons.nightlight, 'Sessione'.tr(context), () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SessionScreen()));
            }),
            const SizedBox(height: 8),
            _section(context, 'Sistema'.tr(context)),
            _navTile(context, Icons.cloud_outlined, '${'Bridge salvate'.tr(context)} (${state.bridges.length})', () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const ConnectionsScreen()));
            }),
            _navTile(context, Icons.settings_input_component, 'INDI Panel'.tr(context), () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const IndiPanelScreen()));
            }),
            _navTile(context, Icons.folder_outlined, 'Files'.tr(context), () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const FilesScreen()));
            }),
            _navTile(context, Icons.terminal, 'INDI Logs'.tr(context), () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const LogsScreen()));
            }),
            _navTile(context, Icons.history, 'Activity Log (chiamate API)'.tr(context), () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const ActivityLogScreen()));
            }),
            _navTile(context, Icons.settings, 'Impostazioni'.tr(context), () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
            }),
            const Divider(),
            _navTile(context, Icons.power_settings_new, 'Disconnetti'.tr(context), () async {
              Navigator.pop(context);
              await state.disconnect();
            }, danger: true),
          ],
        ),
      ),
    );
  }

  Widget _section(BuildContext c, String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
        child: Text(t.toUpperCase(),
            style: TextStyle(fontSize: 10, color: T.muted(c), letterSpacing: 2, fontWeight: FontWeight.w600)),
      );

  Widget _navTile(BuildContext c, IconData i, String t, VoidCallback tap, {bool danger = false}) {
    return ListTile(
      leading: Icon(i, color: danger ? T.err(c) : T.accent(c)),
      title: Text(t, style: TextStyle(color: danger ? T.err(c) : T.text(c), fontSize: 14)),
      onTap: tap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );
  }

  Widget _statusTile(BuildContext c, String name, String state) {
    Color color;
    switch (state) {
      case 'connected':
        color = T.ok(c); break;
      case 'reconnecting':
      case 'connecting':
      case 'pinging':
        color = T.warn(c); break;
      default:
        color = T.muted(c);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(name, style: TextStyle(color: T.muted(c), fontSize: 12)),
          const Spacer(),
          Text(state, style: TextStyle(color: color, fontSize: 11)),
        ],
      ),
    );
  }
}

/// Banner di connessione: appare in cima quando la WS di stato non è
/// connessa (riconnessione in corso / persa). Offre un tap per forzare la
/// riconnessione manuale delle WebSocket.
class _ConnectionBanner extends StatelessWidget {
  final String label;
  const _ConnectionBanner({required this.label});

  @override
  Widget build(BuildContext context) {
    final reconnecting = label == 'connecting' || label == 'reconnecting';
    final color = reconnecting ? T.warn(context) : T.err(context);
    final txt = reconnecting
        ? 'Riconnessione in corso…'.tr(context)
        : 'Connessione persa'.tr(context);
    return Material(
      color: color.withValues(alpha: 0.16),
      child: InkWell(
        onTap: () => context.read<AppState>().reconnectWs(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(children: [
            SizedBox(
              width: 14, height: 14,
              child: reconnecting
                  ? CircularProgressIndicator(strokeWidth: 2, color: color)
                  : Icon(Icons.cloud_off, size: 14, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(txt,
                style: TextStyle(color: T.text(context), fontSize: 12.5))),
            Text('RICONNETTI'.tr(context),
                style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    );
  }
}

/// FAB di STOP di emergenza, persistente in tutte le schermate della shell.
/// Apre un bottom-sheet con gli stop critici. Niente azioni dirette senza
/// scelta esplicita (evita stop accidentali con un tap solo).
class _EmergencyStopFab extends StatelessWidget {
  Future<void> _run(BuildContext c, Future<void> Function() fn, String okMsg) async {
    final s = c.read<AppState>();
    if (s.api == null) return;
    try {
      await fn();
      if (c.mounted) showSnack(c, okMsg);
    } on ApiException catch (e) {
      if (c.mounted) showSnack(c, '${'Errore: '.tr(c)}${e.body}', error: true);
    } catch (e) {
      if (c.mounted) showSnack(c, '${'Errore: '.tr(c)}$e', error: true);
    }
  }

  void _openSheet(BuildContext context) {
    final s = context.read<AppState>();
    showModalBottomSheet(context: context, backgroundColor: T.panel(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (c) => SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(Icons.warning_amber_rounded, color: T.err(c)),
            const SizedBox(width: 8),
            Text('Stop di emergenza'.tr(c), style: TextStyle(
                color: T.text(c), fontWeight: FontWeight.w700, fontSize: 16)),
          ]),
          const SizedBox(height: 4),
          Text('Scegli cosa fermare. Azione immediata.'.tr(c),
              style: TextStyle(color: T.muted(c), fontSize: 12)),
          const SizedBox(height: 14),
          _stopBtn(c, Icons.stop_circle, 'FERMA SEQUENZA'.tr(c),
              () { Navigator.pop(c); _run(c, () => s.api!.captureEkosAbort(), 'Sequenza fermata'.tr(c)); }),
          const SizedBox(height: 8),
          _stopBtn(c, Icons.center_focus_strong, 'STOP GUIDA'.tr(c),
              () { Navigator.pop(c); _run(c, () => s.api!.guideStop(), 'Guida fermata'.tr(c)); }),
          const SizedBox(height: 8),
          _stopBtn(c, Icons.pan_tool, 'STOP MONTATURA'.tr(c),
              () { Navigator.pop(c); _run(c, () => s.api!.mountAbort(), 'Montatura fermata'.tr(c)); }),
          const SizedBox(height: 8),
          _stopBtn(c, Icons.block, 'FERMA TUTTO'.tr(c), () async {
            Navigator.pop(c);
            await _run(c, () => s.api!.captureEkosAbort(), '…');
            await _run(c, () => s.api!.guideStop(), '…');
            await _run(c, () => s.api!.mountAbort(), 'Tutto fermato'.tr(c));
          }, danger: true),
        ]),
      )),
    );
  }

  Widget _stopBtn(BuildContext c, IconData icon, String label, VoidCallback onTap,
      {bool danger = false}) {
    final col = danger ? T.err(c) : T.text(c);
    return Material(
      color: danger ? T.err(c).withValues(alpha: 0.14) : T.panel(c),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: danger ? T.err(c).withValues(alpha: 0.5) : T.line(c)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(children: [
            Icon(icon, color: col, size: 20),
            const SizedBox(width: 12),
            Text(label, style: TextStyle(color: col, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    if (s.api == null) return const SizedBox.shrink();
    return FloatingActionButton.small(
      heroTag: 'emergencyStop',
      backgroundColor: T.err(context),
      foregroundColor: Colors.white,
      tooltip: 'Stop di emergenza'.tr(context),
      onPressed: () => _openSheet(context),
      child: const Icon(Icons.stop),
    );
  }
}
