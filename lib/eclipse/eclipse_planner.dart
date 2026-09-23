import 'eclipse_optimizer.dart';

/// Motore di pianificazione eclissi (Fase 2) — il "motore del tempo".
///
/// Dai feature selezionati costruisce una timeline di totalità ordinata,
/// stima le durate (esposizione + overhead di lettura/salvataggio per frame)
/// e applica il **budget-tempo**: se i blocchi non stanno nella durata della
/// totalità, riduce la profondità partendo dalla priorità più bassa
/// (corona esterna → media → cromosfera → interna → protuberanze → Baily),
/// come da specifica concordata. Baily/diamante non vengono mai sacrificati.

/// Contatti dell'eclissi. La totalità è C2→C3.
class EclipseContacts {
  final DateTime? c1;
  final DateTime? c2;
  final DateTime? max;
  final DateTime? c3;
  final DateTime? c4;

  const EclipseContacts({this.c1, this.c2, this.max, this.c3, this.c4});

  /// Durata della totalità (null se C2/C3 mancano).
  Duration? get totality =>
      (c2 != null && c3 != null) ? c3!.difference(c2!) : null;
}

/// Un blocco di cattura schedulato (una feature, un bracket).
class CaptureBlock {
  final EclipseFeature feature;

  /// Etichetta di visualizzazione (per Baily può essere "C2"/"C3").
  final String label;

  /// Esposizioni in secondi (crescente).
  final List<double> exposures;

  /// Scatti per ogni esposizione del bracket.
  final int shots;

  /// Priorità: 1 = massima (mai eliminata) … 6 = prima a essere ridotta.
  final int priority;

  /// true nelle fasi parziali (filtro solare inserito).
  final bool withFilter;

  const CaptureBlock({
    required this.feature,
    required this.label,
    required this.exposures,
    required this.shots,
    required this.priority,
    this.withFilter = false,
  });

  /// Numero totale di frame (esposizioni × scatti).
  int get frames => exposures.length * shots;

  /// Durata stimata: Σ (esposizione + overhead) × scatti.
  Duration estimate(double overheadSec) {
    var s = 0.0;
    for (final e in exposures) {
      s += (e + overheadSec) * shots;
    }
    return Duration(milliseconds: (s * 1000).round());
  }

  CaptureBlock copyWith({List<double>? exposures, int? shots}) => CaptureBlock(
        feature: feature,
        label: label,
        exposures: exposures ?? this.exposures,
        shots: shots ?? this.shots,
        priority: priority,
        withFilter: withFilter,
      );
}

/// Piano completo: blocchi + verifica del budget-tempo.
class EclipsePlan {
  /// Blocchi di totalità, in ordine cronologico.
  final List<CaptureBlock> totalityBlocks;

  /// Blocchi di fase parziale (filtro inserito) — fuori dal budget totalità.
  final List<CaptureBlock> partialBlocks;

  /// Durata disponibile della totalità (null se contatti mancanti).
  final Duration? totalityBudget;

  /// Overhead per frame usato nella stima (s).
  final double overheadSec;

  /// Note su cosa è stato ridotto/eliminato per rientrare nel tempo.
  final List<String> adjustments;

  const EclipsePlan({
    required this.totalityBlocks,
    required this.partialBlocks,
    required this.totalityBudget,
    required this.overheadSec,
    required this.adjustments,
  });

  Duration get totalityUsed => totalityBlocks.fold(
      Duration.zero, (a, b) => a + b.estimate(overheadSec));

  int get totalityFrames =>
      totalityBlocks.fold(0, (a, b) => a + b.frames);

  int get partialFrames => partialBlocks.fold(0, (a, b) => a + b.frames);

  /// true se i blocchi di totalità stanno nella durata disponibile.
  bool get fits =>
      totalityBudget == null || totalityUsed <= totalityBudget!;

  /// Secondi di sforamento (0 se rientra o budget ignoto).
  int get overrunSeconds {
    if (totalityBudget == null) return 0;
    final over = totalityUsed - totalityBudget!;
    return over.isNegative ? 0 : over.inSeconds;
  }

  /// Margine residuo nella totalità (0 se sfora o budget ignoto).
  int get marginSeconds {
    if (totalityBudget == null) return 0;
    final left = totalityBudget! - totalityUsed;
    return left.isNegative ? 0 : left.inSeconds;
  }

