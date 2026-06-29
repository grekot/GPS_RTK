import 'package:latlong2/latlong.dart';

/// Działka ewidencyjna pobrana z usługi ULDK lub wczytana z pliku.
class Parcel {
  final String id; // pełny identyfikator TERYT, np. 120205_2.0001.222/1
  final String number; // np. 222/1
  final String region; // obręb
  final String commune; // gmina
  final String county; // powiat
  final List<LatLng> points; // obrys (zamknięty pierścień zewnętrzny)
  final DateTime fetchedAt;

  const Parcel({
    required this.id,
    required this.number,
    required this.region,
    required this.commune,
    required this.county,
    required this.points,
    required this.fetchedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'number': number,
        'region': region,
        'commune': commune,
        'county': county,
        'fetchedAt': fetchedAt.toIso8601String(),
        'points': [
          for (final p in points) [p.latitude, p.longitude],
        ],
      };

  factory Parcel.fromJson(Map<String, dynamic> json) => Parcel(
        id: json['id'] as String,
        number: json['number'] as String,
        region: json['region'] as String,
        commune: json['commune'] as String,
        county: json['county'] as String,
        fetchedAt: DateTime.parse(json['fetchedAt'] as String),
        points: [
          for (final p in json['points'] as List)
            LatLng((p[0] as num).toDouble(), (p[1] as num).toDouble()),
        ],
      );

  /// Krótki opis do list i komunikatów, np. "222/1 (Gnojnik, gm. Gnojnik)".
  String get label => '$number ($region, gm. $commune)';
}
