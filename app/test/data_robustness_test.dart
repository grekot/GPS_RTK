import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gps_rtk_app/models/design.dart';
import 'package:gps_rtk_app/models/measured_point.dart';
import 'package:gps_rtk_app/models/rtk_position.dart';
import 'package:gps_rtk_app/services/app_settings.dart';
import 'package:gps_rtk_app/services/backup_service.dart';
import 'package:gps_rtk_app/services/design_store.dart';
import 'package:gps_rtk_app/services/measured_point_store.dart';
import 'package:gps_rtk_app/services/photo_service.dart';

MeasuredPoint _pt(String id, {String? photo}) => MeasuredPoint(
      id: id,
      latitude: 49.8964,
      longitude: 20.6156,
      rms: 0.01,
      meanAccuracy: 0.02,
      samples: 20,
      worstFix: FixType.rtkFixed,
      measuredAt: DateTime.utc(2026, 10, 5),
      photoPath: photo,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('magazyn punktów', () {
    test('równoległe zapisy nie gubią punktów (wspólna kolejka)', () async {
      final a = MeasuredPointStore(), b = MeasuredPointStore();
      await Future.wait([
        for (var i = 0; i < 20; i++) (i.isEven ? a : b).add(_pt('p$i')),
      ]);
      expect(await a.loadAll(), hasLength(20));
    });

    test('uszkodzony JSON: pusta lista + kopia w .corrupt, bez wyjątku',
        () async {
      SharedPreferences.setMockInitialValues(
          {'measured_points.v1': '[{"id": "x", BROKEN'});
      expect(await MeasuredPointStore().loadAll(), isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(MeasuredPointStore.corruptKey), contains('BROKEN'));
    });

    test('jeden uszkodzony rekord nie blokuje pozostałych', () async {
      SharedPreferences.setMockInitialValues({
        'measured_points.v1':
            jsonEncode([_pt('ok').toJson(), {'id': 'zly'}]),
      });
      final all = await MeasuredPointStore().loadAll();
      expect(all.map((p) => p.id), ['ok']);
    });

    test('nieznana wartość fixa (nowsza wersja) → FixType.none', () {
      final j = _pt('a').toJson()..['fix'] = 'ppp';
      expect(MeasuredPoint.fromJson(j).worstFix, FixType.none);
    });
  });

  group('ustawienia i projekty', () {
    test('uszkodzone ustawienia → wartości domyślne zamiast awarii startu',
        () async {
      SharedPreferences.setMockInitialValues({'settings.v1': '{oops'});
      AppSettings.instance = AppSettings(samples: 7);
      await AppSettings.load();
      expect(AppSettings.instance.samples, 7); // bez zmian, bez wyjątku
    });

    test('nieznane narzędzie w projekcie pomija element, nie cały projekt',
        () async {
      final d = Design(id: 'D1', name: 'X', createdAt: DateTime.utc(2026))
        ..elements.add(DesignElement(
            tool: ToolType.rownolegla,
            ref: const GeomRef(kind: 'parcel', sourceId: 'P1', edge: 0)));
      final j = d.toJson();
      (j['elements'] as List).add({
        ...(j['elements'] as List).first as Map<String, dynamic>,
        'tool': 'narzedzieZPrzyszlosci',
      });
      SharedPreferences.setMockInitialValues({'designs.v1': jsonEncode([j])});
      final loaded = await DesignStore().load();
      expect(loaded, hasLength(1));
      expect(loaded.single.elements, hasLength(1));
    });
  });

  group('import kopii zapasowej', () {
    const photos = '/data/user/0/pl.gpsrtk/files/photos';

    test('ścieżka zdjęcia spoza katalogu zdjęć jest usuwana', () async {
      final bundle = jsonEncode(BackupService.toBundle(
        points: [
          _pt('ok', photo: '$photos/ok.jpg'),
          _pt('zly', photo: '/data/user/0/pl.gpsrtk/shared_prefs/Flutter.xml'),
          _pt('trik', photo: '$photos/../shared_prefs/Flutter.xml'),
        ],
        designs: const [],
        parcels: const [],
        buildings: const [],
      ));
      await BackupService(photosDirPath: () async => photos).importJson(bundle);
      final byId = {
        for (final p in await MeasuredPointStore().loadAll()) p.id: p
      };
      expect(byId['ok']!.photoPath, '$photos/ok.jpg');
      expect(byId['zly']!.photoPath, isNull);
      expect(byId['trik']!.photoPath, isNull);
    });

    test('kopia z nowszego formatu jest odrzucana z czytelnym komunikatem', () {
      final raw = jsonEncode({'app': 'gps_rtk', 'version': 99, 'points': []});
      expect(
        () => BackupService.parseBundle(raw),
        throwsA(isA<FormatException>().having(
            (e) => e.message, 'message', contains('nowszej wersji'))),
      );
    });

    test('uszkodzony rekord w kopii jest pomijany', () {
      final raw = jsonEncode({
        'app': 'gps_rtk',
        'version': 1,
        'points': [_pt('ok').toJson(), {'bez': 'pól'}],
      });
      expect(BackupService.parseBundle(raw).points.map((p) => p.id), ['ok']);
    });
  });

  group('PhotoService.isInPhotosDir', () {
    test('plik w katalogu — tak; poza nim, ".." lub sam katalog — nie', () {
      const d = r'C:\app\photos';
      expect(PhotoService.isInPhotosDir(r'C:\app\photos\a.jpg', d), isTrue);
      expect(PhotoService.isInPhotosDir('C:/app/photos/a.jpg', d), isTrue);
      expect(PhotoService.isInPhotosDir(r'C:\app\photosX\a.jpg', d), isFalse);
      expect(PhotoService.isInPhotosDir(r'C:\app\photos\..\x', d), isFalse);
      expect(PhotoService.isInPhotosDir(r'C:\app\photos\', d), isFalse);
    });
  });
}
