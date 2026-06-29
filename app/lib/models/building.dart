import 'package:latlong2/latlong.dart';

/// Obrys budynku pobrany z usługi ULDK (geometria EGiB).
class Building {
  const Building({
    required this.id,
    required this.points,
    required this.fetchedAt,
  });

  final String id;
  final List<LatLng> points; // zamknięty pierścień zewnętrzny
  final DateTime fetchedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'fetchedAt': fetchedAt.toIso8601String(),
        'points': [
          for (final p in points) [p.latitude, p.longitude],
        ],
      };

  factory Building.fromJson(Map<String, dynamic> json) => Building(
        id: json['id'] as String,
        fetchedAt: DateTime.parse(json['fetchedAt'] as String),
        points: [
          for (final p in json['points'] as List)
            LatLng((p[0] as num).toDouble(), (p[1] as num).toDouble()),
        ],
      );
}
