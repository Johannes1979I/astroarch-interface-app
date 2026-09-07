import 'package:flutter/material.dart';
import '../i18n/strings.dart';
import '../theme/app_theme.dart';
import 'align/plate_solve_tab.dart';
import 'align/polar_align_tab.dart';
import 'shell_screen.dart';

/// Align: 2 tab (Plate Solve + Polar Align) accessibili dalla bottom nav
/// tra Mount e Capture.
class AlignScreen extends StatefulWidget {
  const AlignScreen({super.key});
  @override
  State<AlignScreen> createState() => _AlignScreenState();
}

class _AlignScreenState extends State<AlignScreen> with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Align'.tr(context)),
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: openShellDrawer,
        ),
        bottom: TabBar(
          controller: _tab,
          indicatorColor: T.accent(context),
          labelColor: T.accent(context),
          unselectedLabelColor: T.muted(context),
          tabs: [
            Tab(icon: const Icon(Icons.gps_fixed, size: 18), text: 'PLATE SOLVE'.tr(context)),
            Tab(icon: const Icon(Icons.explore, size: 18), text: 'POLAR ALIGN'.tr(context)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: const [
          PlateSolveTab(),
          PolarAlignTab(),
        ],
      ),
    );
  }
}
