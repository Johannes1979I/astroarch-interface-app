import 'dart:math' as math;

/// Ottimizzatore esposizioni per l'eclissi — port fedele in Dart del modulo
/// `exposure-optimizer.js` di Eclipse Commander.
///
/// Modello di Fred Espenak (NASA/GSFC): bracket di riferimento per **f/10, ISO 100**
/// scalati sull'equipment reale con la formula
///   t_reale = t_rif × (f_reale / f_rif)² × (ISO_rif / ISO_efficace)
/// Per le CMOS l'ISO efficace è derivato dal gain rispetto all'unity gain.
///
/// È il "cervello" di pianificazione in-app (Fase 2): gira offline, senza bridge.

/// Fasi/feature fotografabili durante l'eclissi.
enum EclipseFeature {
  partial,
  baily,
  chromosphere,
  prominences,
  innerCorona,
  midCorona,
  outerCorona,
  totality,
}

extension EclipseFeatureX on EclipseFeature {
  /// Chiave usata nelle tabelle di riferimento (compatibile con Eclipse Commander).
  String get key => switch (this) {
        EclipseFeature.partial => 'partial',
        EclipseFeature.baily => 'baily',
        EclipseFeature.chromosphere => 'chromosphere',
        EclipseFeature.prominences => 'prominences',
        EclipseFeature.innerCorona => 'inner-corona',
        EclipseFeature.midCorona => 'mid-corona',
        EclipseFeature.outerCorona => 'outer-corona',
        EclipseFeature.totality => 'totality',
      };

  /// Etichetta in italiano per la UI.
  String get labelIt => switch (this) {
        EclipseFeature.partial => 'Parziale (con filtro)',
        EclipseFeature.baily => 'Perle di Baily / Diamante',
        EclipseFeature.chromosphere => 'Cromosfera',
        EclipseFeature.prominences => 'Protuberanze',
        EclipseFeature.innerCorona => 'Corona interna',
        EclipseFeature.midCorona => 'Corona media',
        EclipseFeature.outerCorona => 'Corona esterna',
        EclipseFeature.totality => 'Totalità (HDR completo)',
      };

  /// true se la feature avviene DURANTE la totalità (senza filtro).
  bool get isTotalityFeature => switch (this) {
        EclipseFeature.baily ||
        EclipseFeature.chromosphere ||
        EclipseFeature.prominences ||
        EclipseFeature.innerCorona ||
        EclipseFeature.midCorona ||
        EclipseFeature.outerCorona ||
        EclipseFeature.totality =>
          true,
        EclipseFeature.partial => false,
      };
}

/// Specifica minima della camera per il calcolo fotometrico.
class CameraSpec {
  final String type; // 'cmos' | 'dslr'
  final double? unityGain; // gain al quale la camera ha ~unity gain
  final String sensor; // es. 'IMX571' (per rilevare BSI)
  final String manufacturer; // es. 'ZWO', 'QHY', 'ToupTek'
  final double? pixelSize; // micron (per il limite anti-trailing)

  const CameraSpec({
    this.type = 'cmos',
    this.unityGain,
    this.sensor = '',
    this.manufacturer = '',
    this.pixelSize,
  });
}

/// Specifica minima del telescopio/ottica.
class TelescopeSpec {
  final double fRatio; // rapporto focale (es. 4, 10)
  final double focalLength; // mm

  const TelescopeSpec({required this.fRatio, required this.focalLength});
}

/// Ottimizzatore esposizioni. Stateless: costruiscilo una volta e riusalo.
class ExposureOptimizer {
  static const double refFRatio = 10;
  static const double refIso = 100;

  /// Bracket di riferimento (secondi) per f/10, ISO 100 — guida Espenak.
  static final Map<String, List<double>> referenceBrackets = {
    'partial': [1 / 1000, 1 / 500, 1 / 250],
    'baily': [1 / 4000, 1 / 2000, 1 / 1000, 1 / 500],
    'chromosphere': [1 / 2000, 1 / 1000, 1 / 500, 1 / 250],
    'prominences': [1 / 500, 1 / 250, 1 / 125, 1 / 60],
    'inner-corona': [1 / 1000, 1 / 500, 1 / 250, 1 / 125, 1 / 60, 1 / 30],
    'mid-corona': [1 / 60, 1 / 30, 1 / 15, 1 / 8, 1 / 4, 1 / 2],
    'outer-corona': [1 / 4, 1 / 2, 1, 2, 4],
    'totality': [
      1 / 2000, 1 / 1000, 1 / 500, 1 / 250, 1 / 125, 1 / 60, 1 / 30,
      1 / 15, 1 / 8, 1 / 4, 1 / 2, 1, 2, 4,
    ],
  };

  /// Tempi di scatto standard reali, per arrotondare i valori calcolati.
  static final List<double> standardShutters = [
    1 / 8000, 1 / 6400, 1 / 5000, 1 / 4000, 1 / 3200, 1 / 2500, 1 / 2000, 1 / 1600,
    1 / 1250, 1 / 1000, 1 / 800, 1 / 640, 1 / 500, 1 / 400, 1 / 320, 1 / 250,
    1 / 200, 1 / 160, 1 / 125, 1 / 100, 1 / 80, 1 / 60, 1 / 50, 1 / 40,
    1 / 30, 1 / 25, 1 / 20, 1 / 15, 1 / 13, 1 / 10, 1 / 8, 1 / 6,
    1 / 5, 1 / 4, 0.3, 0.4, 1 / 2, 0.6, 0.8, 1,
    1.3, 1.6, 2, 2.5, 3.2, 4, 5, 6,
    8, 10, 13, 15, 20, 25, 30,
  ];

