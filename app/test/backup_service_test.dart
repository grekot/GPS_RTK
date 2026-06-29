import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:gps_rtk_app/models/building.dart';
import 'package:gps_rtk_app/models/design.dart';
import 'package:gps_rtk_app/models/measured_point.dart';
import 'package:gps_rtk_app/models/parcel.dart';
import 'package:gps_rtk_app/models/rtk_position.dart';
import 'package:gps_rtk_app/services/backup_service.dart';

void main() {
  final point = MeasuredPoint(
    id: 'pt1',
    latitude: 49.8964,
    longitude: 20.6156,
    altitude: 250.0,
    rms: 0.01,
    meanAccuracy: 0.02,
    samples: 20,
    worstFix: FixType.rtkFixed,
    measuredAt: DateTime.utc(2026, 6, 28),
    label: 'reper',
  );
  final design = Design(id: 'D1', name: 'Ogrodzenie', createdAt: DateTime.utc(2026))
    ..elements.add(DesignElement(
        tool: ToolType.rownolegla,
        ref: const GeomRef(kind: 'parcel', sourceId: 'P1', edge: 0))
      ..offset = 1.5);
  final parcel = Parcel(
    id: 'P1',
    number: '222/1',
    region: '',
    commune: '',
    county: '',
    fetchedAt: DateTime.utc(2026),
    points: const [
      LatLng(49.8964, 20.6156),
      LatLng(49.8965, 20.6156),
      LatLng(49.8965, 20.6157),
    ],
  );
  final building = Building(
    id: 'B1',
    fetchedAt: DateTime.utc(2026),
    points: const [LatLng(49.8964, 20.6156), LatLng(49.8965, 20.6157)],
  );

  String bundleJson() => jsonEncode(BackupService.toBundle(
        points: [point],
        designs: [design],
        parcels: [parcel],
        buildings: [building],
      ));

  test('toBundle → parseBundle: round-trip zachowuje wszystkie kategorie', () {
    final b = BackupService.parseBundle(bundleJson());
    expect(b.points, hasLength(1));
    expect(b.designs, hasLength(1));
    expect(b.parcels, hasLength(1));
    expect(b.buildings, hasLength(1));
    expect(b.points.first.label, 'reper');
    expect(b.points.first.altitude, closeTo(250.0, 1e-9));
    expect(b.designs.first.name, 'Ogrodzenie');
    expect(b.designs.first.elements.first.offset, 1.5);
    expect(b.parcels.first.number, '222/1');
    expect(b.buildings.first.id, 'B1');
  });

  test('nagłówek app=gps_rtk i wersja są w kopii', () {
    final j = jsonDecode(bundleJson()) as Map<String, dynamic>;
    expect(j['app'], 'gps_rtk');
    expect(j['version'], BackupService.formatVersion);
  });

  test('obcy JSON → FormatException', () {
    expect(() => BackupService.parseBundle('{"foo":1}'),
        throwsA(isA<FormatException>()));
    expect(() => BackupService.parseBundle('[]'),
        throwsA(isA<FormatException>()));
  });

  test('brakujące sekcje → puste listy (bez wywrotki)', () {
    final b = BackupService.parseBundle('{"app":"gps_rtk","version":1}');
    expect(b.points, isEmpty);
    expect(b.designs, isEmpty);
    expect(b.parcels, isEmpty);
    expect(b.buildings, isEmpty);
  });
}
