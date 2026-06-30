import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:gps_rtk_app/utils/geo.dart';

/// Obrys działki 222/1 (WGS84) — z dane/dzialka_222_1.geojson.
const gnojnikRing = [
  LatLng(49.8961851053933, 20.6158876571654),
  LatLng(49.8966355793539, 20.6164060487422),
  LatLng(49.8966595205632, 20.6164133752834),
  LatLng(49.8966969919656, 20.6163793938844),
  LatLng(49.8967702150162, 20.6162808223837),
  LatLng(49.8968058282749, 20.6162287606019),
  LatLng(49.8968323900486, 20.6161585364024),
  LatLng(49.8968575607642, 20.6160483750633),
  LatLng(49.8968643770909, 20.6158531737869),
  LatLng(49.8968494987749, 20.6157046348919),
  LatLng(49.8968362900651, 20.6156529604012),
  LatLng(49.8968010761280, 20.6155812779389),
  LatLng(49.8965497389591, 20.6152742704654),
  LatLng(49.8964604585176, 20.6151669682298),
  LatLng(49.8963827043336, 20.6150920061087),
  LatLng(49.8958966389206, 20.6146879089146),
  LatLng(49.8956634060877, 20.6144182092327),
  LatLng(49.8953684636804, 20.6149785629223),
  LatLng(49.8961851053933, 20.6158876571654),
];

