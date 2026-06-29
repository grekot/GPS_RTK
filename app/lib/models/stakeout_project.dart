import 'dart:convert';

import 'package:latlong2/latlong.dart';

/// Przenośny projekt tyczenia (wymiana PC ↔ telefon). Zapis jako GeoJSON z
/// rozszerzeniem: każdy obiekt ma `properties.role` ∈ {reference, construction,
/// stakeout}. `reference` to obrys odniesienia (budynek/działka), `construction`
/// to zaprojektowana figura (linia/prostokąt), `stakeout` to punkty do wytyczenia.
class StakeoutProject {
  StakeoutProject({
    required this.name,
    required this.createdAt,
    required this.stakePoints,
    this.reference = const [],
    this.construction = const [],
    this.constructionClosed = false,
    this.extraConstructions = const [],
  });

  final String name;
  final DateTime createdAt;
  final List<LatLng> stakePoints;
  final List<LatLng> reference;
  final List<LatLng> construction;
  final bool constructionClosed;

  /// Dodatkowe figury konstrukcyjne poza [construction] — dla projektów z wieloma
  /// elementami (kolejne linie/prostokąty budowane względem siebie). Każda ma
  /// własny obrys i flagę domknięcia (Polygon vs LineString).
  final List<({List<LatLng> path, bool closed})> extraConstructions;

  /// Obrys do narysowania na ekranie tyczenia: konstrukcja, a w razie jej braku
  /// — odniesienie.
  List<LatLng> get outline =>
      construction.isNotEmpty ? construction : reference;

  static List<List<double>> _ring(List<LatLng> pts) {
    final ring = [
      for (final p in pts) [p.longitude, p.latitude],
    ];
    if (ring.isNotEmpty && ring.first.toString() != ring.last.toString()) {
      ring.add(ring.first); // domknięcie pierścienia (wymóg GeoJSON Polygon)
    }
    return ring;
  }

  String toGeoJson() {
    final features = <Map<String, dynamic>>[];
    if (reference.isNotEmpty) {
      features.add({
        'type': 'Feature',
        'properties': {'role': 'reference'},
        'geometry': {
          'type': 'Polygon',
          'coordinates': [_ring(reference)],
        },
      });
    }
    Map<String, dynamic> constructionFeature(List<LatLng> path, bool closed) => {
          'type': 'Feature',
          'properties': {'role': 'construction'},
          'geometry': closed
              ? {
                  'type': 'Polygon',
                  'coordinates': [_ring(path)],
                }
              : {
                  'type': 'LineString',
                  'coordinates': [
                    for (final p in path) [p.longitude, p.latitude],
                  ],
                },
        };
    if (construction.isNotEmpty) {
      features.add(constructionFeature(construction, constructionClosed));
    }
    for (final shape in extraConstructions) {
      if (shape.path.isNotEmpty) {
        features.add(constructionFeature(shape.path, shape.closed));
      }
    }
    for (var i = 0; i < stakePoints.length; i++) {
      features.add({
        'type': 'Feature',
        'properties': {'role': 'stakeout', 'index': i, 'label': '${i + 1}'},
        'geometry': {
          'type': 'Point',
          'coordinates': [stakePoints[i].longitude, stakePoints[i].latitude],
        },
      });
    }
    return const JsonEncoder.withIndent('  ').convert({
      'type': 'FeatureCollection',
      'properties': {
        'app': 'gps_rtk',
        'kind': 'stakeout-project',
        'name': name,
        'created': createdAt.toIso8601String(),
      },
      'crs': {
        'type': 'name',
        'properties': {'name': 'urn:ogc:def:crs:OGC:1.3:CRS84'},
      },
      'features': features,
    });
  }

  factory StakeoutProject.fromGeoJson(String source) {
    final json = jsonDecode(source) as Map<String, dynamic>;
    if (json['type'] != 'FeatureCollection') {
      throw const FormatException('To nie jest GeoJSON FeatureCollection.');
    }
    final props = (json['properties'] as Map<String, dynamic>?) ?? const {};
    final reference = <LatLng>[];
    var construction = <LatLng>[];
    var constructionClosed = false;
    final extra = <({List<LatLng> path, bool closed})>[];
    final stake = <({int index, LatLng p})>[];

    for (final f in (json['features'] as List? ?? const [])) {
      final feat = f as Map<String, dynamic>;
      final role =
          (feat['properties'] as Map<String, dynamic>?)?['role'] as String?;
      final geom = feat['geometry'] as Map<String, dynamic>?;
      if (geom == null) continue;
      final type = geom['type'] as String?;
      final coords = geom['coordinates'];

      List<LatLng> ringToLatLng(dynamic ring) {
        final pts = [
          for (final c in ring as List)
            LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
        ];
        // Usuń duplikat zamykający pierścień (GeoJSON Polygon), by tablica
        // odpowiadała wejściu (otwarty zestaw wierzchołków).
        if (pts.length > 1 &&
            pts.first.latitude == pts.last.latitude &&
            pts.first.longitude == pts.last.longitude) {
          pts.removeLast();
        }
        return pts;
      }

      switch (role) {
        case 'reference':
          if (type == 'Polygon') {
            reference.addAll(ringToLatLng((coords as List).first));
          }
        case 'construction':
          List<LatLng>? path;
          var closed = false;
          if (type == 'Polygon') {
            path = ringToLatLng((coords as List).first);
            closed = true;
          } else if (type == 'LineString') {
            path = ringToLatLng(coords);
          }
          if (path != null) {
            // Pierwsza figura → construction; kolejne → extraConstructions.
            if (construction.isEmpty) {
              construction = path;
              constructionClosed = closed;
            } else {
              extra.add((path: path, closed: closed));
            }
          }
        case 'stakeout':
          if (type == 'Point') {
            final idx = (feat['properties']
                    as Map<String, dynamic>?)?['index'] as int? ??
                stake.length;
            stake.add((
              index: idx,
              p: LatLng((coords[1] as num).toDouble(),
                  (coords[0] as num).toDouble())
            ));
          }
      }
    }
    stake.sort((a, b) => a.index.compareTo(b.index));

    return StakeoutProject(
      name: props['name'] as String? ?? 'Projekt',
      createdAt:
          DateTime.tryParse(props['created'] as String? ?? '') ?? DateTime.now(),
      reference: reference,
      construction: construction,
      constructionClosed: constructionClosed,
      extraConstructions: extra,
      stakePoints: [for (final s in stake) s.p],
    );
  }
}