  /// Payload JSON per il conduttore del bridge (`POST /api/eclipse/plan`).
  /// Invia i blocchi di totalità (il fire-loop live); la fase parziale resta
  /// gestita a parte (filtro manuale).
  Map<String, dynamic> bridgePayload({double? gain, double? offset, String? device}) => {
        'blocks': [
          for (final b in totalityBlocks)
            {
              'label': b.label,
              'exposures': b.exposures,
              'shots': b.shots,
              'priority': b.priority,
              'with_filter': b.withFilter,
            }
        ],
        if (gain != null) 'gain': gain,
        if (offset != null) 'offset': offset,
        if (device != null && device.isNotEmpty) 'device': device,
        'overhead_sec': overheadSec,
        if (totalityBudget != null) 'totality_sec': totalityBudget!.inSeconds,
      };
}

/// Costruttore del piano.
class EclipsePlanner {
  final ExposureOptimizer opt;

  /// Overhead per frame (lettura + salvataggio). ~1.5s tipico per CMOS grandi.
  final double overheadSec;

  EclipsePlanner({ExposureOptimizer? optimizer, this.overheadSec = 1.5})
      : opt = optimizer ?? ExposureOptimizer();

  /// Priorità di una feature (1 = mai eliminata … 6 = prima a essere ridotta).
  static int priorityOf(EclipseFeature f) => switch (f) {
        EclipseFeature.baily => 1,
        EclipseFeature.prominences => 2,
        EclipseFeature.innerCorona => 3,
        EclipseFeature.chromosphere => 4,
        EclipseFeature.midCorona => 5,
        EclipseFeature.outerCorona => 6,
        EclipseFeature.totality => 3,
        EclipseFeature.partial => 9,
      };

  /// Ordine cronologico delle feature di totalità (bookend Baily a C2 e C3).
  static const List<EclipseFeature> _totalityOrder = [
    EclipseFeature.baily, // C2 (diamante ingresso)
    EclipseFeature.chromosphere,
    EclipseFeature.prominences,
    EclipseFeature.innerCorona,
    EclipseFeature.midCorona,
    EclipseFeature.outerCorona,
    EclipseFeature.totality,
    EclipseFeature.baily, // C3 (diamante uscita) — gestito come 2ª occorrenza
  ];

  EclipsePlan build({
    required Set<EclipseFeature> features,
    required EclipseContacts contacts,
    TelescopeSpec? scope,
    CameraSpec? cam,
    double? gain,
    double? iso,
    int shotsPerExposure = 1,
    bool maximizeShots = false,
  }) {
    final adjustments = <String>[];

    // --- Blocchi di totalità (in ordine, Baily bookend) ---
    final totality = <CaptureBlock>[];
    var bailySeen = 0;
    for (final f in _totalityOrder) {
      if (!features.contains(f)) continue;
      final expo = opt.optimizedExposures(f, scope: scope, cam: cam, gain: gain, iso: iso);
      if (expo.isEmpty) continue;
      String label = f.labelIt;
      if (f == EclipseFeature.baily) {
        bailySeen++;
        label = bailySeen == 1 ? 'Perle di Baily — C2 (ingresso)'
                               : 'Perle di Baily — C3 (uscita)';
      }
      totality.add(CaptureBlock(
        feature: f,
        label: label,
        exposures: List<double>.of(expo),
        shots: shotsPerExposure,
        priority: priorityOf(f),
      ));
    }

    // --- Budget-tempo ---
    final budget = contacts.totality;
    if (budget != null) {
      if (maximizeShots) {
        _maximizeShots(totality, budget, adjustments);
      } else {
        _applyTimeBudget(totality, budget, adjustments);
      }
    }

    // --- Blocchi di fase parziale (filtro inserito, fuori dal budget) ---
    final partial = <CaptureBlock>[];
    if (features.contains(EclipseFeature.partial)) {
      final expo = opt.optimizedExposures(EclipseFeature.partial,
          scope: scope, cam: cam, gain: gain, iso: iso);
      if (expo.isNotEmpty) {
        partial.add(CaptureBlock(
          feature: EclipseFeature.partial,
          label: 'Fase parziale (filtro ND5)',
          exposures: List<double>.of(expo),
          shots: shotsPerExposure,
          priority: priorityOf(EclipseFeature.partial),
          withFilter: true,
        ));
      }
    }

    return EclipsePlan(
      totalityBlocks: totality,
      partialBlocks: partial,
      totalityBudget: budget,
      overheadSec: overheadSec,
      adjustments: adjustments,
    );
  }

