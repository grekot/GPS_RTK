import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:gps_rtk_app/models/rtk_position.dart';
import 'package:gps_rtk_app/rtk/nmea_parser.dart';
import 'package:gps_rtk_app/rtk/ntrip_client.dart';

void main() {
  group('NTRIP protokół', () {
    const cfg = NtripConfig(
      host: 'system.asgeupos.pl',
      port: 2101,
      mountpoint: 'RTN4G_VRS_RTCM32',
      username: 'user',
      password: 'pass',
    );

    test('żądanie zawiera mountpoint i autoryzację Basic', () {
      final req = buildNtripRequest(cfg);
      expect(req, startsWith('GET /RTN4G_VRS_RTCM32 HTTP/1.0'));
      final auth = base64Encode(utf8.encode('user:pass'));
      expect(req, contains('Authorization: Basic $auth'));
      expect(req, endsWith('\r\n\r\n'));
    });

    test('rozpoznanie odpowiedzi OK (ICY/HTTP) i odrzucenia', () {
      expect(ntripResponseOk('ICY 200 OK'), isTrue);
      expect(ntripResponseOk('HTTP/1.1 200 OK'), isTrue);
      expect(ntripResponseOk('HTTP/1.1 401 Unauthorized'), isFalse);
      expect(ntripResponseOk('SOURCETABLE 200 OK'), isTrue); // 200 — ale to nie mount
    });

    test('koniec nagłówka: ICY (1 linia) i HTTP (pusta linia)', () {
      final icy = 'ICY 200 OK\r\nXXX'.codeUnits;
      expect(ntripHeaderEnd(icy), 'ICY 200 OK\r\n'.length);
      final http = 'HTTP/1.1 200 OK\r\nServer: x\r\n\r\nDATA'.codeUnits;
      expect(ntripHeaderEnd(http), 'HTTP/1.1 200 OK\r\nServer: x\r\n\r\n'.length);
    });

    test('roundtrip JSON konfiguracji', () {
      final back = NtripConfig.fromJson(cfg.toJson());
      expect(back.host, cfg.host);
      expect(back.mountpoint, cfg.mountpoint);
      expect(back.port, 2101);
    });
  });

  group('NTRIP sourcetable', () {
    const sample = 'SOURCETABLE 200 OK\r\n'
        'Server: NTRIP Caster\r\n'
        '\r\n'
        'CAS;system.asgeupos.pl;2101;ASG-EUPOS;GUGiK;0;POL;52;21;0.0.0.0;0\r\n'
        'NET;ASG-EUPOS;GUGiK;B;N;none;none;none;none\r\n'
        'STR;RTN4G_VRS_RTCM32;RTN4G;RTCM 3.2;1004(1),1012(1);2;GPS+GLO;'
        'ASG-EUPOS;POL;52.00;21.00;1;0;sNTRIP;none;B;N;9600;\r\n'
        'STR;NAWGEO_VRS_3_1;NAWGEO;RTCM 3.1;1004(1);2;GPS+GLO+GAL;'
        'ASG-EUPOS;POL;52.0;21.0;1;0;x;none;B;N;9600;\r\n'
        'ENDSOURCETABLE\r\n';

    test('parseSourcetable wyłuskuje tylko linie STR', () {
      final list = parseSourcetable(sample);
      expect(list.length, 2);
      expect(list.first.mountpoint, 'RTN4G_VRS_RTCM32');
      expect(list.first.identifier, 'RTN4G');
      expect(list.first.format, 'RTCM 3.2');
      expect(list.first.navSystem, 'GPS+GLO');
      expect(list.first.country, 'POL');
      expect(list.first.lat, closeTo(52.0, 1e-9)); // pole 9
      expect(list.first.lon, closeTo(21.0, 1e-9)); // pole 10
      expect(list[1].mountpoint, 'NAWGEO_VRS_3_1');
    });

    test('parsowanie kończy się na ENDSOURCETABLE', () {
      final withTrailing =
          '$sample' 'STR;PO_KONCU;x;RTCM 3.2;;2;GPS;net;POL\r\n';
      final list = parseSourcetable(withTrailing);
      expect(list.any((e) => e.mountpoint == 'PO_KONCU'), isFalse);
    });

    test('SourcetableEntry.parse odrzuca nie-STR i puste nazwy', () {
      expect(SourcetableEntry.parse('NET;ASG;...'), isNull);
      expect(SourcetableEntry.parse('STR;;ident'), isNull);
      final e = SourcetableEntry.parse('STR;MP1;Loc;RTCM 3.2;;;GPS;;DEU')!;
      expect(e.mountpoint, 'MP1');
      expect(e.navSystem, 'GPS');
      expect(e.country, 'DEU');
      expect(e.lat, isNull); // brak pól 9/10 → null, bez wywrotki
      expect(e.lon, isNull);
    });

    test('buildSourcetableRequest: GET /, auth tylko z loginem', () {
      final anon = buildSourcetableRequest('', '');
      expect(anon, startsWith('GET / HTTP/1.0'));
      expect(anon, isNot(contains('Authorization')));
      expect(anon, endsWith('\r\n\r\n'));
      expect(buildSourcetableRequest('u', 'p'),
          contains('Authorization: Basic '));
    });
  });

  test('buildGgaSentence → NmeaParser odtwarza pozycję (round-trip)', () {
    final gga = buildGgaSentence(48.1173, 11.5167,
        timeUtc: DateTime.utc(2026, 6, 14, 10, 0, 0), fixQuality: 4);
    final p = NmeaParser().addLine(gga);
    expect(p, isNotNull);
    expect(p!.latitude, closeTo(48.1173, 1e-5));
    expect(p.longitude, closeTo(11.5167, 1e-5));
    expect(p.fixType, FixType.rtkFixed);
  });
}
