import 'package:flutter_test/flutter_test.dart';

import 'package:gps_rtk_app/models/device_telemetry.dart';

void main() {
  group('DeviceTelemetry.tryParse', () {
    test('parsuje pełną ramkę z firmware (README)', () {
      final t = DeviceTelemetry.tryParse(
        '{"bat_mv":3987,"bat_pct":74,"up_s":1234,"rtcm_bps":512,'
        '"ble_mtu":247,"fix":4,"sat":18,"hdop":0.82,"age":1.4}',
      )!;
      expect(t.batteryMv, 3987);
      expect(t.batteryPct, 74);
      expect(t.uptimeS, 1234);
      expect(t.rtcmBps, 512);
      expect(t.bleMtu, 247);
      expect(t.fix, 4);
      expect(t.satellites, 18);
      expect(t.hdop, closeTo(0.82, 1e-9));
      expect(t.correctionAgeS, closeTo(1.4, 1e-9));
      expect(t.hasBattery, isTrue);
      expect(t.rtcmFlowing, isTrue);
    });

    test('age=-1 → null (brak poprawek); bat=0 → hasBattery=false', () {
      final t = DeviceTelemetry.tryParse(
        '{"bat_mv":0,"bat_pct":0,"rtcm_bps":0,"fix":1,"age":-1}',
      )!;
      expect(t.correctionAgeS, isNull);
      expect(t.hasBattery, isFalse);
      expect(t.rtcmFlowing, isFalse);
    });

    test('brakujące pola → null, obecne zachowane', () {
      final t = DeviceTelemetry.tryParse('{"fix":5}')!;
      expect(t.fix, 5);
      expect(t.batteryPct, isNull);
      expect(t.bleMtu, isNull);
      expect(t.correctionAgeS, isNull);
    });

    test('odporne na obramowanie/śmieci wokół obiektu JSON', () {
      final t = DeviceTelemetry.tryParse('\x00 {"fix":4} \r\n')!;
      expect(t.fix, 4);
    });

    test('niepoprawna treść → null', () {
      expect(DeviceTelemetry.tryParse('nonsense'), isNull);
      expect(DeviceTelemetry.tryParse('[1,2,3]'), isNull);
      expect(DeviceTelemetry.tryParse(''), isNull);
      expect(DeviceTelemetry.tryParse('{niepoprawny'), isNull);
    });
  });
}
