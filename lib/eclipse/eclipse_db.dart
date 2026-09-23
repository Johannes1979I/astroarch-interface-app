import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

/// Database eclissi bundlato (da Eclipse Commander, `assets/eclipse/eclipses.json`).
/// Contiene l'elenco eclissi con il percorso di centralità (punti lat/lon +
/// durata + località) e l'eclissi massima. I **tempi di contatto** (orari C1-C4)
/// NON sono nel JSON: li calcola il bridge con astropy per il GPS scelto.

class EclipsePathPoint {
  final double lat;
  final double lon;
  final int duration; // secondi di totalità/anularità in quel punto
  final String location;
  const EclipsePathPoint(
      {required this.lat, required this.lon, required this.duration, required this.location});

  factory EclipsePathPoint.fromJson(Map<String, dynamic> j) => EclipsePathPoint(
        lat: (j['lat'] as num).toDouble(),
        lon: (j['lon'] as num).toDouble(),
        duration: (j['duration'] as num?)?.toInt() ?? 0,
        location: (j['location'] as String?) ?? '',
      );
}

class EclipseEvent {
  final String id;
  final String type; // total | annular
  final String date; // YYYY-MM-DD
  final String name;
  final double magnitude;
  final int maxDuration; // s
  final List<EclipsePathPoint> path;
  final double? geLat;
  final double? geLon;
  final String? geTime; // es. "10:06:37 UT"

  const EclipseEvent({
    required this.id,
    required this.type,
    required this.date,
    required this.name,
    required this.magnitude,
    required this.maxDuration,
    required this.path,
    this.geLat,
    this.geLon,
    this.geTime,
  });

  bool get isTotal => type == 'total';

  factory EclipseEvent.fromJson(Map<String, dynamic> j) {
    final ge = j['greatestEclipse'] as Map<String, dynamic>?;
    return EclipseEvent(
      id: j['id'] as String,
      type: (j['type'] as String?) ?? 'total',
      date: j['date'] as String,
      name: (j['name'] as String?) ?? (j['id'] as String),
      magnitude: (j['magnitude'] as num?)?.toDouble() ?? 0,
      maxDuration: (j['maxDuration'] as num?)?.toInt() ?? 0,
      path: ((j['path'] as List?) ?? const [])
          .cast<Map<String, dynamic>>()
          .map(EclipsePathPoint.fromJson)
          .toList(),
      geLat: (ge?['lat'] as num?)?.toDouble(),
      geLon: (ge?['lon'] as num?)?.toDouble(),
      geTime: ge?['time'] as String?,
    );
  }

  /// Punto del percorso più vicino a (lat, lon) — per stimare la durata locale.
  EclipsePathPoint? nearest(double lat, double lon) {
    EclipsePathPoint? best;
    var bestD = double.infinity;
    for (final p in path) {
      final d = (p.lat - lat) * (p.lat - lat) + (p.lon - lon) * (p.lon - lon);
      if (d < bestD) {
        bestD = d;
        best = p;
      }
    }
    return best;
  }
}

/// Carica il database eclissi bundlato.
Future<List<EclipseEvent>> loadEclipseDb() async {
  final raw = await rootBundle.loadString('assets/eclipse/eclipses.json');
  final j = jsonDecode(raw) as Map<String, dynamic>;
  final list = (j['eclipses'] as List).cast<Map<String, dynamic>>();
  final events = list.map(EclipseEvent.fromJson).toList();
  // Ordina per data crescente.
  events.sort((a, b) => a.date.compareTo(b.date));
  return events;
}
