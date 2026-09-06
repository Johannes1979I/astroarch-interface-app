// Checks that the app shell changes shape at the breakpoints declared in
// ShellLayout. The inner screens do not matter here: what is verified is
// which navigation appears and how many panes get composed.
//
// The point is to pin the behaviour down: the breakpoints are design values
// and may well change, but they must not change by accident.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:astroarch_interface/screens/shell_screen.dart';
import 'package:astroarch_interface/state/app_state.dart';

/// Mounts the shell at a given width.
Future<void> pumpShellAt(WidgetTester tester, double width) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(width, 1000);
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: AppState(),
      child: const MaterialApp(home: ShellScreen()),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('below the rail breakpoint: bottom bar, one pane',
      (tester) async {
    await pumpShellAt(tester, ShellLayout.rail - 100);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('above the rail breakpoint: side rail, no bottom bar',
      (tester) async {
    await pumpShellAt(tester, ShellLayout.rail + 100);
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('between rail and twoPane: single column with a capped width',
      (tester) async {
    await pumpShellAt(tester, ShellLayout.twoPane - 100);
    expect(find.byType(NavigationRail), findsOneWidget);
    // The width cap is there: without it the screen would stretch.
    final constrained = tester.widgetList<ConstrainedBox>(
      find.byType(ConstrainedBox),
    );
    expect(
      constrained.any((c) =>
          c.constraints.maxWidth == ShellLayout.maxSingleColumn),
      isTrue,
      reason: 'the single column must be capped at maxSingleColumn',
    );
  });

  testWidgets('above twoPane: two panes side by side', (tester) async {
    await pumpShellAt(tester, ShellLayout.twoPane + 100);
    expect(find.byType(NavigationRail), findsOneWidget);
    // The vertical divider exists only in the two-pane composition.
    expect(find.byType(VerticalDivider), findsOneWidget);
  });

  testWidgets('picking the first pane\'s screen in the second one swaps them',
      (tester) async {
    await pumpShellAt(tester, ShellLayout.twoPane + 100);

    final railBefore =
        tester.widget<NavigationRail>(find.byType(NavigationRail));
    final primaryBefore = railBefore.selectedIndex!;
    final chips = find.byType(ChoiceChip);
    int selectedChip() =>
        tester.widgetList<ChoiceChip>(chips).toList().indexWhere((c) => c.selected);
    final secondBefore = selectedChip();
    expect(secondBefore, isNot(primaryBefore));

    // Asking the second pane for the screen already open in the first does
    // not open a second copy: the two panes swap.
    await tester.tap(chips.at(primaryBefore));
    await tester.pump();

    final railAfter = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(railAfter.selectedIndex, secondBefore);
    expect(selectedChip(), primaryBefore);
  });

  testWidgets('the destinations are the same for bar and rail',
      (tester) async {
    await pumpShellAt(tester, ShellLayout.rail - 100);
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    final barCount = bar.destinations.length;

    await pumpShellAt(tester, ShellLayout.rail + 100);
    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.destinations.length, barCount);
  });
}
