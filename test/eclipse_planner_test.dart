import 'package:flutter_test/flutter_test.dart';
import 'package:astroarch_interface/eclipse/eclipse_optimizer.dart';
import 'package:astroarch_interface/eclipse/eclipse_planner.dart';

void main() {
  // Setup di test: ToupTek 2600 (CMOS) su un rifrattore f/5.5, 400mm.
  const cam = CameraSpec(
    type: 'cmos',
    unityGain: 100,
    sensor: 'IMX571',
    manufacturer: 'ToupTek',
    pixelSize: 3.76,
  );
  const scope = TelescopeSpec(fRatio: 5.5, focalLength: 400);

  final allFeatures = {
    EclipseFeature.baily,
    EclipseFeature.chromosphere,
    EclipseFeature.prominences,
    EclipseFeature.innerCorona,
    EclipseFeature.midCorona,
    EclipseFeature.outerCorona,
  };

  EclipseContacts contactsWithTotality(int seconds) {
    final c2 = DateTime(2027, 8, 2, 11, 0, 0);
    return EclipseContacts(c2: c2, c3: c2.add(Duration(seconds: seconds)));
  }

  group('ExposureOptimizer', () {
    test('scala i bracket verso tempi più corti a f/5.5 vs f/10 rif', () {
      final opt = ExposureOptimizer();
      final ref = opt.optimizedExposures(EclipseFeature.outerCorona);
      final scaled = opt.optimizedExposures(EclipseFeature.outerCorona,
          scope: scope, cam: cam, gain: 100);
      expect(ref, isNotEmpty);
      expect(scaled, isNotEmpty);
      // f/5.5 raccoglie più luce di f/10 → esposizioni più corte in media.
      final avgRef = ref.reduce((a, b) => a + b) / ref.length;
      final avgScaled = scaled.reduce((a, b) => a + b) / scaled.length;
      expect(avgScaled, lessThan(avgRef));
    });

    test('formatExposure', () {
      expect(formatExposure(1 / 1000), '1/1000');
      expect(formatExposure(2), '2s');
      expect(formatExposure(0.5), '1/2');
    });
  });

  group('EclipsePlanner budget-tempo', () {
    test('totalità lunga (240s): tiene tutti i blocchi selezionati', () {
      final planner = EclipsePlanner();
      final plan = planner.build(
        features: allFeatures,
        contacts: contactsWithTotality(240),
        scope: scope,
        cam: cam,
        gain: 100,
      );
      expect(plan.fits, isTrue);
      // Baily bookend (C2 + C3) + 5 feature = 7 blocchi.
      expect(plan.totalityBlocks.length, 7);
      expect(plan.overrunSeconds, 0);
      expect(plan.totalityFrames, greaterThan(0));
    });

    test('totalità cortissima (25s): riduce ma rientra e NON elimina Baily', () {
      final planner = EclipsePlanner();
      final plan = planner.build(
        features: allFeatures,
        contacts: contactsWithTotality(25),
        scope: scope,
        cam: cam,
        gain: 100,
      );
      expect(plan.fits, isTrue, reason: 'deve rientrare nel budget');
      expect(plan.adjustments, isNotEmpty, reason: 'deve aver ridotto qualcosa');
      // Baily (priorità 1) deve sopravvivere ad entrambi i bordi.
      final baily = plan.totalityBlocks
          .where((b) => b.feature == EclipseFeature.baily)
          .toList();
      expect(baily.length, 2, reason: 'Baily C2 e C3 mai eliminate');
      for (final b in baily) {
        expect(b.exposures, isNotEmpty);
      }
    });

    test('fase parziale è fuori dal budget totalità', () {
      final planner = EclipsePlanner();
      final plan = planner.build(
        features: {EclipseFeature.partial, EclipseFeature.outerCorona, EclipseFeature.baily},
        contacts: contactsWithTotality(120),
        scope: scope,
        cam: cam,
        gain: 100,
      );
      expect(plan.partialBlocks.length, 1);
      expect(plan.partialBlocks.first.withFilter, isTrue);
      // I blocchi parziali non contano nei frame di totalità.
      expect(plan.totalityBlocks.every((b) => !b.withFilter), isTrue);
    });

    test('senza contatti: nessun budget, tiene tutto', () {
      final planner = EclipsePlanner();
      final plan = planner.build(
        features: allFeatures,
        contacts: const EclipseContacts(),
        scope: scope,
        cam: cam,
        gain: 100,
      );
      expect(plan.totalityBudget, isNull);
      expect(plan.fits, isTrue);
      expect(plan.adjustments, isEmpty);
    });

    test('massimizza scatti: riempie il budget, più frame del fisso, Baily capped', () {
      final planner = EclipsePlanner();
      final fixed = planner.build(
        features: allFeatures,
        contacts: contactsWithTotality(180),
        scope: scope, cam: cam, gain: 100, shotsPerExposure: 1,
      );
      final maxed = planner.build(
        features: allFeatures,
        contacts: contactsWithTotality(180),
        scope: scope, cam: cam, gain: 100, maximizeShots: true,
      );
      expect(maxed.fits, isTrue, reason: 'deve stare nel budget');
      expect(maxed.totalityFrames, greaterThan(fixed.totalityFrames),
          reason: 'più frame rispetto a 1 scatto fisso');
      // Baily resta limitata (fenomeno transitorio).
      for (final b in maxed.totalityBlocks
          .where((b) => b.feature == EclipseFeature.baily)) {
        expect(b.shots, lessThanOrEqualTo(2));
      }
    });
  });
}
