import 'package:flutter_test/flutter_test.dart';

import 'package:gps_rtk_app/map/tile_math.dart';

void main() {
  // Odniesienie: znana wartość kafelka dla Berlina (13.377,52.518) na z=12 to
  // x=2200, y=1343 w schemacie slippy map.
  test('lonToTileX / latToTileY zgodne ze schematem slippy map', () {
    expect(lonToTileX(13.377, 12), 2200);
    expect(latToTileY(52.518, 12), 1343);
  });

  test('z=0 ma jeden kafelek (0,0)', () {
    expect(lonToTileX(20.6, 0), 0);
    expect(latToTileY(49.9, 0), 0);
  });

  test('indeks rośnie na wschód i na południe', () {
    expect(lonToTileX(21.0, 14) >= lonToTileX(20.0, 14), isTrue);
    // większa szerokość (północ) => mniejszy Y
    expect(latToTileY(50.0, 14) < latToTileY(49.0, 14), isTrue);
  });

  test('tilesForBounds pokrywa prostokąt; pojedynczy zoom = oczekiwana liczba',
      () {
    // mały prostokąt wokół Gnojnika na z=18
    const s = 49.8954, w = 20.6144, n = 49.8969, e = 20.6164;
    final z18 = tilesForBounds(s, w, n, e, 18, 18);
    final xa = lonToTileX(w, 18), xb = lonToTileX(e, 18);
    final ya = latToTileY(n, 18), yb = latToTileY(s, 18);
    final expected = (xb - xa + 1) * (yb - ya + 1);
    expect(z18.length, expected);
    expect(z18.every((t) => t.z == 18), isTrue);
  });

  test('zakres zoomów sumuje kafelki ze wszystkich poziomów', () {
    const s = 49.8954, w = 20.6144, n = 49.8969, e = 20.6164;
    final multi = tileCountForBounds(s, w, n, e, 15, 19);
    var sum = 0;
    for (var z = 15; z <= 19; z++) {
      sum += tilesForBounds(s, w, n, e, z, z).length;
    }
    expect(multi, sum);
    expect(multi, greaterThan(0));
  });
}
