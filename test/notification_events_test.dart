// Alerts arriving from the bridge over the state WebSocket.
//
// The behaviour worth pinning down is what the app does with the event, not
// the socket plumbing: an alert must be shown, must survive being dismissed
// (it stays in the history), and must not pile up without bound.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:astroarch_interface/state/app_state.dart';
import 'package:astroarch_interface/widgets/notification_banner.dart';

Map<String, dynamic> event({
  String title = 'KStars',
  String message = 'process gone',
  String level = 'error',
  String source = 'astro_monitor',
  double? ts,
}) =>
    {
      'type': 'notification',
      'title': title,
      'message': message,
      'level': level,
      'source': source,
      if (ts != null) 'ts': ts,
    };

void main() {
  test('an alert is stored and becomes the pending banner', () {
    final s = AppState();
    s.handleNotificationEvent(event());

    expect(s.notifications, hasLength(1));
    expect(s.pendingNotification?['message'], 'process gone');
    expect(s.pendingNotification?['level'], 'error');
    expect(s.unseenNotifications, 1);
  });

  test('dismissing hides the banner but keeps the history', () {
    final s = AppState();
    s.handleNotificationEvent(event());
    s.dismissNotification();

    expect(s.pendingNotification, isNull);
    expect(s.notifications, hasLength(1),
        reason: 'a dismissed alert must stay findable');
  });

  test('an unknown level falls back to info', () {
    final s = AppState();
    s.handleNotificationEvent(event(level: 'catastrophic'));
    expect(s.pendingNotification?['level'], 'info');
  });

  test('an event with neither title nor message is ignored', () {
    final s = AppState();
    s.handleNotificationEvent(event(title: '', message: ''));
    expect(s.notifications, isEmpty);
    expect(s.pendingNotification, isNull);
  });

  test('the history is capped', () {
    final s = AppState();
    for (var i = 0; i < 60; i++) {
      s.handleNotificationEvent(event(message: 'alert $i'));
    }
    expect(s.notifications.length, lessThanOrEqualTo(50));
    expect(s.notifications.last['message'], 'alert 59',
        reason: 'the newest one must survive the cap');
  });

  testWidgets('the banner shows the alert and closes on demand',
      (tester) async {
    final s = AppState();
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: s,
        child: const MaterialApp(
          home: Scaffold(body: NotificationBanner()),
        ),
      ),
    );
    // Nothing to show: the banner takes up no room at all.
    expect(find.byType(IconButton), findsNothing);

    s.handleNotificationEvent(event(message: 'star lost', level: 'warning'));
    await tester.pump();
    expect(find.text('star lost'), findsOneWidget);
    expect(find.text('astro_monitor'), findsOneWidget);

    await tester.tap(find.byType(IconButton));
    await tester.pump();
    expect(find.text('star lost'), findsNothing);
  });
}
