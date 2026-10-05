import 'package:flutter_test/flutter_test.dart';

import 'package:gps_rtk_app/services/app_settings.dart';
import 'package:gps_rtk_app/services/keep_awake.dart';

void main() {
  final calls = <bool>[];
  setUp(() {
    calls.clear();
    KeepAwake.apply = (enable) async => calls.add(enable);
    AppSettings.instance = AppSettings(keepAwake: true);
  });

  test('wyjście z tyczenia nie gasi ekranu trwającej sesji', () {
    final home = Object(), stakeout = Object();
    KeepAwake.instance.hold(home);
    KeepAwake.instance.hold(stakeout);
    KeepAwake.instance.release(stakeout);
    expect(KeepAwake.instance.active, isTrue);
    KeepAwake.instance.release(home);
    expect(KeepAwake.instance.active, isFalse);
    expect(calls, [true, false]); // bez zbędnych przełączeń po drodze
  });

  test('tyczenie bez „Start" też trzyma ekran', () {
    final stakeout = Object();
    KeepAwake.instance.hold(stakeout);
    expect(calls.last, isTrue);
    KeepAwake.instance.release(stakeout);
    expect(calls.last, isFalse);
  });

  test('wyłączone ustawienie „Nie wygaszaj ekranu" jest respektowane', () {
    final owner = Object();
    KeepAwake.instance.hold(owner);
    AppSettings.instance = AppSettings(keepAwake: false);
    KeepAwake.instance.refresh();
    expect(calls.last, isFalse);
    KeepAwake.instance.release(owner);
  });
}
