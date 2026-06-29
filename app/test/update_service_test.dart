import 'package:flutter_test/flutter_test.dart';

import 'package:gps_rtk_app/services/update_service.dart';

void main() {
  group('isNewer — porównanie wersji', () {
    test('nowszy major/minor/patch', () {
      expect(UpdateService.isNewer('v1.1.0', '1.0.0'), isTrue);
      expect(UpdateService.isNewer('2.0.0', '1.9.9'), isTrue);
      expect(UpdateService.isNewer('1.0.1', '1.0.0'), isTrue);
    });

    test('równe lub starsze → brak aktualizacji', () {
      expect(UpdateService.isNewer('1.0.0', '1.0.0'), isFalse);
      expect(UpdateService.isNewer('v1.0.0', '1.1.0'), isFalse);
      expect(UpdateService.isNewer('0.9.0', '1.0.0'), isFalse);
    });

    test('prefiks v i brakujące segmenty', () {
      expect(UpdateService.isNewer('v1.2', '1.1.9'), isTrue); // 1.2 > 1.1.9
      expect(UpdateService.isNewer('1.0', '1.0.0'), isFalse); // równe
    });

    test('sufiks build (+N / -beta) jest pomijany', () {
      expect(UpdateService.isNewer('1.0.1+5', '1.0.1'), isFalse);
      expect(UpdateService.isNewer('v1.1.0-beta', '1.0.0'), isTrue);
    });

    test('pusty tag → brak aktualizacji', () {
      expect(UpdateService.isNewer('', '1.0.0'), isFalse);
    });
  });

  group('parseRelease — wyłuskanie pól', () {
    test('wybiera asset .apk i pola release', () {
      final r = UpdateService.parseRelease({
        'tag_name': 'v1.2.0',
        'body': 'Co nowego: poprawki',
        'html_url': 'https://github.com/grekot/GPS_RTK/releases/tag/v1.2.0',
        'assets': [
          {'name': 'notes.txt', 'browser_download_url': 'http://x/notes.txt'},
          {'name': 'gps_rtk.apk', 'browser_download_url': 'http://x/gps_rtk.apk'},
        ],
      });
      expect(r.tag, 'v1.2.0');
      expect(r.notes, 'Co nowego: poprawki');
      expect(r.releaseUrl, contains('releases/tag/v1.2.0'));
      expect(r.apkUrl, 'http://x/gps_rtk.apk');
    });

    test('brak assetu .apk → apkUrl null', () {
      final r = UpdateService.parseRelease({
        'tag_name': '1.0.0',
        'assets': [
          {'name': 'source.zip', 'browser_download_url': 'http://x/s.zip'},
        ],
      });
      expect(r.apkUrl, isNull);
      expect(r.tag, '1.0.0');
    });

    test('brak assetów / pól → bezpieczne wartości', () {
      final r = UpdateService.parseRelease({'tag_name': 'v2.0.0'});
      expect(r.apkUrl, isNull);
      expect(r.notes, '');
      expect(r.releaseUrl, '');
    });
  });
}
