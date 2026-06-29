import 'package:flutter_test/flutter_test.dart';

import 'package:gps_rtk_app/measure/point_averager.dart';
import 'package:gps_rtk_app/models/rtk_position.dart';

RtkPosition _pos(
  double lat,
  double lon, {
  FixType fix = FixType.rtkFixed,
  double acc = 0.02,
  double? alt,
}) =>
    RtkPosition(
      latitude: lat,
      longitude: lon,
      altitude: alt,
      accuracy: acc,
      fixType: fix,
      timestamp: DateTime.utc(2026, 6, 13),
    );

void main() {
  test('identyczne próbki: średnia = punkt, RMS = 0', () {
    final a = PointAverager(targetSamples: 5);
    for (var i = 0; i < 5; i++) {
      a.add(_pos(49.8964, 20.6156));
    }
    expect(a.isComplete, isTrue);
    final r = a.finalize()!;
    expect(r.samples, 5);
    expect(r.mean.latitude, closeTo(49.8964, 1e-9));
    expect(r.mean.longitude, closeTo(20.6156, 1e-9));
    expect(r.rms, closeTo(0, 1e-6));
    expect(r.meanAccuracy, closeTo(0.02, 1e-9));
  });

  test('bramka jakości odrzuca FixType.none', () {
    final a = PointAverager();
    expect(a.add(_pos(49.8964, 20.6156, fix: FixType.none)), isFalse);
    expect(a.count, 0);
    expect(a.finalize(), isNull);
  });

  test('zapamiętuje najgorszy i najlepszy fix', () {
    final a = PointAverager()
      ..add(_pos(49.8964, 20.6156, fix: FixType.gps))
      ..add(_pos(49.8964, 20.6156, fix: FixType.rtkFixed))
      ..add(_pos(49.8964, 20.6156, fix: FixType.rtkFloat));
    final r = a.finalize()!;
    expect(r.worstFix, FixType.gps); // najniższa ranga
    expect(r.bestFix, FixType.rtkFixed); // najwyższa ranga
  });

  test('RMS > 0 dla rozrzuconych próbek, średnia pośrodku', () {
    final a = PointAverager(targetSamples: 2)
      ..add(_pos(49.89640, 20.61560))
      ..add(_pos(49.89641, 20.61560)); // ~1,1 m na północ
    final r = a.finalize()!;
    expect(r.rms, greaterThan(0.3));
    expect(r.rms, lessThan(1.0));
    expect(r.mean.latitude, closeTo(49.896405, 1e-6));
  });

  test('uśrednia wysokość i liczy rozrzut pionowy', () {
    final a = PointAverager(targetSamples: 3)
      ..add(_pos(49.8964, 20.6156, alt: 249.9))
      ..add(_pos(49.8964, 20.6156, alt: 250.0))
      ..add(_pos(49.8964, 20.6156, alt: 250.1));
    final r = a.finalize()!;
    expect(r.meanAltitude, closeTo(250.0, 1e-9));
    expect(r.verticalRms, greaterThan(0)); // niezerowy rozrzut
    expect(r.verticalRms, closeTo(0.0816, 1e-3)); // sqrt(mean(0.1²,0,0.1²))
  });

  test('brak wysokości w próbkach → meanAltitude null, verticalRms 0', () {
    final a = PointAverager(targetSamples: 2)
      ..add(_pos(49.8964, 20.6156))
      ..add(_pos(49.8964, 20.6156));
    final r = a.finalize()!;
    expect(r.meanAltitude, isNull);
    expect(r.verticalRms, 0);
  });

  test('miesza próbki z wysokością i bez — średnia z dostępnych', () {
    final a = PointAverager(targetSamples: 3)
      ..add(_pos(49.8964, 20.6156, alt: 100))
      ..add(_pos(49.8964, 20.6156)) // bez wysokości — pomijana w średniej
      ..add(_pos(49.8964, 20.6156, alt: 102));
    final r = a.finalize()!;
    expect(r.meanAltitude, closeTo(101, 1e-9));
  });
}
