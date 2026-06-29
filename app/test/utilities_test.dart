import 'package:flutter_test/flutter_test.dart';

import 'package:gps_rtk_app/map/tile_math.dart';
import 'package:gps_rtk_app/measure/utility_category.dart';
import 'package:gps_rtk_app/models/measured_point.dart';
import 'package:gps_rtk_app/models/rtk_position.dart';
import 'package:gps_rtk_app/services/kiut_service.dart';

void main() {
  group('UtilityCategory', () {
    test('fromCode mapuje kod na kategorię', () {
      expect(UtilityCategory.fromCode('gaz'), UtilityCategory.gaz);
      expect(UtilityCategory.fromCode('woda'), UtilityCategory.woda);
    });

    test('fromCode dla null/nieznanego = null', () {
      expect(UtilityCategory.fromCode(null), isNull);
      expect(UtilityCategory.fromCode('xyz'), isNull);
    });
  });

  group('lonLatToMercator', () {
    test('(0,0) -> (0,0)', () {
      final m = lonLatToMercator(0, 0);
      expect(m.x, closeTo(0, 1e-6));
      expect(m.y, closeTo(0, 1e-6));
    });

    test('Gnojnik ~ (2.29 mln E, 6.43 mln N)', () {
      // wartość referencyjna policzona niezależnie wzorem Web Mercator.
      final m = lonLatToMercator(20.6156, 49.8964);
      expect(m.x, closeTo(2294918, 1000));
      expect(m.y, closeTo(6428353, 1000));
    });
  });

  group('KiutService', () {
    test('featureInfoUrl ma poprawne parametry GetFeatureInfo', () {
      final uri = KiutService.featureInfoUrl(20.6156, 49.8964);
      expect(uri.host, 'integracja.gugik.gov.pl');
      expect(uri.queryParameters['REQUEST'], 'GetFeatureInfo');
      expect(uri.queryParameters['SRS'], 'EPSG:3857');
      expect(uri.queryParameters['QUERY_LAYERS'], contains('przewod_gazowy'));
      expect(uri.queryParameters['BBOX'], isNotNull);
    });

    test('stripHtml usuwa znaczniki i normalizuje spacje', () {
      expect(
        KiutService.stripHtml('<table><tr><td>Wodociąg</td></tr></table>'),
        'Wodociąg',
      );
      expect(KiutService.stripHtml('<br>  &nbsp; <b>x</b>'), 'x');
    });
  });

  test('CSV zawiera kolumnę kategoria i kod medium', () {
    final p = MeasuredPoint(
      id: 'u1',
      latitude: 49.8964,
      longitude: 20.6156,
      rms: 0.01,
      meanAccuracy: 0.02,
      samples: 20,
      worstFix: FixType.rtkFixed,
      measuredAt: DateTime.utc(2026, 6, 13),
      label: 'Gaz',
      category: 'gaz',
    );
    final csv = measuredPointsToCsv([p]);
    final lines = csv.trim().split('\n');
    expect(lines.first, contains('kategoria'));
    expect(lines[1].split(';')[1], 'gaz'); // druga kolumna = kategoria
  });
}