  /// Massimizza il numero di scatti per fase riempiendo il budget di totalità:
  /// ogni blocco parte da 1 passaggio, poi si aggiungono passaggi (bilanciando
  /// tra le fasi, dando al blocco con meno scatti) finché il tempo lo consente.
  /// Le fasi transitorie (Baily, cromosfera) hanno un tetto perché il fenomeno
  /// dura pochi secondi. Serve a integrare segnale: più frame da impilare.
  void _maximizeShots(
      List<CaptureBlock> blocks, Duration budget, List<String> adjustments) {
    final budgetSec = budget.inSeconds.toDouble();
    for (var i = 0; i < blocks.length; i++) {
      blocks[i] = blocks[i].copyWith(shots: 1);
    }
    double perPass(CaptureBlock b) =>
        b.copyWith(shots: 1).estimate(overheadSec).inMilliseconds / 1000.0;
    double used() => blocks.fold(
        0.0, (a, b) => a + b.estimate(overheadSec).inMilliseconds / 1000.0);
    int cap(EclipseFeature f) => switch (f) {
          EclipseFeature.baily => 2, // fenomeno di pochi secondi
          EclipseFeature.chromosphere => 3,
          _ => 1 << 30, // corona/protuberanze: nessun tetto pratico
        };
    var guard = 0;
    while (guard < 10000) {
      guard++;
      CaptureBlock? cand;
      for (final b in blocks) {
        if (b.shots >= cap(b.feature)) continue;
        if (used() + perPass(b) > budgetSec) continue;
        if (cand == null || b.shots < cand.shots) cand = b;
      }
      if (cand == null) break;
      final i = blocks.indexOf(cand);
      blocks[i] = cand.copyWith(shots: cand.shots + 1);
    }
    final total = blocks.fold(0, (a, b) => a + b.frames);
    adjustments.add('Scatti massimizzati: $total frame nel tempo disponibile');
  }

  /// Riduce i blocchi finché la somma stimata rientra nel [budget].
  /// Strategia (spec a): togli l'esposizione più lunga dal blocco di priorità
  /// più bassa; se un blocco resta senza esposizioni, viene eliminato. Baily
  /// (priorità 1) non viene mai svuotato: si ferma prima.
  void _applyTimeBudget(
      List<CaptureBlock> blocks, Duration budget, List<String> adjustments) {
    Duration used() =>
        blocks.fold(Duration.zero, (a, b) => a + b.estimate(overheadSec));

    var guard = 0;
    while (used() > budget && guard < 500) {
      guard++;
      // Candidato: priorità più alta (numero) e più esposizioni, escludendo
      // Baily (priorità 1) e blocchi con una sola esposizione rimasta se
      // esistono candidati con più margine.
      CaptureBlock? target;
      for (final b in blocks) {
        if (b.priority <= 1) continue; // Baily mai ridotta
        if (b.exposures.length <= 1) continue;
        if (target == null ||
            b.priority > target.priority ||
            (b.priority == target.priority &&
                b.exposures.length > target.exposures.length)) {
          target = b;
        }
      }
      // Se nessun blocco ha >1 esposizione, elimina l'intero blocco di
      // priorità più bassa (Baily esclusa).
      if (target == null) {
        CaptureBlock? drop;
        for (final b in blocks) {
          if (b.priority <= 1) continue;
          if (drop == null || b.priority > drop.priority) drop = b;
        }
        if (drop == null) break; // restano solo blocchi intoccabili
        blocks.remove(drop);
        adjustments.add('Eliminato "${drop.label}" per rientrare nel tempo');
        continue;
      }
      // Togli l'esposizione più lunga dal blocco target.
      final idx = blocks.indexOf(target);
      final trimmed = List<double>.of(target.exposures)..removeLast();
      blocks[idx] = target.copyWith(exposures: trimmed);
      adjustments.add(
          'Ridotta profondità "${target.label}" (${formatExposure(target.exposures.last)} rimossa)');
    }
  }
}
