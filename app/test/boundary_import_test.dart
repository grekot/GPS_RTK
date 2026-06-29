import 'package:flutter_test/flutter_test.dart';

import 'package:gps_rtk_app/utils/boundary_import.dart';
import 'package:gps_rtk_app/utils/pl2000.dart';

void main() {
  const lat = 49.8964, lon = 20.6156; // Gnojnik (strefa 7)

  test('Pl2000 round-trip: lat/lon → PL-2000 → lat/lon', () {
    final pl = Pl2000.fromLatLon(lat, lon);
    final back = Pl2000.toLatLon(pl.zone, pl.easting, pl.northing);
    expect(back.lat, closeTo(lat, 1e-7));
    expect(back.lon, closeTo(lon, 1e-7));
  });

  test('zoneFromEasting czyta strefę z prefiksu Y', () {
    expect(Pl2000.zoneFromEasting(7400000), 7);
    expect(Pl2000.zoneFromEasting(5500000), 5);
  });

  group('parseBoundaryPoints', () {
    test('format nr;X;Y;BPP (przecinek dziesiętny) — etykieta, pozycja, BPP', () {
      final pl = Pl2000.fromLatLon(lat, lon);
      final csv = '12; ${pl.northing.toStringAsFixed(2)}; '
          '${pl.easting.toStringAsFixed(2)}; 0,08';
      final pts = parseBoundaryPoints(csv);
      expect(pts, hasLength(1));
      expect(pts.first.label, '12');
      expect(pts.first.position.latitude, closeTo(lat, 1e-5));
      expect(pts.first.position.longitude, closeTo(lon, 1e-5));
      expect(pts.first.bpp, closeTo(0.08, 1e-9));
    });

    test('odwrotna kolejność Y X i spacje — autodetekcja', () {
      final pl = Pl2000.fromLatLon(lat, lon);
      final csv = '7  ${pl.easting.toStringAsFixed(3)}  '
          '${pl.northing.toStringAsFixed(3)}';
      final pts = parseBoundaryPoints(csv);
      expect(pts, hasLength(1));
      expect(pts.first.position.latitude, closeTo(lat, 1e-5));
      expect(pts.first.position.longitude, closeTo(lon, 1e-5));
    });

    test('nagłówek i komentarze pomijane', () {
      final pts = parseBoundaryPoints('nr;X;Y;dokladnosc\n# uwaga\n\n');
      expect(pts, isEmpty);
    });

    test('wiele punktów', () {
      final a = Pl2000.fromLatLon(lat, lon);
      final b = Pl2000.fromLatLon(lat + 0.0005, lon + 0.0005);
      final csv = 'A;${a.northing};${a.easting}\n'
          'B;${b.northing};${b.easting}';
      final pts = parseBoundaryPoints(csv);
      expect(pts.map((p) => p.label), ['A', 'B']);
      expect(pts.first.bpp, isNull);
    });
  });
}
