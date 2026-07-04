import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:gps_rtk_app/models/rtk_position.dart';
import 'package:gps_rtk_app/sources/position_source.dart';

RtkPosition _pos(double lat) => RtkPosition(
      latitude: lat,
      longitude: 20,
      accuracy: 0.02,
      fixType: FixType.rtkFixed,
      timestamp: DateTime.utc(2026, 7, 4),
    );

/// Atrapa źródła sprzętowego: liczy connect/disconnect zamiast otwierać port.
class _FakeShared extends SharedPositionSource {
  int connects = 0;
  int disconnects = 0;
  int? lastEpoch;
  StreamController<RtkPosition>? ctrl;

  @override
  String get name => 'fake';

  @override
  Future<void> connect(StreamController<RtkPosition> c, int epoch) async {
    connects++;
    lastEpoch = epoch;
    ctrl = c;
  }

  @override
  Future<void> disconnect() async {
    disconnects++;
  }
}

void main() {
  // Scenariusz z terenu: ekran główny słucha, wejście w ekran tyczenia dokłada
  // drugiego słuchacza. Wcześniej otwierało to DRUGIE połączenie USB/NTRIP
  // (przeplecione RTCM → utrata fixa), a wyjście z tyczenia zamykało port pod
  // ekranem głównym (zamrożona pozycja przy pokazywanym fixie).
  test('drugi słuchacz nie otwiera drugiego połączenia, obaj dostają pozycje',
      () async {
    final src = _FakeShared();
    final got1 = <RtkPosition>[];
    final got2 = <RtkPosition>[];
    final sub1 = src.positions().listen(got1.add); // ekran główny
    final sub2 = src.positions().listen(got2.add); // ekran tyczenia
    await Future<void>.delayed(Duration.zero);

    expect(src.connects, 1);
    src.ctrl!.add(_pos(50));
    await Future<void>.delayed(Duration.zero);
    expect(got1, hasLength(1));
    expect(got2, hasLength(1));

    await sub1.cancel();
    await sub2.cancel();
  });

  test('wyjście z ekranu tyczenia nie rozłącza źródła ekranu głównego',
      () async {
    final src = _FakeShared();
    final got1 = <RtkPosition>[];
    final sub1 = src.positions().listen(got1.add); // ekran główny
    final sub2 = src.positions().listen((_) {}); // ekran tyczenia
    await Future<void>.delayed(Duration.zero);

    await sub2.cancel(); // powrót z tyczenia
    expect(src.disconnects, 0);
    src.ctrl!.add(_pos(51)); // ekran główny nadal dostaje pozycje
    await Future<void>.delayed(Duration.zero);
    expect(got1, hasLength(1));

    await sub1.cancel();
  });

  test('ostatni słuchacz rozłącza; ponowny Start łączy od nowa', () async {
    final src = _FakeShared();
    final sub = src.positions().listen((_) {});
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(src.disconnects, 1);

    final sub2 = src.positions().listen((_) {});
    await Future<void>.delayed(Duration.zero);
    expect(src.connects, 2); // Stop→Start działa bez tworzenia nowego obiektu

    await sub2.cancel();
  });

  // Szybkie Start→Stop: connect() w trakcie (np. skanowanie BLE) musi po
  // rozłączeniu zobaczyć nieaktualną epokę i nie dokończyć łączenia.
  test('rozłączenie unieważnia epokę trwającego connect()', () async {
    final src = _FakeShared();
    final sub = src.positions().listen((_) {});
    await Future<void>.delayed(Duration.zero);
    final epoch = src.lastEpoch!;
    expect(src.epochActive(epoch), isTrue);
    await sub.cancel();
    expect(src.epochActive(epoch), isFalse);
  });
}
