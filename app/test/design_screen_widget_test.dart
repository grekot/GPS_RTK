import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'package:gps_rtk_app/models/design.dart';
import 'package:gps_rtk_app/models/parcel.dart';
import 'package:gps_rtk_app/screens/design_screen.dart';
import 'package:gps_rtk_app/sources/phone_gnss_source.dart';

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

Widget _screen(Design d, Parcel sq) => MaterialApp(
      home: DesignScreen(
        design: d,
        parcels: [sq],
        buildings: const [],
        designs: [d],
        measuredPoints: const [],
        source: PhoneGnssSource(),
        onSave: (_) {},
      ),
    );

void main() {
  // Regresja: zaznaczenie „linii między punktami" wywoływało panel parametrów
  // (`_paramRow`), który dla elementu BEZ pól robił `.clamp(1, 0)` → ArgumentError
  // „Invalid argument(s): 1" i czerwony ekran. Panel musi renderować się bez
  // wyjątku. (Test modelu tego nie łapał — to była ścieżka UI.)
  testWidgets('zaznaczenie linii punkt-punkt nie wywala panelu parametrów',
      (tester) async {
    final sq = _square();
    final d = Design(id: 'D', name: 'Test', createdAt: DateTime.utc(2026));
    d.elements.add(DesignElement(
      tool: ToolType.liniaPunkty,
      ref: GeomRef(kind: 'frozen', frozen: [
        sq.points[0].latitude,
        sq.points[0].longitude,
        sq.points[2].latitude,
        sq.points[2].longitude,
      ]),
    ));

    await tester.pumpWidget(_screen(d, sq));
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull); // render bez zaznaczenia

    // Zaznacz element przez listę elementów → rebuild panelu parametrów.
    await tester.tap(find.byTooltip('Lista elementów'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1. Linia między punktami'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull); // panel nie rzuca ArgumentError
    expect(find.textContaining('Linia między punktami'), findsWidgets);
  });

  // Linijka: wejście w tryb pomiaru + dwa tapnięcia na mapie → baner z wynikiem.
  testWidgets('linijka: pomiar odległości między dwoma punktami', (tester) async {
    final sq = _square();
    final d = Design(id: 'D', name: 'Test', createdAt: DateTime.utc(2026));

    await tester.pumpWidget(_screen(d, sq));
    await tester.pump(const Duration(milliseconds: 50));

    // Wejdź w tryb pomiaru przez ikonę „Pomiar" na górnej belce.
    await tester.tap(find.byTooltip('Pomiar odległości (linijka)'));
    await tester.pumpAndSettle();
    expect(find.textContaining('wskaż pierwszy punkt'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Dwa tapnięcia na mapie (górna część ekranu) → pomiar.
    await tester.tapAt(const Offset(200, 250));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(360, 360));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Odległość:'), findsOneWidget);

    // Osusz 4-sekundowy timer SnackBara („wskaż drugi punkt"), inaczej teardown
    // zgłasza „Timer still pending".
    await tester.pump(const Duration(seconds: 5));
  });

  // Widoczność per projekt: NOWY projekt (pusta biała lista) startuje z ukrytymi
  // obcymi geometriami i sam otwiera arkusz widoczności; włączenie działki
  // zapisuje się w projekcie (visibleRefs) — trwałe po zapisie przy wyjściu.
  testWidgets('nowy projekt: obce ukryte, wybór widoczności zapamiętany',
      (tester) async {
    final sq = _square();
    final d = Design(
      id: 'D',
      name: 'Test',
      createdAt: DateTime.utc(2026),
      visibleRefs: {},
    );

    await tester.pumpWidget(_screen(d, sq));
    await tester.pumpAndSettle();

    // Arkusz widoczności otworzył się sam (nic nie widać, brak elementów).
    expect(find.text('Widoczność geometrii'), findsOneWidget);

    // Włącz działkę → klucz trafia do białej listy projektu.
    await tester.tap(find.text('Działka 1'));
    await tester.pumpAndSettle();
    expect(d.visibleRefs, contains('parcel:P1'));

    // Wyłącz z powrotem → klucz znika (lista faktycznie odzwierciedla stan).
    await tester.tap(find.text('Działka 1'));
    await tester.pumpAndSettle();
    expect(d.visibleRefs, isNot(contains('parcel:P1')));
  });

  // Zgodność wstecz: projekt sprzed funkcji (visibleRefs == null) nie otwiera
  // arkusza i pokazuje wszystko jak dotychczas.
  testWidgets('stary projekt (bez visibleRefs): bez auto-arkusza widoczności',
      (tester) async {
    final sq = _square();
    final d = Design(id: 'D', name: 'Test', createdAt: DateTime.utc(2026));

    await tester.pumpWidget(_screen(d, sq));
    await tester.pumpAndSettle();

    expect(find.text('Widoczność geometrii'), findsNothing);
    expect(d.visibleRefs, isNull);
  });

  // Precyzyjne rysowanie: przyciski +/- zoomują mapę (pinch przy dużym
  // powiększeniu jest zbyt zgrubny), limit podniesiony ponad natywny zoom
  // ortofoto (wektory zostają ostre).
  testWidgets('przyciski zoomu przybliżają i oddalają mapę', (tester) async {
    final sq = _square();
    final d = Design(id: 'D', name: 'Test', createdAt: DateTime.utc(2026));

    await tester.pumpWidget(_screen(d, sq));
    await tester.pump(const Duration(milliseconds: 50));

    final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
    final z0 = map.mapController!.camera.zoom;

    await tester.tap(find.byTooltip('Przybliż'));
    await tester.pump();
    expect(map.mapController!.camera.zoom, closeTo(z0 + 1, 1e-6));

    await tester.tap(find.byTooltip('Oddal'));
    await tester.pump();
    expect(map.mapController!.camera.zoom, closeTo(z0, 1e-6));
  });
}
