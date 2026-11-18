// Checks that the app shell changes shape at the breakpoints declared in
// ShellLayout. The inner screens do not matter here: what is verified is
// which navigation appears and how many panes get composed.
//
// The point is to pin the behaviour down: the breakpoints are design values
// and may well change, but they must not change by accident.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:astroarch_interface/screens/dashboard_screen.dart';
import 'package:astroarch_interface/screens/shell_screen.dart';
import 'package:astroarch_interface/state/app_state.dart';

/// Mounts the shell at a given width.
Future<void> pumpShellAt(WidgetTester tester, double width,
    {double height = 1000}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: AppState(),
      child: const MaterialApp(home: ShellScreen()),
    ),
  );
  await tester.pump();
}


/// Opens the second pane the way a user does: by tapping its FAB.
///
/// The pane is opt-in, not on by default — two panes mean two screens
/// polling the Raspberry at once, and nobody should get that without
/// asking. So a test about the two-pane composition has to open it first.
Future<void> openSecondPane(WidgetTester tester) async {
  final fab = find.byIcon(Icons.vertical_split);
  expect(fab, findsOneWidget,
      reason: 'the button that opens the second pane must be reachable');
  await tester.tap(fab);
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

  testWidgets('between rail and twoPane: the screen fills the pane',
      (tester) async {
    // Until 0.10.1 the shell capped every screen at 620 px, and on a monitor
    // the dashboard was a phone-wide strip in the middle of nowhere. Now the
    // pane is the screen's to fill: the content width is decided inside it
    // by lib/widgets/responsive.dart.
    await pumpShellAt(tester, ShellLayout.twoPane - 100);
    expect(find.byType(NavigationRail), findsOneWidget);
    final railW = tester.getSize(find.byType(NavigationRail)).width;
    final screenW = tester.getSize(find.byType(DashboardScreen)).width;
    expect(screenW, closeTo(ShellLayout.twoPane - 100 - railW, 1.0),
        reason: 'no cap: the screen spans the whole pane next to the rail');
  });

  testWidgets('a phone in landscape keeps the bottom bar', (tester) async {
    // 800 x 360: wide enough for the rail, too short for five labelled
    // destinations in a column.
    await pumpShellAt(tester, 800, height: 360);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final size in const [
    Size(320, 568), Size(360, 640), Size(412, 915), // phones
    Size(800, 360),                                 // phone, landscape
    Size(768, 1024), Size(1024, 768),               // tablets
    Size(1280, 800), Size(1920, 1080), Size(2560, 1440), // monitors
  ]) {
    testWidgets('no overflow at ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
      await pumpShellAt(tester, size.width, height: size.height);
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull,
          reason: 'the dashboard must lay out without overflow');
    });
  }

  testWidgets('above twoPane: two panes side by side', (tester) async {
    await pumpShellAt(tester, ShellLayout.twoPane + 100);
    expect(find.byType(NavigationRail), findsOneWidget);
    // One column until asked: the divider appears only once the pane is open.
    expect(find.byType(VerticalDivider), findsNothing);
    await openSecondPane(tester);
    // The vertical divider exists only in the two-pane composition.
    expect(find.byType(VerticalDivider), findsOneWidget);
  });

  testWidgets('picking the first pane\'s screen in the second one swaps them',
      (tester) async {
    await pumpShellAt(tester, ShellLayout.twoPane + 100);
    await openSecondPane(tester);

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

  testWidgets('closing the second pane does not remove the emergency stop',
      (tester) async {
    // Regression: on a wide window with the second pane closed, the abort FAB
    // used to be *replaced* by the button that reopens the pane. It is the one
    // control in this app that may never disappear, so the reopen button has
    // to be *added* to the slot, not swapped into it.
    //
    // Counted on the slot rather than looked up by icon on purpose: the abort
    // button hides itself when no bridge is connected, which is the state a
    // freshly built AppState is in, so an icon finder would pass here for the
    // wrong reason.
    Column fabSlot() => tester
        .widget<Scaffold>(find.byType(Scaffold).first)
        .floatingActionButton! as Column;

    await pumpShellAt(tester, ShellLayout.twoPane + 100);
    final closed = fabSlot().children;
    // reopen button, the spacer between them, emergency stop.
    expect(closed.length, 3,
        reason: 'pane closed: reopen button AND emergency stop');

    await openSecondPane(tester);
    final open = fabSlot().children;
    expect(open.length, 1, reason: 'pane open: only the emergency stop');
    // The stop is the last child either way: it never gets swapped out.
    expect(closed.last.runtimeType, open.last.runtimeType);
  });
}
