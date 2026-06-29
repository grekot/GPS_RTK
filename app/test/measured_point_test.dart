import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:gps_rtk_app/models/measured_point.dart';
import 'package:gps_rtk_app/models/rtk_position.dart';

void main() {
  final p = MeasuredPoint(
    id: '1',
    latitude: 49.8964,
    longitude: 20.6156,
    rms: 0.012,
    meanAccuracy: 0.02,
    samples: 20,
    worstFix: FixType.rtkFixed,
    measuredAt: DateTime.utc(2026, 6, 13, 10),
    label: 'pkt 1',
    parcelId: '120205_2.0001.222/1',
    targetIndex: 0,
    devDistance: 0.18,
    devNorth: 0.12,
    devEast: -0.13,
  );

  test('JSON roundtrip zachowuje pola', () {
    final annotated = p.copyWith(note: 'studzienka', photoPath: '/x/1.jpg');
    final back = MeasuredPoint.fromJson(annotated.toJson());
    expect(back.latitude, p.latitude);
    expect(back.worstFix, FixType.rtkFixed);
    expect(back.devDistance, 0.18);
    expect(back.parcelId, p.parcelId);
    expect(back.targetIndex, 0);
    expect(back.note, 'studzienka');
    expect(back.photoPath, '/x/1.jpg');
  });

  test('copyWith: usuwanie zdjęcia i ustawianie notatki', () {
    final withPhoto = p.copyWith(photoPath: '/x/1.jpg', note: 'a');
    expect(withPhoto.photoPath, '/x/1.jpg');
    final cleared = withPhoto.copyWith(removePhoto: true);
    expect(cleared.photoPath, isNull);
    expect(cleared.note, 'a'); // notatka zostaje
  });

  test('GeoJSON: FeatureCollection z punktem [lon,lat] i właściwościami', () {
    final gj = jsonDecode(measuredPointsToGeoJson(
        [p.copyWith(note: 'hydrant')])) as Map<String, dynamic>;
    expect(gj['type'], 'FeatureCollection');
    final feat = (gj['features'] as List).single as Map<String, dynamic>;
    final coords = feat['geometry']['coordinates'] as List;
    expect(coords[0], closeTo(20.6156, 1e-9)); // lon pierwsze
    expect(coords[1], closeTo(49.8964, 1e-9));
    expect(feat['properties']['notatka'], 'hydrant');
  });

  test('CSV ma nagłówek z notatką i wiersz z odchyłką', () {
    final csv = measuredPointsToCsv([p.copyWith(note: 'rura PE')]);
    final lines = csv.trim().split('\n');
    expect(lines.first, contains('notatka'));
    expect(lines.length, 2);
    expect(lines[1], contains('pkt 1'));
    expect(lines[1], contains('RTK Fixed'));
    expect(lines[1], contains('0.180')); // dev_m
    expect(lines[1], contains('rura PE'));
  });

  group('wysokość', () {
    final pAlt = MeasuredPoint(
      id: '2',
      latitude: 49.8964,
      longitude: 20.6156,
      altitude: 250.123,
      rms: 0.012,
      meanAccuracy: 0.02,
      samples: 20,
      worstFix: FixType.rtkFixed,
      measuredAt: DateTime.utc(2026, 6, 13, 10),
      label: 'pkt 2',
    );

    test('JSON round-trip zachowuje wysokość (i null gdy brak)', () {
      expect(MeasuredPoint.fromJson(pAlt.toJson()).altitude,
          closeTo(250.123, 1e-9));
      expect(MeasuredPoint.fromJson(p.toJson()).altitude, isNull);
    });

    test('copyWith zachowuje wysokość', () {
      expect(pAlt.copyWith(note: 'x').altitude, closeTo(250.123, 1e-9));
    });

    test('CSV ma kolumnę wys_m z wartością; pusta gdy brak wysokości', () {
      final csv = measuredPointsToCsv([pAlt, p]);
      final lines = csv.trim().split('\n');
      expect(lines.first, contains('wys_m'));
      expect(lines[1], contains('250.123'));
    });

    test('GeoJSON: wysokość jako 3. współrzędna i właściwość wys_m', () {
      final gj =
          jsonDecode(measuredPointsToGeoJson([pAlt])) as Map<String, dynamic>;
      final feat = (gj['features'] as List).single as Map<String, dynamic>;
      final coords = feat['geometry']['coordinates'] as List;
      expect(coords.length, 3);
      expect(coords[2], closeTo(250.123, 1e-9));
      expect(feat['properties']['wys_m'], closeTo(250.123, 1e-9));
    });

    test('GeoJSON bez wysokości: tylko [lon,lat]', () {
      final gj =
          jsonDecode(measuredPointsToGeoJson([p])) as Map<String, dynamic>;
      final feat = (gj['features'] as List).single as Map<String, dynamic>;
      expect((feat['geometry']['coordinates'] as List).length, 2);
    });
  });
}
