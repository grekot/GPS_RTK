import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:gps_rtk_app/services/update_service.dart';

const _apk =
    'https://github.com/grekot/GPS_RTK/releases/download/v1.2.0/gps_rtk.apk';

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
          {
            'name': 'gps_rtk.apk',
            'browser_download_url': _apk,
            'digest': 'sha256:${'AB' * 32}',
          },
        ],
      });
      expect(r.tag, 'v1.2.0');
      expect(r.notes, 'Co nowego: poprawki');
      expect(r.releaseUrl, contains('releases/tag/v1.2.0'));
      expect(r.apkUrl, _apk);
      expect(r.apkSha256, 'ab' * 32);
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

  group('zaufane źródło pobierania', () {
    test('tylko HTTPS z GitHuba', () {
      expect(isTrustedDownloadUrl(_apk), isTrue);
      expect(
          isTrustedDownloadUrl(
              'https://objects.githubusercontent.com/github-production-release-asset/x'),
          isTrue);
      expect(isTrustedDownloadUrl('http://github.com/a.apk'), isFalse);
      expect(isTrustedDownloadUrl('https://evil.example/a.apk'), isFalse);
      expect(isTrustedDownloadUrl('https://github.com.evil.example/a.apk'),
          isFalse);
      expect(isTrustedDownloadUrl(null), isFalse);
    });

    test('parseRelease pomija asset .apk spoza GitHuba', () {
      final r = UpdateService.parseRelease({
        'tag_name': 'v9',
        'assets': [
          {'name': 'x.apk', 'browser_download_url': 'https://evil.example/x.apk'},
        ],
      });
      expect(r.apkUrl, isNull);
    });

    test('nieprawidłowy digest jest ignorowany', () {
      final r = UpdateService.parseRelease({
        'assets': [
          {'name': 'a.apk', 'browser_download_url': _apk, 'digest': 'md5:abc'},
        ],
      });
      expect(r.apkUrl, _apk);
      expect(r.apkSha256, isNull);
    });
  });

  group('downloadApk', () {
    late Directory tmp;
    setUp(() async => tmp = await Directory.systemTemp.createTemp('upd'));
    tearDown(() async => tmp.delete(recursive: true));

    final body = List<int>.generate(5000, (i) => i % 251);
    final goodSha = sha256.convert(body).toString();

    UpdateService svc(http.Client c,
            {Duration stall = const Duration(seconds: 5)}) =>
        UpdateService(client: c, tempDir: () async => tmp, stallTimeout: stall);

    MockClient serving(List<int> data) => MockClient.streaming((req, _) async =>
        http.StreamedResponse(Stream.value(data), 200,
            contentLength: data.length));

    test('pobiera plik i akceptuje zgodny SHA-256', () async {
      final progress = <double>[];
      final path = await svc(serving(body))
          .downloadApk(_apk, expectedSha256: goodSha, onProgress: progress.add);
      expect(await File(path).readAsBytes(), body);
      expect(progress.last, 1.0);
    });

    test('niezgodny SHA-256 → błąd i usunięty plik', () async {
      await expectLater(
        svc(serving(body)).downloadApk(_apk, expectedSha256: '0' * 64),
        throwsA(isA<StateError>()),
      );
      expect(File('${tmp.path}/gps_rtk_update.apk').existsSync(), isFalse);
    });

    test('link spoza GitHuba odrzucony bez łączenia', () async {
      var called = false;
      final c = MockClient((_) async {
        called = true;
        return http.Response('', 200);
      });
      await expectLater(svc(c).downloadApk('https://evil.example/a.apk'),
          throwsA(isA<StateError>()));
      expect(called, isFalse);
    });

    test('Anuluj przerywa zawieszone pobieranie', () async {
      final ctrl = StreamController<List<int>>();
      final c = MockClient.streaming((req, _) async =>
          http.StreamedResponse(ctrl.stream, 200, contentLength: 10000));
      final cancel = UpdateCancelToken();
      final f = svc(c).downloadApk(_apk, cancel: cancel);
      ctrl.add([1, 2, 3]);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      cancel.cancel();
      await expectLater(f, throwsA(isA<UpdateCancelled>()));
      expect(File('${tmp.path}/gps_rtk_update.apk').existsSync(), isFalse);
      await ctrl.close();
    });

    test('brak danych dłużej niż limit → błąd zamiast wiecznego czekania',
        () async {
      final ctrl = StreamController<List<int>>();
      final c = MockClient.streaming((req, _) async =>
          http.StreamedResponse(ctrl.stream, 200, contentLength: 10000));
      await expectLater(
        svc(c, stall: const Duration(milliseconds: 100)).downloadApk(_apk),
        throwsA(isA<StateError>()),
      );
      await ctrl.close();
    });
  });
}
