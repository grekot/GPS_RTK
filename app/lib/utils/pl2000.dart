import 'package:proj4dart/proj4dart.dart' as proj4;

/// Transformacja WGS84/ETRS89 → układ PL-2000 (Gaussa-Krügera, GRS80).
/// Strefy: 5 (lon0 15°, EPSG:2176), 6 (18°, 2177), 7 (21°, 2178), 8 (24°, 2179).
/// Konwencja PL-2000: Y = easting (z prefiksem strefy), X = northing.
class Pl2000 {
  static proj4.Projection get _wgs84 =>
      proj4.Projection.get('EPSG:4326') ?? proj4.Projection.WGS84;

  static proj4.Projection _zone(int zone) {
    final code = 'EPSG:${2171 + zone}';
    return proj4.Projection.get(code) ??
        proj4.Projection.add(
          code,
          '+proj=tmerc +lat_0=0 +lon_0=${3 * zone} +k=0.999923 '
          '+x_0=${500000 + zone * 1000000} +y_0=0 +ellps=GRS80 '
          '+towgs84=0,0,0,0,0,0,0 +units=m +no_defs',
        );
  }

  /// Numer strefy PL-2000 dla danej długości geograficznej (5..8).
  static int zoneFor(double lon) => (lon / 3).round().clamp(5, 8);

  /// Numer strefy odczytany z easting Y (z prefiksem strefy), np. 7,5 mln → 7.
  static int zoneFromEasting(double easting) =>
      (easting / 1000000).floor().clamp(5, 8);

  /// Zwraca strefę oraz współrzędne PL-2000: easting (Y) i northing (X) [m].
  static ({int zone, double easting, double northing}) fromLatLon(
    double lat,
    double lon,
  ) {
    final zone = zoneFor(lon);
    final p = _wgs84.transform(_zone(zone), proj4.Point(x: lon, y: lat));
    return (zone: zone, easting: p.x, northing: p.y);
  }

  /// Odwrotnie: PL-2000 (strefa, easting Y, northing X) → WGS84 (lat, lon).
  static ({double lat, double lon}) toLatLon(
    int zone,
    double easting,
    double northing,
  ) {
    final p =
        _zone(zone).transform(_wgs84, proj4.Point(x: easting, y: northing));
    return (lat: p.y, lon: p.x);
  }
}
