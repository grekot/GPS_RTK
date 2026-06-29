import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:gps_rtk_app/geometry/construction.dart';
import 'package:gps_rtk_app/geometry/local_frame.dart';
import 'package:gps_rtk_app/geometry/vec2.dart';

void main() {
  void expectVec(Vec2 v, double x, double y) {
    expect(v.x, closeTo(x, 1e-6));
    expect(v.y, closeTo(y, 1e-6));
  }

  test('offsetSegment odsuwa w lewo od kierunku', () {
    final (a, b) = offsetSegment(const Vec2(0, 0), const Vec2(10, 0), 3);
    expectVec(a, 0, 3);
    expectVec(b, 10, 3);
  });

  test('offsetSegment ujemny = w prawo', () {
    final (a, _) = offsetSegment(const Vec2(0, 0), const Vec2(10, 0), -3);
    expectVec(a, 0, -3);
  });

  group('parallelLine', () {
    test('offset=0, along=0, length=krawędź → jak offsetSegment', () {
      final (p, q) =
          parallelLine(const Vec2(0, 0), const Vec2(10, 0), offset: 3, length: 10);
      expectVec(p, 0, 3);
      expectVec(q, 10, 3);
    });

    test('along przesuwa wzdłuż krawędzi, length ustala długość', () {
      final (p, q) = parallelLine(const Vec2(0, 0), const Vec2(10, 0),
          offset: 3, along: 2, length: 4);
      expectVec(p, 2, 3);
      expectVec(q, 6, 3);
    });

    test('offset ujemny = druga strona; length ujemna = w przeciwną stronę', () {
      final (p, _) =
          parallelLine(const Vec2(0, 0), const Vec2(10, 0), offset: -3, length: 5);
      expectVec(p, 0, -3);
      final (s, e) =
          parallelLine(const Vec2(0, 0), const Vec2(10, 0), offset: 0, length: -5);
      expectVec(s, 0, 0);
      expectVec(e, -5, 0);
    });
  });

  test('nearestSegmentIndex — wybór spośród dowolnych odcinków', () {
    const segs = [
      (Vec2(0, 0), Vec2(10, 0)),
      (Vec2(0, 5), Vec2(10, 5)),
    ];
    expect(nearestSegmentIndex(segs, const Vec2(5, 1)), 0);
    expect(nearestSegmentIndex(segs, const Vec2(5, 4)), 1);
  });

  group('placeOnEdge / decomposeOnEdge (parametryczne umiejscowienie)', () {
    const a = Vec2(0, 0);
    const b = Vec2(10, 0); // dir=(1,0), perp=(0,1)

    test('placeOnEdge: along ∥ i offset ⊥', () {
      expectVec(placeOnEdge(const Vec2(0, 0), a, b, offset: 3, along: 2), 2, 3);
      expectVec(
          placeOnEdge(const Vec2(5, 0), a, b, offset: -1, along: 0), 5, -1);
    });

    test('decomposeOnEdge: składowe wektora w ramce krawędzi', () {
      final (al, off) = decomposeOnEdge(const Vec2(2, 3), a, b);
      expect(al, closeTo(2, 1e-9));
      expect(off, closeTo(3, 1e-9));
    });

    test('round-trip: decompose(place(v) - v) == (along, offset)', () {
      final moved = placeOnEdge(const Vec2(4, 0), a, b, offset: 1.5, along: -2);
      final (al, off) = decomposeOnEdge(moved - const Vec2(4, 0), a, b);
      expect(al, closeTo(-2, 1e-9));
      expect(off, closeTo(1.5, 1e-9));
    });

    test('działa dla krawędzi ukośnej (pionowej)', () {
      const c = Vec2(0, 0);
      const d = Vec2(0, 10); // dir=(0,1), perp=(-1,0)
      expectVec(placeOnEdge(const Vec2(0, 0), c, d, offset: 2, along: 3), -2, 3);
    });
  });

  test('closestPointOnLine — rzut prostopadły na prostą', () {
    expectVec(
        closestPointOnLine(const Vec2(5, 3), const Vec2(0, 0), const Vec2(10, 0)),
        5, 0);
    // poza odcinkiem, ale to PROSTA — rzut może wyjść poza końce
    expectVec(
        closestPointOnLine(
            const Vec2(-2, 4), const Vec2(0, 0), const Vec2(10, 0)),
        -2, 0);
  });

  test('closestPointOnSegment — rzut z ograniczeniem do końców', () {
    expectVec(
        closestPointOnSegment(
            const Vec2(5, 3), const Vec2(0, 0), const Vec2(10, 0)),
        5, 0); // wewnątrz
    expectVec(
        closestPointOnSegment(
            const Vec2(-2, 4), const Vec2(0, 0), const Vec2(10, 0)),
        0, 0); // przed początkiem → koniec a
    expectVec(
        closestPointOnSegment(
            const Vec2(15, 1), const Vec2(0, 0), const Vec2(10, 0)),
        10, 0); // za końcem → koniec b
  });

  group('snapToNearest', () {
    const candidates = [Vec2(10, 0), Vec2(0, 10)];

    test('przyciąga do kandydata w promieniu', () {
      final s = snapToNearest(const Vec2(9.5, 0), candidates, 1.0);
      expectVec(s, 10, 0); // dist 0.5 ≤ 1 → snap
    });

    test('bez przyciągania, gdy za daleko — zwraca punkt', () {
      final s = snapToNearest(const Vec2(5, 5), candidates, 1.0);
      expectVec(s, 5, 5);
    });

    test('wybiera najbliższego z kilku kandydatów', () {
      final s = snapToNearest(
          const Vec2(1, 9), candidates, 5.0); // bliżej (0,10) niż (10,0)
      expectVec(s, 0, 10);
    });
  });

  test('perpendicularThrough — prostopadła wyśrodkowana w punkcie', () {
    final (a, b) = perpendicularThrough(
        const Vec2(0, 0), const Vec2(10, 0), const Vec2(5, 0), 4);
    expectVec(a, 5, -2);
    expectVec(b, 5, 2);
  });

  test('rectangleFromEdge — podjazd od krawędzi', () {
    final r = rectangleFromEdge(const Vec2(0, 0), const Vec2(10, 0),
        offset: 2, length: 4, width: 3);
    expect(r, hasLength(4));
    expectVec(r[0], 0, 2);
    expectVec(r[1], 4, 2);
    expectVec(r[2], 4, 5);
    expectVec(r[3], 0, 5);
  });

  test('pointsAlong — co 4 m z końcem', () {
    final pts = pointsAlong(const Vec2(0, 0), const Vec2(10, 0), 4);
    expect(pts.map((p) => p.x).toList(), [0, 4, 8, 10]);
  });

  test('lineIntersection — przecięcie i równoległość', () {
    final p = lineIntersection(const Vec2(0, 0), const Vec2(10, 0),
        const Vec2(5, -5), const Vec2(5, 5));
    expect(p, isNotNull);
    expectVec(p!, 5, 0);
    expect(
      lineIntersection(const Vec2(0, 0), const Vec2(10, 0), const Vec2(0, 1),
          const Vec2(10, 1)),
      isNull,
    );
  });

  test('extend — przedłużenie poza b', () {
    expectVec(extend(const Vec2(0, 0), const Vec2(10, 0), 5), 15, 0);
  });

  test('pointToSegmentDistance — rzut na odcinek i poza nim', () {
    expect(
        pointToSegmentDistance(
            const Vec2(5, 3), const Vec2(0, 0), const Vec2(10, 0)),
        closeTo(3, 1e-9));
    // poza odcinkiem — liczone do najbliższego końca
    expect(
        pointToSegmentDistance(
            const Vec2(-3, 0), const Vec2(0, 0), const Vec2(10, 0)),
        closeTo(3, 1e-9));
  });

  test('nearestEdgeIndex — wybór krawędzi kwadratu', () {
    const ring = [Vec2(0, 0), Vec2(10, 0), Vec2(10, 10), Vec2(0, 10)];
    expect(nearestEdgeIndex(ring, const Vec2(5, -1)), 0); // dół
    expect(nearestEdgeIndex(ring, const Vec2(11, 5)), 1); // prawo
    expect(nearestEdgeIndex(ring, const Vec2(5, 11)), 2); // góra
    expect(nearestEdgeIndex(ring, const Vec2(-1, 5)), 3); // lewo
  });

  group('offsetRing — odsunięcie całego obrysu', () {
    // CCW kwadrat 10×10; offset dodatni = na lewo od kierunku obchodzenia,
    // czyli do wewnątrz dla pierścienia obchodzonego przeciwnie do zegara.
    const sq = [Vec2(0, 0), Vec2(10, 0), Vec2(10, 10), Vec2(0, 10)];

    test('inset o 1 m → mniejszy kwadrat 8×8', () {
      final r = offsetRing(sq, 1);
      expect(r, hasLength(4));
      expectVec(r[0], 1, 1);
      expectVec(r[1], 9, 1);
      expectVec(r[2], 9, 9);
      expectVec(r[3], 1, 9);
    });

    test('offset ujemny → większy kwadrat (na zewnątrz)', () {
      final r = offsetRing(sq, -1);
      expectVec(r[0], -1, -1);
      expectVec(r[2], 11, 11);
    });

    test('zachowuje liczbę wierzchołków', () {
      const penta = [
        Vec2(0, 0),
        Vec2(10, 0),
        Vec2(12, 6),
        Vec2(5, 10),
        Vec2(-2, 6),
      ];
      expect(offsetRing(penta, 0.5), hasLength(5));
    });
  });

  group('rectangleMetrics — kontrola prostokątności', () {
    test('idealny prostokąt: równe przekątne, kąty 90°', () {
      const r = [Vec2(0, 0), Vec2(10, 0), Vec2(10, 6), Vec2(0, 6)];
      final m = rectangleMetrics(r);
      expect(m.sides[0], closeTo(10, 1e-9));
      expect(m.sides[1], closeTo(6, 1e-9));
      expect(m.sides[2], closeTo(10, 1e-9));
      expect(m.sides[3], closeTo(6, 1e-9));
      expect(m.diag1, closeTo(m.diag2, 1e-9));
      expect(m.diagDiff, closeTo(0, 1e-9));
      expect(m.squarenessError, closeTo(0, 1e-9));
      for (final a in m.angles) {
        expect(a, closeTo(90, 1e-6));
      }
    });

    test('skośny czworokąt: przekątne różne, błąd kąta > 0', () {
      const r = [Vec2(0, 0), Vec2(10, 0), Vec2(12, 6), Vec2(2, 6)];
      final m = rectangleMetrics(r);
      expect(m.diagDiff, greaterThan(0.5));
      expect(m.squarenessError, greaterThan(1));
    });
  });

  test('LocalFrame: roundtrip i zgodność z metrami', () {
    final frame = LocalFrame(const LatLng(49.8964, 20.6156));
    expectVec(frame.toLocal(const LatLng(49.8964, 20.6156)), 0, 0);
    // 25 m na wschód, 40 m na północ → i z powrotem (tolerancja 1 mm).
    final p = frame.toLatLng(const Vec2(25, 40));
    final back = frame.toLocal(p);
    expect(back.x, closeTo(25, 1e-3));
    expect(back.y, closeTo(40, 1e-3));
  });
}
