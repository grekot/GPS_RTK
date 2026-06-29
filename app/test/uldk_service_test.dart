import 'package:flutter_test/flutter_test.dart';

import 'package:gps_rtk_app/services/uldk_service.dart';

void main() {
  const sampleRecord =
      'SRID=4326;POLYGON((20.61 49.89,20.62 49.89,20.62 49.90,20.61 49.89))'
      '|120205_2.0001.222/1|222/1|Gnojnik|Gnojnik|powiat brzeski';

  test('parsuje odpowiedź ze statusem "1" i jednym rekordem', () {
    final parcels = UldkService.parseResponse('1\n$sampleRecord\n');
    expect(parcels, hasLength(1));
    final p = parcels.first;
    expect(p.id, '120205_2.0001.222/1');
    expect(p.number, '222/1');
    expect(p.region, 'Gnojnik');
    expect(p.commune, 'Gnojnik');
    expect(p.county, 'powiat brzeski');
    expect(p.points, hasLength(4));
    expect(p.points.first.latitude, closeTo(49.89, 1e-9));
    expect(p.points.first.longitude, closeTo(20.61, 1e-9));
  });

  test('parsuje odpowiedź z wieloma rekordami', () {
    final parcels =
        UldkService.parseResponse('2\n$sampleRecord\n$sampleRecord\n');
    expect(parcels, hasLength(2));
  });

  test('odpowiedź bez linii statusu też przechodzi', () {
    final parcels = UldkService.parseResponse('$sampleRecord\n');
    expect(parcels, hasLength(1));
  });

  test('status "-1 brak wyników" rzuca UldkException z komunikatem', () {
    expect(
      () => UldkService.parseResponse('-1 brak wyników\n'),
      throwsA(
        isA<UldkException>().having(
          (e) => e.message,
          'message',
          contains('brak wyników'),
        ),
      ),
    );
  });

  test('status "0" z rekordem to sukces (format GetParcelByXY)', () {
    final parcels = UldkService.parseResponse('0\n$sampleRecord\n');
    expect(parcels, hasLength(1));
  });

  test('status "0" bez rekordów rzuca UldkException', () {
    expect(
      () => UldkService.parseResponse('0\n'),
      throwsA(isA<UldkException>()),
    );
  });

  test('pusta odpowiedź rzuca UldkException', () {
    expect(
      () => UldkService.parseResponse('  \n'),
      throwsA(isA<UldkException>()),
    );
  });

  test('geometria inna niż POLYGON rzuca UldkException', () {
    expect(
      () => UldkService.parseWktPolygon('SRID=4326;POINT(20.61 49.89)'),
      throwsA(isA<UldkException>()),
    );
  });

  test('parseBuilding wyciąga obrys i id (geom_wkt|id)', () {
    const body = '0\n'
        'SRID=4326;POLYGON((20.61 49.89,20.62 49.89,20.62 49.90,20.61 49.89))'
        '|120205_2.0001.BU_123\n';
    final b = UldkService.parseBuilding(body);
    expect(b.id, '120205_2.0001.BU_123');
    expect(b.points, hasLength(4));
    expect(b.points.first.latitude, closeTo(49.89, 1e-9));
  });

  test('parseBuilding dla braku wyników rzuca UldkException', () {
    expect(
      () => UldkService.parseBuilding('-1 brak wyników\n'),
      throwsA(isA<UldkException>()),
    );
  });
}