void main() {
  // Punkty graniczne 1 i 2 działki 222/1 w Gnojniku. Odległość referencyjna
  // policzona z układu PL-2000: dx=37,50 m, dy=49,91 m -> 62,43 m.
  const p1 = LatLng(49.8961851053933, 20.6158876571654);
  const p2 = LatLng(49.8966355793539, 20.6164060487422);

  test('odległość zgadza się z referencją z PL-2000', () {
    expect(distanceMeters(p1, p2), closeTo(62.43, 0.05));
  });

  test('azymut p1->p2 wskazuje północny wschód', () {
    final b = bearingDegrees(p1, p2);
    expect(b, closeTo(36.6, 0.5));
    expect(cardinal(b), 'NE');
  });

  test('przesunięcie N/E względem północy geograficznej', () {
    // Składowe w PL-2000 (dx=37,50, dy=49,91) są względem północy SIATKI,
    // skręconej o zbieżność południków (~0,30° w Gnojniku, strefa 7).
    // Po odkręceniu o ten kąt: north=50,10 m, east=37,24 m.
    final o = offsetNorthEast(p1, p2);
    expect(o.north, closeTo(50.10, 0.05));
    expect(o.east, closeTo(37.24, 0.05));
  });

  test('odległość do samego siebie wynosi zero', () {
    expect(distanceMeters(p1, p1), closeTo(0, 1e-9));
  });

  test('formatowanie odległości', () {
    expect(formatDistance(0.62), '62 cm');
    expect(formatDistance(3.456), '3,46 m');
    expect(formatDistance(62.43), '62,4 m');
    expect(formatDistance(1234), '1,23 km');
  });

  test('kierunki świata', () {
    expect(cardinal(0), 'N');
    expect(cardinal(359), 'N');
    expect(cardinal(90), 'E');
    expect(cardinal(225), 'SW');
  });

  group('relativeBearing', () {
    test('cel na wprost gdy patrzymy w jego stronę', () {
      expect(relativeBearing(90, 90), closeTo(0, 1e-9));
    });

    test('cel po prawej = wartość dodatnia', () {
      expect(relativeBearing(90, 0), closeTo(90, 1e-9));
    });

    test('cel po lewej = wartość ujemna', () {
      expect(relativeBearing(0, 90), closeTo(-90, 1e-9));
    });

    test('normalizuje przejście przez północ', () {
      // patrzę na 350°, cel na 10° -> 20° w prawo, nie -340°.
      expect(relativeBearing(10, 350), closeTo(20, 1e-9));
      // patrzę na 10°, cel na 350° -> 20° w lewo.
      expect(relativeBearing(350, 10), closeTo(-20, 1e-9));
    });

    test('cel dokładnie za plecami', () {
      expect(relativeBearing(180, 0).abs(), closeTo(180, 1e-9));
    });
  });

  group('isPointInPolygon', () {
    const square = [
      LatLng(0, 0),
      LatLng(0, 1),
      LatLng(1, 1),
      LatLng(1, 0),
      LatLng(0, 0), // domknięcie pierścienia
    ];

    test('punkt w środku', () {
      expect(isPointInPolygon(const LatLng(0.5, 0.5), square), isTrue);
    });

    test('punkt na zewnątrz (na prawo)', () {
      expect(isPointInPolygon(const LatLng(0.5, 1.5), square), isFalse);
    });

    test('punkt na zewnątrz (poniżej)', () {
      expect(isPointInPolygon(const LatLng(-0.1, 0.5), square), isFalse);
    });

    test('zbyt mało wierzchołków = false', () {
      expect(
        isPointInPolygon(const LatLng(0, 0), [const LatLng(0, 0)]),
        isFalse,
      );
    });

    test('punkt wewnątrz realnej działki 222/1', () {
      // (49.8964, 20.6156) — punkt potwierdzony przez ULDK GetParcelByXY
      // jako leżący na działce 222/1.
      expect(isPointInPolygon(const LatLng(49.8964, 20.6156), gnojnikRing),
          isTrue);
      // punkt wyraźnie poza działką (na północ) — nie.
      expect(isPointInPolygon(const LatLng(49.9000, 20.6200), gnojnikRing),
          isFalse);
    });
  });

  group('turnInstruction', () {
    test('mały kąt to prosto', () {
      expect(turnInstruction(0), 'prosto');
      expect(turnInstruction(10), 'prosto');
      expect(turnInstruction(-14), 'prosto');
    });

    test('strona zależy od znaku', () {
      expect(turnInstruction(30), 'lekko w prawo');
      expect(turnInstruction(-30), 'lekko w lewo');
      expect(turnInstruction(90), 'w prawo');
      expect(turnInstruction(-90), 'w lewo');
    });

    test('duży kąt to zawróć', () {
      expect(turnInstruction(170), 'zawróć');
      expect(turnInstruction(-160), 'zawróć');
    });
  });

  test('isValidLatLng — zakres i wartości skończone', () {
    expect(isValidLatLng(49.9, 20.6), isTrue);
    expect(isValidLatLng(-90, -180), isTrue);
    expect(isValidLatLng(1054.6196325941419, 20), isFalse); // bug z terenu
    expect(isValidLatLng(49, 200), isFalse);
    expect(isValidLatLng(double.nan, 20), isFalse);
    expect(isValidLatLng(double.infinity, 20), isFalse);
  });

  group('allValidLatLng — strażnik warstw mapy', () {
    test('PUSTA lista → false (inaczej Polygon([]) → LatLng(NaN) przy zoomie)', () {
      // Sedno buga: Iterable.every na pustej liście zwraca true.
      expect(<LatLng>[].every((p) => isValidLatLng(p.latitude, p.longitude)),
          isTrue); // dokumentuje pułapkę, której unikamy
      expect(allValidLatLng(const <LatLng>[]), isFalse);
    });

    test('lista samych poprawnych → true', () {
      expect(allValidLatLng(gnojnikRing), isTrue);
      expect(allValidLatLng(const [LatLng(49.9, 20.6)]), isTrue);
    });

    test('jedna przekłamana współrzędna → false', () {
      expect(
        allValidLatLng(const [LatLng(49.9, 20.6), LatLng(1054.6, 20)]),
        isFalse,
      );
      expect(
        allValidLatLng([const LatLng(49.9, 20.6), LatLng(double.nan, 20)]),
        isFalse,
      );
    });
  });

  group('polygonAreaPerimeter', () {
    test('kwadrat 10×10 m -> 100 m² i 40 m obwodu', () {
      // Wierzchołki budowane przez destinationLatLng (N/E w metrach), więc
      // figura jest dokładnie kwadratem 10 m na elipsoidzie.
      final a = p1;
      final b = destinationLatLng(a, 0, 10); // 10 m na wschód
      final c = destinationLatLng(a, 10, 10); // 10 m N, 10 m E
      final d = destinationLatLng(a, 10, 0); // 10 m na północ
      final r = polygonAreaPerimeter([a, b, c, d]);
      expect(r.area, closeTo(100, 0.05));
      expect(r.perimeter, closeTo(40, 0.01));
    });

    test('kolejność wierzchołków (CW/CCW) nie zmienia pola', () {
      final a = p1;
      final b = destinationLatLng(a, 0, 10);
      final c = destinationLatLng(a, 10, 10);
      final d = destinationLatLng(a, 10, 0);
      final cw = polygonAreaPerimeter([a, b, c, d]).area;
      final ccw = polygonAreaPerimeter([a, d, c, b]).area;
      expect(cw, closeTo(ccw, 1e-6));
    });

    test('zdegenerowany wielokąt (1 punkt) -> zero', () {
      final r = polygonAreaPerimeter([p1]);
      expect(r.area, 0);
      expect(r.perimeter, 0);
    });
  });

  group('slopeBetween / formatSlope / slopeRatio', () {
    test('10 m w poziomie, +0,5 m w pionie → 5%, 50‰, ~2,86°', () {
      final a = p1;
      final b = destinationLatLng(a, 0, 10); // 10 m na wschód
      final s = slopeBetween(a, 100, b, 100.5);
      expect(s.horizontal, closeTo(10, 0.01));
      expect(s.deltaH, closeTo(0.5, 1e-9));
      expect(s.percent, closeTo(5, 0.02));
      expect(s.permille, closeTo(50, 0.2));
      expect(s.angleDeg, closeTo(2.862, 0.02));
    });

    test('spadek w dół = wartości ujemne', () {
      final a = p1;
      final b = destinationLatLng(a, 10, 0); // 10 m na północ
      final s = slopeBetween(a, 100, b, 99.0);
      expect(s.deltaH, closeTo(-1.0, 1e-9));
      expect(s.percent, closeTo(-10, 0.05));
      expect(s.angleDeg, lessThan(0));
    });

    test('pokrywające się punkty (poziomo) → procent 0, brak NaN', () {
      final s = slopeBetween(p1, 100, p1, 101);
      expect(s.horizontal, closeTo(0, 1e-6));
      expect(s.percent, 0);
      expect(s.permille, 0);
    });

    test('formatSlope: znak i przecinek dziesiętny', () {
      expect(formatSlope(5), '+5,00 %');
      expect(formatSlope(0), '0,00 %');
      final neg = formatSlope(-2.5);
      expect(neg, contains('2,50 %'));
      expect(neg.startsWith('+'), isFalse);
    });

    test('slopeRatio: 1:n, pusty dla zerowego spadku', () {
      expect(slopeRatio(40, 1), '1:40');
      expect(slopeRatio(5, 1), '1:5,0');
      expect(slopeRatio(10, 0), '');
    });
  });
}
