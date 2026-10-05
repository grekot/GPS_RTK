import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:gps_rtk_app/rtk/ntrip_client.dart';

/// Lokalny „caster": każde połączenie obsługuje [onClient].
class _FakeCaster {
  _FakeCaster(this.onClient);

  final void Function(Socket s, int index) onClient;
  late final ServerSocket server;
  final clients = <Socket>[];

  Future<void> start() async {
    server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((s) {
      clients.add(s);
      s.listen((_) {}, onError: (_) {}, onDone: () {});
      onClient(s, clients.length);
    });
  }

  int get port => server.port;

  Future<void> close() async {
    for (final c in clients) {
      c.destroy();
    }
    await server.close();
  }
}

NtripClient _client(
  int port, {
  List<String>? status,
  List<int>? rtcm,
  Duration headerTimeout = const Duration(seconds: 5),
}) =>
    NtripClient(
      NtripConfig(host: '127.0.0.1', port: port, mountpoint: 'TEST'),
      onStatus: status?.add,
      onRtcm: rtcm?.addAll,
      headerTimeout: headerTimeout,
      retryBase: const Duration(milliseconds: 100),
      retryMax: const Duration(milliseconds: 400),
    );

Future<void> _wait(int ms) => Future.delayed(Duration(milliseconds: ms));

void main() {
  group('ntripRetryDelay', () {
    const base = Duration(seconds: 5);
    const max = Duration(seconds: 60);

    test('pierwsza próba po bazowym opóźnieniu, potem ×2 do limitu', () {
      expect(ntripRetryDelay(1, base, max), base);
      expect(ntripRetryDelay(2, base, max), const Duration(seconds: 10));
      expect(ntripRetryDelay(3, base, max), const Duration(seconds: 20));
      expect(ntripRetryDelay(4, base, max), const Duration(seconds: 40));
      expect(ntripRetryDelay(5, base, max), max);
      expect(ntripRetryDelay(1000, base, max), max);
    });
  });

  group('NtripClient z lokalnym casterem', () {
    test('odbiera RTCM po nagłówku ICY 200', () async {
      final caster = _FakeCaster((s, _) {
        s.add(ascii.encode('ICY 200 OK\r\n'));
        s.add([0xD3, 0x00, 0x01, 0xAA]);
      });
      await caster.start();
      final rtcm = <int>[];
      final c = _client(caster.port, rtcm: rtcm);
      await c.start();
      await _wait(200);
      expect(rtcm, [0xD3, 0x00, 0x01, 0xAA]);
      await c.stop();
      await caster.close();
    });

    test('401 (złe hasło) zatrzymuje klienta — bez ponawiania w kółko',
        () async {
      final caster = _FakeCaster((s, _) {
        s.add(ascii.encode('HTTP/1.0 401 Unauthorized\r\n\r\n'));
      });
      await caster.start();
      final status = <String>[];
      final c = _client(caster.port, status: status);
      await c.start();
      await _wait(700); // kilka okresów ponowienia
      expect(caster.clients, hasLength(1));
      expect(c.running, isFalse);
      expect(c.fatalError, contains('login'));
      await c.stop();
      await caster.close();
    });

    test('sourcetable (zły mountpoint) zatrzymuje klienta', () async {
      final caster = _FakeCaster((s, _) {
        s.add(ascii.encode('SOURCETABLE 200 OK\r\n\r\nENDSOURCETABLE\r\n'));
      });
      await caster.start();
      final c = _client(caster.port);
      await c.start();
      await _wait(500);
      expect(caster.clients, hasLength(1));
      expect(c.fatalError, contains('mountpoint'));
      await caster.close();
    });

    test('zerwane połączenie jest ponawiane', () async {
      final caster = _FakeCaster((s, i) {
        if (i == 1) {
          s.destroy(); // pierwsze zrywamy od razu
        } else {
          s.add(ascii.encode('ICY 200 OK\r\n'));
        }
      });
      await caster.start();
      final c = _client(caster.port);
      await c.start();
      await _wait(400);
      expect(caster.clients, hasLength(2));
      await c.stop();
      await caster.close();
    });

    test('szybkie STOP→START nie odpala zaległego ponowienia (jeden socket)',
        () async {
      final caster = _FakeCaster((s, i) {
        if (i == 1) {
          s.destroy(); // zerwanie → klient planuje ponowienie za 100 ms
        } else {
          s.add(ascii.encode('ICY 200 OK\r\n'));
        }
      });
      await caster.start();
      final c = _client(caster.port);
      await c.start();
      await _wait(30); // zerwanie dotarło, ponowienie zaplanowane
      await c.stop();
      await c.start(); // połączenie nr 2
      await _wait(500); // zaległe ponowienie (100 ms) nie może dać nr 3
      expect(caster.clients, hasLength(2));
      await c.stop();
      await caster.close();
    });

    test('caster milczy po TCP → timeout nagłówka i ponowienie', () async {
      final caster = _FakeCaster((s, _) {/* nic nie odsyła */});
      await caster.start();
      final status = <String>[];
      final c = _client(caster.port,
          status: status, headerTimeout: const Duration(milliseconds: 150));
      await c.start();
      await _wait(450);
      expect(caster.clients.length, greaterThanOrEqualTo(2));
      expect(status.any((m) => m.contains('nie odpowiada')), isTrue);
      await c.stop();
      await caster.close();
    });

    test('GGA nie jest wysyłane przed nagłówkiem odpowiedzi', () async {
      final received = <int>[];
      final ready = Completer<void>();
      late Socket client;
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((s) {
        client = s;
        s.listen(received.addAll);
        ready.complete();
      });
      final c = _client(server.port);
      await c.start();
      await ready.future;
      await _wait(50);
      final before = received.length; // samo żądanie GET
      c.sendGga(r'$GPGGA,early*00');
      await _wait(50);
      expect(received.length, before);
      client.add(ascii.encode('ICY 200 OK\r\n'));
      await _wait(50);
      c.sendGga(r'$GPGGA,late*00');
      await _wait(50);
      expect(ascii.decode(received.sublist(before)), contains('late'));
      await c.stop();
      client.destroy();
      await server.close();
    });
  });
}
