import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:gps_rtk_app/models/stakeout_project.dart';

void main() {
  final project = StakeoutProject(
    name: 'Podjazd',
    createdAt: DateTime.utc(2026, 6, 14, 12),
    reference: const [
      LatLng(49.8960, 20.6150),
      LatLng(49.8962, 20.6150),
      LatLng(49.8962, 20.6154),
      LatLng(49.8960, 20.6154),
    ],
    construction: const [
      LatLng(49.89605, 20.61505),
      LatLng(49.89615, 20.61505),
      LatLng(49.89615, 20.61535),
      LatLng(49.89605, 20.61535),
    ],
    constructionClosed: true,
    stakePoints: const [
      LatLng(49.89605, 20.61505),
      LatLng(49.89615, 20.61505),
      LatLng(49.89615, 20.61535),
    ],
  );

  test('GeoJSON jest poprawnym FeatureCollection z rolami', () {
    final gj = jsonDecode(project.toGeoJson()) as Map<String, dynamic>;
    expect(gj['type'], 'FeatureCollection');
    expect(gj['properties']['kind'], 'stakeout-project');
    final roles = [
      for (final f in gj['features'] as List)
        (f['properties'] as Map)['role'],
    ];
    expect(roles, contains('reference'));
    expect(roles, contains('construction'));
    expect(roles.where((r) => r == 'stakeout').length, 3);
  });

  test('roundtrip zachowuje punkty, kolejność i obrys', () {
    final back = StakeoutProject.fromGeoJson(project.toGeoJson());
    expect(back.name, 'Podjazd');
    expect(back.stakePoints, hasLength(3));
    expect(back.stakePoints.first.latitude, closeTo(49.89605, 1e-9));
    expect(back.stakePoints.first.longitude, closeTo(20.61505, 1e-9));
    expect(back.constructionClosed, isTrue);
    expect(back.construction, hasLength(4));
    expect(back.reference, hasLength(4));
    // outline = konstrukcja (gdy jest)
    expect(back.outline.length, 4);
  });

  test('punkty stakeout wracają w kolejności wg index', () {
    // Zaburzona kolejność features, ale index ustala porządek.
    const gj = '''
    {"type":"FeatureCollection","properties":{"name":"X"},"features":[
      {"type":"Feature","properties":{"role":"stakeout","index":1},
       "geometry":{"type":"Point","coordinates":[20.0,50.0]}},
      {"type":"Feature","properties":{"role":"stakeout","index":0},
       "geometry":{"type":"Point","coordinates":[21.0,51.0]}}
    ]}''';
    final p = StakeoutProject.fromGeoJson(gj);
    expect(p.stakePoints.first.longitude, closeTo(21.0, 1e-9)); // index 0
    expect(p.stakePoints.last.longitude, closeTo(20.0, 1e-9)); // index 1
  });

  test('zły JSON rzuca FormatException', () {
    expect(() => StakeoutProject.fromGeoJson('{"type":"X"}'),
        throwsA(isA<FormatException>()));
  });

  test('extraConstructions: round-trip projektu z wieloma figurami', () {
    final multi = StakeoutProject(
      name: 'Multi',
      createdAt: DateTime.utc(2026, 6, 14),
      reference: const [
        LatLng(50.0000, 20.0000),
        LatLng(50.0010, 20.0000),
        LatLng(50.0010, 20.0010),
      ],
      construction: const [
        LatLng(50.0005, 20.0005),
        LatLng(50.0009, 20.0005),
      ],
      extraConstructions: const [
        (
          path: [
            LatLng(50.0002, 20.0002),
            LatLng(50.0008, 20.0002),
            LatLng(50.0008, 20.0009),
          ],
          closed: true,
        ),
        (
          path: [LatLng(50.0003, 20.0006), LatLng(50.0007, 20.0006)],
          closed: false,
        ),
      ],
      stakePoints: const [LatLng(50.0005, 20.0005)],
    );

    // toGeoJson: 1 reference + 3 construction + 1 stakeout.
    final gj = jsonDecode(multi.toGeoJson()) as Map<String, dynamic>;
    final roles = [
      for (final f in gj['features'] as List) (f['properties'] as Map)['role'],
    ];
    expect(roles.where((r) => r == 'construction').length, 3);

    final back = StakeoutProject.fromGeoJson(multi.toGeoJson());
    expect(back.construction, hasLength(2));
    expect(back.constructionClosed, isFalse);
    expect(back.extraConstructions, hasLength(2));
    expect(back.extraConstructions[0].closed, isTrue);
    expect(back.extraConstructions[0].path, hasLength(3));
    expect(back.extraConstructions[1].closed, isFalse);
    expect(back.extraConstructions[1].path, hasLength(2));
  });
}
