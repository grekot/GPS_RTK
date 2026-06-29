import 'dart:convert';

import 'package:latlong2/latlong.dart';

import '../utils/pl2000.dart';
import 'rtk_position.dart';

/// Punkt zmierzony w terenie (po uśrednieniu), z metryką jakości i odchyłką
/// od porównywanego punktu katastralnego.
class MeasuredPoint {
  const MeasuredPoint({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.rms,
    required this.meanAccuracy,
    required this.samples,
    required this.worstFix,
    required this.measuredAt,
    this.altitude,
    this.label,
    this.parcelId,
    this.targetIndex,
    this.devDistance,
    this.devNorth,
    this.devEast,
    this.category,
    this.note,
    this.photoPath,
  });

  final String id;
  final double latitude;
  final double longitude;

  /// Wysokość [m] z GGA (uśredniona). Null, gdy źródło jej nie podało.
  /// Zwykle ortometryczna (n.p.m. wg geoidy odbiornika); do *różnic* wysokości
  /// na małym terenie model geoidy nie jest potrzebny.
  final double? altitude;

  final double rms; // rozrzut pomiaru [m]
  final double meanAccuracy; // średnia dokładność urządzenia [m]
  final int samples;
  final FixType worstFix;
  final DateTime measuredAt;
  final String? label;

  /// Działka i indeks wierzchołka (0-based), z którym porównano pomiar.
  final String? parcelId;
  final int? targetIndex;

  /// Odchyłka pomiaru od punktu katastralnego: odległość oraz składowe N/E [m]
  /// (wektor od punktu z ewidencji do punktu zmierzonego).
  final double? devDistance;
  final double? devNorth;
  final double? devEast;

  /// Kod kategorii uzbrojenia (np. 'woda', 'gaz') — null dla punktów granicznych.
  final String? category;

  /// Notatka/kod obiektu wpisany przez użytkownika.
  final String? note;

  /// Ścieżka do zdjęcia w pamięci urządzenia (null = brak).
  final String? photoPath;

  LatLng get latLng => LatLng(latitude, longitude);

  MeasuredPoint copyWith({
    String? note,
    String? photoPath,
    bool removePhoto = false,
  }) =>
      MeasuredPoint(
        id: id,
        latitude: latitude,
        longitude: longitude,
        altitude: altitude,
        rms: rms,
        meanAccuracy: meanAccuracy,
        samples: samples,
        worstFix: worstFix,
        measuredAt: measuredAt,
        label: label,
        parcelId: parcelId,
        targetIndex: targetIndex,
        devDistance: devDistance,
        devNorth: devNorth,
        devEast: devEast,
        category: category,
        note: note ?? this.note,
        photoPath: removePhoto ? null : (photoPath ?? this.photoPath),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'lat': latitude,
        'lon': longitude,
        'alt': altitude,
        'rms': rms,
        'acc': meanAccuracy,
        'samples': samples,
        'fix': worstFix.name,
        'at': measuredAt.toIso8601String(),
        'label': label,
        'parcelId': parcelId,
        'targetIndex': targetIndex,
        'devDistance': devDistance,
        'devNorth': devNorth,
        'devEast': devEast,
        'category': category,
        'note': note,
        'photo': photoPath,
      };

  factory MeasuredPoint.fromJson(Map<String, dynamic> j) => MeasuredPoint(
        id: j['id'] as String,
        latitude: (j['lat'] as num).toDouble(),
        longitude: (j['lon'] as num).toDouble(),
        altitude: (j['alt'] as num?)?.toDouble(),
        rms: (j['rms'] as num).toDouble(),
        meanAccuracy: (j['acc'] as num).toDouble(),
        samples: j['samples'] as int,
        worstFix: FixType.values.byName(j['fix'] as String),
        measuredAt: DateTime.parse(j['at'] as String),
        label: j['label'] as String?,
        parcelId: j['parcelId'] as String?,
        targetIndex: j['targetIndex'] as int?,
        devDistance: (j['devDistance'] as num?)?.toDouble(),
        devNorth: (j['devNorth'] as num?)?.toDouble(),
        devEast: (j['devEast'] as num?)?.toDouble(),
        category: j['category'] as String?,
        note: j['note'] as String?,
        photoPath: j['photo'] as String?,
      );
}

String _csvCell(String? v) {
  final s = (v ?? '').replaceAll('"', '""');
  return s.contains(RegExp(r'[;\n"]')) ? '"$s"' : s;
}

/// Eksport listy punktów do CSV (separator ';', współrzędne WGS84).
String measuredPointsToCsv(List<MeasuredPoint> points) {
  final b = StringBuffer()
    ..writeln('label;kategoria;notatka;lat;lon;wys_m;zone2000;y2000_m;x2000_m;'
        'samples;rms_m;acc_m;fix;dev_m;dev_n_m;dev_e_m;zdjecie;time_iso');
  for (final p in points) {
    final pl = Pl2000.fromLatLon(p.latitude, p.longitude);
    b.writeln([
      _csvCell(p.label ?? p.id),
      _csvCell(p.category ?? ''),
      _csvCell(p.note ?? ''),
      p.latitude.toStringAsFixed(8),
      p.longitude.toStringAsFixed(8),
      p.altitude?.toStringAsFixed(3) ?? '',
      pl.zone,
      pl.easting.toStringAsFixed(2),
      pl.northing.toStringAsFixed(2),
      p.samples,
      p.rms.toStringAsFixed(3),
      p.meanAccuracy.toStringAsFixed(3),
      fixLabel(p.worstFix),
      p.devDistance?.toStringAsFixed(3) ?? '',
      p.devNorth?.toStringAsFixed(3) ?? '',
      p.devEast?.toStringAsFixed(3) ?? '',
      _csvCell(p.photoPath?.split(RegExp(r'[/\\]')).last ?? ''),
      p.measuredAt.toIso8601String(),
    ].join(';'));
  }
  return b.toString();
}

/// Eksport listy punktów do GeoJSON (WGS84, CRS84) — do wczytania w QGIS itp.
String measuredPointsToGeoJson(List<MeasuredPoint> points) {
  final features = <Map<String, dynamic>>[];
  for (final p in points) {
    final pl = Pl2000.fromLatLon(p.latitude, p.longitude);
    features.add({
      'type': 'Feature',
      'geometry': {
        'type': 'Point',
        'coordinates': [
          p.longitude,
          p.latitude,
          if (p.altitude != null) p.altitude,
        ],
      },
      'properties': {
        'label': p.label,
        'kategoria': p.category,
        'notatka': p.note,
        'wys_m': p.altitude,
        'zone2000': pl.zone,
        'y2000_m': pl.easting,
        'x2000_m': pl.northing,
        'samples': p.samples,
        'rms_m': p.rms,
        'acc_m': p.meanAccuracy,
        'fix': fixLabel(p.worstFix),
        'dev_m': p.devDistance,
        'dev_n_m': p.devNorth,
        'dev_e_m': p.devEast,
        'zdjecie': p.photoPath?.split(RegExp(r'[/\\]')).last,
        'time_iso': p.measuredAt.toIso8601String(),
      },
    });
  }
  return const JsonEncoder.withIndent('  ').convert({
    'type': 'FeatureCollection',
    'crs': {
      'type': 'name',
      'properties': {'name': 'urn:ogc:def:crs:OGC:1.3:CRS84'},
    },
    'features': features,
  });
}
