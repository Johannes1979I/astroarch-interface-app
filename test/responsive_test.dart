// Regole del layout adattivo (lib/widgets/responsive.dart).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:astroarch_interface/widgets/responsive.dart';

Future<void> pumpAt(WidgetTester tester, Size size, Widget child) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
}

void main() {
  group('contentMaxWidth', () {
    test('a phone gets the whole width', () {
      expect(contentMaxWidth(390), 390);
    });
    test('grows in steps with the screen', () {
      expect(contentMaxWidth(800), 760);
      expect(contentMaxWidth(1200), 1040);
      expect(contentMaxWidth(1600), 1280);
      expect(contentMaxWidth(2560), 1600);
    });
    test('forms stay readable on any screen', () {
      expect(contentMaxWidth(2560, ContentKind.form), 720);
      expect(contentMaxWidth(500, ContentKind.form), 500);
    });
  });

  group('adaptivePadding', () {
    test('no extra margin while the content fits', () {
      expect(adaptivePadding(390, const EdgeInsets.all(16)),
          const EdgeInsets.all(16));
    });
    test('centres the content on a wide screen', () {
      final p = adaptivePadding(2560, const EdgeInsets.symmetric(horizontal: 16));
      expect(p.left, p.right);
      // contenuto = 1600 px, padding compreso
      expect(2560 - p.horizontal, closeTo(1600 - 32, 0.01));
    });
  });

  group('AdaptiveGrid.columnsFor', () {
    test('two cards per row on a phone', () {
      expect(AdaptiveGrid.columnsFor(328, count: 4, minTileWidth: 150), 2);
    });
    test('one column on a very narrow screen', () {
      expect(AdaptiveGrid.columnsFor(200, count: 4, minTileWidth: 150), 1);
    });
    test('four cards in a row on a tablet', () {
      expect(AdaptiveGrid.columnsFor(728, count: 4, minTileWidth: 150), 4);
    });
    test('never more columns than cards', () {
      expect(AdaptiveGrid.columnsFor(2000, count: 2, maxColumns: 4), 2);
    });
    test('no orphan: 4 cards in room for 3 become 2+2', () {
      expect(AdaptiveGrid.columnsFor(500, count: 4, minTileWidth: 150), 2);
    });
    test('no orphan: 6 cards in room for 4 become 3+3', () {
      expect(AdaptiveGrid.columnsFor(700, count: 6, minTileWidth: 150), 3);
    });
  });

  testWidgets('AdaptiveGrid lays tiles out with no overflow, big text too',
      (tester) async {
    await pumpAt(
      tester,
      const Size(320, 640),
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
        child: ListView(children: [
          AdaptiveGrid(minTileWidth: 150, children: [
            for (var i = 0; i < 4; i++)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text('Card $i con un testo piuttosto lungo che va a capo'),
                ),
              ),
          ]),
        ]),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(Card), findsNWidgets(4));
  });

  testWidgets('AdaptivePreview never exceeds its share of the height',
      (tester) async {
    await pumpAt(
      tester,
      const Size(2560, 1000),
      ListView(children: const [
        AdaptivePreview(
          aspectRatio: 16 / 9,
          maxHeightFraction: 0.5,
          child: ColoredBox(key: Key('anteprima'), color: Colors.black),
        ),
      ]),
    );
    final box = tester.getSize(find.byKey(const Key('anteprima')));
    expect(box.height, lessThanOrEqualTo(500.0 + 0.01));
    expect(box.width / box.height, closeTo(16 / 9, 0.01));
  });

  testWidgets('AdaptiveColumns: one column on a phone, two on a monitor',
      (tester) async {
    Widget cols() => ListView(children: const [
          AdaptiveColumns(
            left: [SizedBox(key: Key('L'), height: 50)],
            right: [SizedBox(key: Key('R'), height: 50)],
          ),
        ]);
    await pumpAt(tester, const Size(400, 800), cols());
    expect(tester.getTopLeft(find.byKey(const Key('R'))).dy,
        greaterThan(tester.getTopLeft(find.byKey(const Key('L'))).dy));

    await pumpAt(tester, const Size(1600, 800), cols());
    expect(tester.getTopLeft(find.byKey(const Key('R'))).dy,
        tester.getTopLeft(find.byKey(const Key('L'))).dy);
  });
}
