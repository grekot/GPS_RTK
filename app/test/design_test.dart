import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:gps_rtk_app/models/design.dart';
import 'package:gps_rtk_app/models/parcel.dart';

Parcel _square() => Parcel(
      id: 'P1',
      number: '1',
      region: '',
      commune: '',
      county: '',
      fetchedAt: DateTime.utc(2026),
      points: const [
        LatLng(50.0000, 20.0000),
        LatLng(50.0010, 20.0000),
        LatLng(50.0010, 20.0010),
        LatLng(50.0000, 20.0010),
      ],
    );

void main() {
  group('Design JSON', () {
    test('round-trip zachowuje nazwę, parametry i odniesienie', () {
      final d = Design(id: 'D1', name: 'Ogrodzenie', createdAt: DateTime.utc(2026));
      final e = DesignElement(
          tool: ToolType.rownolegla,
          ref: const GeomRef(kind: 'parcel', sourceId: 'P1', edge: 2))
        ..offset = 1.5
        ..lineLen = 12.0;
      d.elements.add(e);
      d.elements.add(DesignElement(
          tool: ToolType.prostokat,
          ref: const GeomRef(kind: 'element', element: 0, edge: 0))
        ..length = 4
        ..width = 2.5);

      final back = Design.fromJson(
          jsonDecode(jsonEncode(d.toJson())) as Map<String, dynamic>);
      expect(back.name, 'Ogrodzenie');
      expect(back.elements, hasLength(2));
      expect(back.elements[0].tool, ToolType.rownolegla);
      expect(back.elements[0].ref.kind, 'parcel');
      expect(back.elements[0].ref.sourceId, 'P1');
      expect(back.elements[0].ref.edge, 2);
      expect(back.elements[0].offset, 1.5);
      expect(back.elements[0].lineLen, 12.0);
      expect(back.elements[1].tool, ToolType.prostokat);
      expect(back.elements[1].ref.kind, 'element');
      expect(back.elements[1].ref.element, 0);
      expect(back.elements[1].width, 2.5);
    });

    test('round-trip zachowuje linie robocze', () {
      final d = Design(
        id: 'D',
        name: 'd',
        createdAt: DateTime.utc(2026),
        workingLines: const [GeomRef(kind: 'building', sourceId: 'B', edge: 1)],
      );
      final back = Design.fromJson(
          jsonDecode(jsonEncode(d.toJson())) as Map<String, dynamic>);
      expect(back.workingLines, hasLength(1));
      expect(back.workingLines.first.kind, 'building');
      expect(back.workingLines.first.edge, 1);
    });
  });

  group('DesignWorld', () {
    test('element względem krawędzi działki — offset ⊥', () {
      final design = Design(id: 'D1', name: 'd', createdAt: DateTime.utc(2026));
      design.elements.add(DesignElement(
          tool: ToolType.rownolegla,
          ref: const GeomRef(kind: 'parcel', sourceId: 'P1', edge: 0))
        ..offset = 3);
      final world = DesignWorld(
          parcels: [_square()], buildings: const [], designs: [design]);
      final c = world.computeDesign(design);
      expect(c, hasLength(1));
      expect(c[0].path, hasLength(2));

      final ring = world.parcelLocal['P1']!;
      final a = ring[0], b = ring[1];
      final dir = (b - a).normalized;
      // path[0] = a + perp*3 → odległość 3 i prostopadle do krawędzi.
      expect((c[0].path[0] - a).length, closeTo(3, 1e-6));
      expect((c[0].path[0] - a).dot(dir).abs(), closeTo(0, 1e-6));
    });

    test('chaining: element względem innego elementu', () {
      final design = Design(id: 'D1', name: 'd', createdAt: DateTime.utc(2026));
      design.elements.add(DesignElement(
          tool: ToolType.rownolegla,
          ref: const GeomRef(kind: 'parcel', sourceId: 'P1', edge: 0))
        ..offset = 3);
      design.elements.add(DesignElement(
          tool: ToolType.rownolegla,
          ref: const GeomRef(kind: 'element', element: 0, edge: 0))
        ..offset = 2);
      final world = DesignWorld(
          parcels: [_square()], buildings: const [], designs: [design]);
      final c = world.computeDesign(design);
      expect(c, hasLength(2));
      // element 1 jest odsunięty 2 m od krawędzi elementu 0.
      final e0a = c[0].path[0], e0b = c[0].path[1];
      final dir = (e0b - e0a).normalized;
      expect((c[1].path[0] - e0a).length, closeTo(2, 1e-6));
      expect((c[1].path[0] - e0a).dot(dir).abs(), closeTo(0, 1e-6));
    });

    test('cross-design: odniesienie do innego projektu', () {
      final d1 = Design(id: 'D1', name: 'd1', createdAt: DateTime.utc(2026));
      d1.elements.add(DesignElement(
          tool: ToolType.rownolegla,
          ref: const GeomRef(kind: 'parcel', sourceId: 'P1', edge: 0))
        ..offset = 3);
      final d2 = Design(id: 'D2', name: 'd2', createdAt: DateTime.utc(2026));
      d2.elements.add(DesignElement(
          tool: ToolType.rownolegla,
          ref: const GeomRef(kind: 'design', sourceId: 'D1', element: 0, edge: 0))
        ..offset = 1);
      final world = DesignWorld(
          parcels: [_square()], buildings: const [], designs: [d1, d2]);
      final c = world.computeDesign(d2);
      expect(c, hasLength(1));
      expect(c[0].path, hasLength(2)); // rozwiązane przez geometrię D1
    });

    test('frozen ref daje tę samą geometrię co żywe odniesienie do krawędzi', () {
      final sq = _square();
      final d = Design(id: 'D', name: 'd', createdAt: DateTime.utc(2026));
      // A: linia względem krawędzi 0 działki.
      d.elements.add(DesignElement(
          tool: ToolType.rownolegla,
          ref: const GeomRef(kind: 'parcel', sourceId: 'P1', edge: 0))
        ..offset = 3);
      // B: ta sama krawędź, ale „zamrożona" (współrzędne pkt 0–1 działki).
      final p0 = sq.points[0], p1 = sq.points[1];
      d.elements.add(DesignElement(
          tool: ToolType.rownolegla,
          ref: GeomRef(kind: 'frozen', frozen: [
            p0.latitude,
            p0.longitude,
            p1.latitude,
            p1.longitude
          ]))
        ..offset = 3);
      final world = DesignWorld(
          parcels: [sq], buildings: const [], designs: [d]);
      final c = world.computeDesign(d);
      for (var k = 0; k < 2; k++) {
        expect(c[1].path[k].x, closeTo(c[0].path[k].x, 1e-6));
        expect(c[1].path[k].y, closeTo(c[0].path[k].y, 1e-6));
      }
    });

    test('przedłużenie: path = linia (2 pkt), stake = koniec (1 pkt)', () {
      final d = Design(id: 'D', name: 'd', createdAt: DateTime.utc(2026));
      d.elements.add(DesignElement(
          tool: ToolType.przedluzenie,
          ref: const GeomRef(kind: 'parcel', sourceId: 'P1', edge: 0)));
      final w = DesignWorld(
          parcels: [_square()], buildings: const [], designs: [d]);
      final c = w.computeDesign(d);
      expect(c[0].path, hasLength(2)); // linia musi mieć 2 punkty (rysowanie)
      expect(c[0].stake, hasLength(1));
    });

    test('punkty wzdłuż: path = linia bazowa (2 pkt), stake = wiele punktów', () {
      final d = Design(id: 'D', name: 'd', createdAt: DateTime.utc(2026));
      d.elements.add(DesignElement(
          tool: ToolType.punktyWzdluz,
          ref: const GeomRef(kind: 'parcel', sourceId: 'P1', edge: 0))
        ..interval = 50);
      final w = DesignWorld(
          parcels: [_square()], buildings: const [], designs: [d]);
      final c = w.computeDesign(d);
      expect(c[0].path, hasLength(2));
      expect(c[0].stake.length, greaterThan(1));
    });

    test('punkt przecięcia dwóch krawędzi = wspólny wierzchołek', () {
      final sq = _square();
      final d = Design(id: 'D', name: 'd', createdAt: DateTime.utc(2026));
      // Krawędź 0 i 1 działki przecinają się w wierzchołku 1.
      d.elements.add(DesignElement(
        tool: ToolType.punktPrzeciecie,
        ref: const GeomRef(kind: 'parcel', sourceId: 'P1', edge: 0),
        ref2: const GeomRef(kind: 'parcel', sourceId: 'P1', edge: 1),
      ));
      final w =
          DesignWorld(parcels: [sq], buildings: const [], designs: [d]);
      final c = w.computeDesign(d);
      expect(c[0].path, hasLength(1));
      expect((c[0].path[0] - w.parcelLocal['P1']![1]).length, closeTo(0, 1e-6));
    });

    test('punkt ręczny = stała współrzędna wskazana na mapie', () {
      final sq = _square();
      final d = Design(id: 'D', name: 'd', createdAt: DateTime.utc(2026));
      d.elements.add(DesignElement(
        tool: ToolType.punktReczny,
        ref: GeomRef(kind: 'point', frozen: [
          sq.points[3].latitude,
          sq.points[3].longitude,
        ]),
      ));
      final w =
          DesignWorld(parcels: [sq], buildings: const [], designs: [d]);
      final c = w.computeDesign(d);
      expect(c[0].path, hasLength(1));
      expect((c[0].path[0] - w.parcelLocal['P1']![3]).length, closeTo(0, 1e-6));
    });

    test('punkt GPS = stała współrzędna z pomiaru', () {
      final sq = _square();
      final d = Design(id: 'D', name: 'd', createdAt: DateTime.utc(2026));
      d.elements.add(DesignElement(
        tool: ToolType.punktGps,
        ref: GeomRef(kind: 'point', frozen: [
          sq.points[2].latitude,
          sq.points[2].longitude,
        ]),
      ));
      final w =
          DesignWorld(parcels: [sq], buildings: const [], designs: [d]);
      final c = w.computeDesign(d);
      expect(c[0].path, hasLength(1));
      expect((c[0].path[0] - w.parcelLocal['P1']![2]).length, closeTo(0, 1e-6));
    });

    test('linia robocza przedłuża krawędź o zapas w obie strony', () {
      final sq = _square();
      final d = Design(
        id: 'D',
        name: 'd',
        createdAt: DateTime.utc(2026),
        workingLines: const [GeomRef(kind: 'parcel', sourceId: 'P1', edge: 0)],
      );
      final w =
          DesignWorld(parcels: [sq], buildings: const [], designs: [d]);
      final ws = w.workingLine(d.workingLines.first, const [], {d.id})!;
      final ring = w.parcelLocal['P1']!;
      final a = ring[0], b = ring[1];
      final perp = (b - a).normalized.perpLeft;
      expect((ws.$1 - a).length, closeTo(500, 1e-6));
      expect((ws.$2 - b).length, closeTo(500, 1e-6));
      // współliniowość z krawędzią (składowa prostopadła ≈ 0)
      expect((ws.$1 - a).dot(perp).abs(), closeTo(0, 1e-6));
      expect((ws.$2 - b).dot(perp).abs(), closeTo(0, 1e-6));
    });

    test('koło: N punktów na obwodzie, każdy w promieniu od środka', () {
      final sq = _square();
      final d = Design(id: 'D', name: 'd', createdAt: DateTime.utc(2026));
      d.elements.add(DesignElement(
          tool: ToolType.kolo,
          ref: const GeomRef(kind: 'parcel', sourceId: 'P1', edge: 0))
        ..radius = 5
        ..curvePoints = 12);
      final w = DesignWorld(parcels: [sq], buildings: const [], designs: [d]);
      final c = w.computeDesign(d);
      expect(c[0].closed, isTrue);
      expect(c[0].stake, hasLength(12));
      // środek = placeOnEdge(a, offset 0, along 0) = wierzchołek 0 działki.
      final center = w.parcelLocal['P1']![0];
      for (final p in c[0].stake) {
        expect((p - center).length, closeTo(5, 1e-6));
      }
    });

    test('koło: curvePoints poza zakresem są przycinane (≥3)', () {
      final sq = _square();
      final d = Design(id: 'D', name: 'd', createdAt: DateTime.utc(2026));
      d.elements.add(DesignElement(
          tool: ToolType.kolo,
          ref: const GeomRef(kind: 'parcel', sourceId: 'P1', edge: 0))
        ..curvePoints = 1);
      final w = DesignWorld(parcels: [sq], buildings: const [], designs: [d]);
      expect(w.computeDesign(d)[0].stake, hasLength(3));
    });

    test('łuk: N punktów na rozwarciu, otwarty, w promieniu od środka', () {
      final sq = _square();
      final d = Design(id: 'D', name: 'd', createdAt: DateTime.utc(2026));
      d.elements.add(DesignElement(
          tool: ToolType.luk,
          ref: const GeomRef(kind: 'parcel', sourceId: 'P1', edge: 0))
        ..radius = 5
        ..curvePoints = 5
        ..azimuth = 0
        ..sweep = 90);
      final w = DesignWorld(parcels: [sq], buildings: const [], designs: [d]);
      final c = w.computeDesign(d);
      expect(c[0].closed, isFalse);
      expect(c[0].stake, hasLength(5));
      final center = w.parcelLocal['P1']![0];
      for (final p in c[0].stake) {
        expect((p - center).length, closeTo(5, 1e-6));
      }
      // azymut startu 0 = północ → pierwszy punkt na (east≈0, north≈+5).
      expect((c[0].stake.first - center).x, closeTo(0, 1e-6));
      expect((c[0].stake.first - center).y, closeTo(5, 1e-6));
      // koniec: azymut 90 = wschód → (east≈+5, north≈0).
      expect((c[0].stake.last - center).x, closeTo(5, 1e-6));
      expect((c[0].stake.last - center).y, closeTo(0, 1e-6));
    });

    test('linia z azymutu: zadana długość i kierunek', () {
      final sq = _square();
      final d = Design(id: 'D', name: 'd', createdAt: DateTime.utc(2026));
      d.elements.add(DesignElement(
          tool: ToolType.liniaAzymut,
          ref: const GeomRef(kind: 'parcel', sourceId: 'P1', edge: 0))
        ..azimuth = 90
        ..length = 8);
      final w = DesignWorld(parcels: [sq], buildings: const [], designs: [d]);
      final c = w.computeDesign(d);
      expect(c[0].path, hasLength(2));
      final start = c[0].path[0], end = c[0].path[1];
      expect((end - start).length, closeTo(8, 1e-6));
      // azymut 90 = wschód → przyrost tylko po east (+x).
      expect((end - start).x, closeTo(8, 1e-6));
      expect((end - start).y, closeTo(0, 1e-6));
    });

    test('odsunięcie obrysu: zamknięty pierścień o tej samej liczbie wierzchołków',
        () {
      final sq = _square();
      final d = Design(id: 'D', name: 'd', createdAt: DateTime.utc(2026));
      d.elements.add(DesignElement(
          tool: ToolType.obrysOdsuniety,
          ref: const GeomRef(kind: 'parcel', sourceId: 'P1', edge: 0))
        ..offset = 2);
      final w = DesignWorld(parcels: [sq], buildings: const [], designs: [d]);
      final c = w.computeDesign(d);
      expect(c[0].closed, isTrue);
      expect(c[0].path, hasLength(w.parcelLocal['P1']!.length));
      // Naroża prostokąta (90°) przy odsunięciu o 2 m przesuwają się po
      // przekątnej o 2·√2 ≈ 2,83 m — równoległe przesunięcie obrysu.
      // (Dokładne współrzędne sprawdza test offsetRing w construction_test.)
      final ring = w.parcelLocal['P1']!;
      for (var i = 0; i < ring.length; i++) {
        expect((c[0].path[i] - ring[i]).length, closeTo(2.8284, 0.02));
      }
    });

    test('cykl cross-design nie zawiesza — przerywany', () {
      final a = Design(id: 'A', name: 'a', createdAt: DateTime.utc(2026));
      a.elements.add(DesignElement(
          tool: ToolType.rownolegla,
          ref: const GeomRef(kind: 'design', sourceId: 'B', element: 0, edge: 0)));
      final b = Design(id: 'B', name: 'b', createdAt: DateTime.utc(2026));
      b.elements.add(DesignElement(
          tool: ToolType.rownolegla,
          ref: const GeomRef(kind: 'design', sourceId: 'A', element: 0, edge: 0)));
      final world = DesignWorld(
          parcels: [_square()], buildings: const [], designs: [a, b]);
      final c = world.computeDesign(a);
      expect(c, hasLength(1));
      expect(c[0].isEmpty, isTrue); // odniesienie nierozwiązywalne (cykl)
    });
  });
}