  /// Sensori BSI noti (isoAtUnity più alto).
  static const List<String> _bsiSensors = [
    'IMX294', 'IMX571', 'IMX455', 'IMX410', 'IMX533',
    'IMX585', 'IMX678', 'IMX662', 'IMX482', 'IMX464',
    'IMX290', 'IMX291', 'IMX185', 'IMX178', 'IMX183',
    'IMX432', 'IMX472',
  ];

  /// Bracket ottimizzato (secondi, crescente) per una feature.
  /// Senza [scope]/[cam] ritorna i valori di riferimento non scalati.
  List<double> optimizedExposures(
    EclipseFeature feature, {
    TelescopeSpec? scope,
    CameraSpec? cam,
    double? gain,
    double? iso,
  }) {
    final ref = referenceBrackets[feature.key] ?? referenceBrackets['totality']!;
    if (scope == null || cam == null) {
      return List<double>.of(ref)..sort();
    }

    final sf = _scaleFactor(scope, cam, gain: gain, iso: iso);
    final scaled = ref.map((t) => _snap(t * sf)).toSet().toList()..sort();

    // Limite anti-trailing (la corona esterna è esente: pose lunghe volute).
    final maxExp = _maxExposure(scope, cam);
    final limited = scaled
        .where((e) => e <= maxExp || feature == EclipseFeature.outerCorona)
        .toList();

    if (limited.length < 2 && scaled.length >= 2) {
      return scaled.take(math.min(scaled.length, 3)).toList();
    }
    return limited.isNotEmpty ? limited : scaled;
  }

  /// Fattore di scala combinato rispetto al setup di riferimento.
  double _scaleFactor(TelescopeSpec scope, CameraSpec cam,
      {double? gain, double? iso}) {
    final fr = scope.fRatio > 0 ? scope.fRatio : refFRatio;
    final fRatioFactor = math.pow(fr / refFRatio, 2).toDouble();
    final effIso = _effectiveIso(cam, gain: gain, iso: iso);
    final sensitivity = refIso / effIso;
    return fRatioFactor * sensitivity;
  }

  /// ISO efficace: diretto per reflex, derivato dal gain per le CMOS.
  double _effectiveIso(CameraSpec cam, {double? gain, double? iso}) {
    final type = cam.type.toLowerCase();
    if (type == 'dslr') return iso ?? 400;
    if (type == 'cmos') {
      final unity = cam.unityGain ?? 120;
      final g = gain ?? unity;
      final isoAtUnity = _isBsi(cam) ? 800.0 : 400.0;
      final gainPerStop = _gainPerStop(cam);
      final stops = (g - unity) / gainPerStop;
      final eff = isoAtUnity * math.pow(2, stops);
      return eff.clamp(50, 25600).toDouble();
    }
    if (iso != null) return iso;
    if (gain != null) return 100 * math.pow(2, gain / 40).toDouble();
    return 400;
  }

  double _gainPerStop(CameraSpec cam) {
    final m = cam.manufacturer.toLowerCase();
    if (m.contains('zwo') || m.contains('asi')) return 33;
    if (m.contains('qhy')) return 25;
    return 30;
  }

  bool _isBsi(CameraSpec cam) {
    final s = cam.sensor.toUpperCase();
    return _bsiSensors.any(s.contains);
  }

  /// Esposizione massima prima del trailing visibile (>1 px), cap a 30s.
  double _maxExposure(TelescopeSpec scope, CameraSpec cam) {
    final fl = scope.focalLength > 0 ? scope.focalLength : 600;
    final px = cam.pixelSize ?? 4;
    final imageScale = (px / fl) * 206.265; // arcsec/pixel
    const trackingResidual = 1.0; // arcsec/s tipico
    return math.min(30.0, imageScale / trackingResidual);
  }

  /// Arrotonda al tempo di scatto standard più vicino (distanza in stop, log2).
  double _snap(double seconds) {
    if (seconds <= 0) return 1 / 4000;
    final ls = math.log(seconds) / math.ln2;
    var closest = standardShutters.first;
    var minDiff = (ls - math.log(closest) / math.ln2).abs();
    for (final sh in standardShutters) {
      final diff = (ls - math.log(sh) / math.ln2).abs();
      if (diff < minDiff) {
        minDiff = diff;
        closest = sh;
      }
    }
    return closest;
  }
}

/// Formatta un'esposizione in secondi come stringa leggibile: `1/1000`, `2s`, `0.5s`.
String formatExposure(double seconds) {
  if (seconds >= 1) {
    return seconds == seconds.roundToDouble()
        ? '${seconds.toInt()}s'
        : '${seconds.toStringAsFixed(1)}s';
  }
  if (seconds <= 0) return '—';
  final inv = (1 / seconds).round();
  return '1/$inv';
}
