import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
