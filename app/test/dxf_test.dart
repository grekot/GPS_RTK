import 'package:flutter_test/flutter_test.dart';

import 'package:gps_rtk_app/models/measured_point.dart';
import 'package:gps_rtk_app/models/rtk_position.dart';
import 'package:gps_rtk_app/utils/dxf.dart';
import 'package:gps_rtk_app/utils/pl2000.dart';

int _count(String s, String needle) => needle.allMatches(s).length;

void main() {
  test('pusty dokument ma poprawną strukturę DXF', () {
    final dxf = DxfBuilder().build();
    expect(dxf, startsWith('0\r\nSECTION'));
    expect(dxf, contains('ENTITIES'));
    expect(dxf, contains('TABLES'));
    expect(dxf.trimRight(), endsWith('EOF'));
  });

  test('polilinia: poprawna liczba VERTEX, SEQEND, warstwa w tabeli', () {
    final dxf = (DxfBuilder()
          ..addPolyline(
            [
              [0, 0],
              [10, 0],
              [10, 10],
            ],
            layer: 'TEST',
            color: 3,
            closed: true,
          ))
        .build();
    expect(_count(dxf, 'POLYLINE'), 1);
    expect(_count(dxf, 'VERTEX'), 3);
    expect(_count(dxf, 'SEQEND'), 1);
    // warstwa zadeklarowana w tabeli LAYER (z kolorem 3).
    expect(dxf, contains('LAYER'));
    expect(dxf, contains('TEST'));
    expect(dxf, contains('\r\n62\r\n3\r\n'));
  });

  test('punkt z etykietą tworzy POINT i TEXT', () {
    final dxf = (DxfBuilder()
          ..addPoint(7500000.0, 5500000.0,
              layer: 'PUNKTY', color: 1, label: 'A1'))
        .build();
    expect(_count(dxf, '\r\nPOINT\r\n'), 1);
    expect(_count(dxf, '\r\nTEXT\r\n'), 1);
    expect(dxf, contains('A1'));
    // współrzędne zapisane (x=easting, y=northing).
    expect(dxf, contains('7500000.000'));
    expect(dxf, contains('5500000.000'));
  });

  test('punkt bez etykiety nie dodaje TEXT', () {
    final dxf =
        (DxfBuilder()..addPoint(0, 0, layer: 'X')).build();
    expect(_count(dxf, '\r\nTEXT\r\n'), 0);
  });

  test('measuredPointsToDxf: punkt na warstwie PUNKTY w PL-2000', () {
    final p = MeasuredPoint(
      id: '1',
      latitude: 49.8964,
      longitude: 20.6156,
      rms: 0.01,
      meanAccuracy: 0.02,
      samples: 10,
      worstFix: FixType.rtkFixed,
      measuredAt: DateTime.utc(2026, 6, 13),
      label: 'pkt 1',
    );
    final dxf = measuredPointsToDxf([p]);
    expect(dxf, contains('PUNKTY'));
    expect(dxf, contains('pkt 1'));
    // easting PL-2000 powinien pojawić się jako współrzędna X w DXF.
    final pl = Pl2000.fromLatLon(p.latitude, p.longitude);
    expect(dxf, contains(pl.easting.toStringAsFixed(3)));
  });

  test('liczba wpisów w tabeli LAYER = liczba użytych warstw', () {
    final dxf = (DxfBuilder()
          ..addPoint(0, 0, layer: 'A')
          ..addPoint(1, 1, layer: 'B')
          ..addPoint(2, 2, layer: 'A')) // ta sama warstwa — bez duplikatu
        .build();
    // liczymy wpisy warstw (0/LAYER), nie nazwę tabeli (2/LAYER).
    expect(_count(dxf, '0\r\nLAYER\r\n'), 2); // A i B (jedna deklaracja A)
  });
}
