import 'package:flutter_test/flutter_test.dart';

import 'package:gps_rtk_app/models/device_telemetry.dart';
import 'package:gps_rtk_app/models/rtk_position.dart';
import 'package:gps_rtk_app/sources/ble_receiver_source.dart';
import 'package:gps_rtk_app/sources/phone_gnss_source.dart';

void main() {
  test('źródła pozycji mają nazwy dla użytkownika', () {
    expect(PhoneGnssSource().name, 'GPS telefonu');
    expect(BleReceiverSource().name, 'Odbiornik RTK (BLE)');
  });

  test('źródło BLE udostępnia strumień pozycji i telemetrię', () {
    final src = BleReceiverSource();
    expect(src.positions(), isA<Stream<RtkPosition>>());
    expect(src.statusMessages, isA<Stream<String>>());
    expect(src.telemetry, isA<Stream<DeviceTelemetry>>());
  });

  test('RtkPosition przechowuje komplet danych', () {
    final p = RtkPosition(
      latitude: 49.8964,
      longitude: 20.6156,
      accuracy: 2.5,
      fixType: FixType.gps,
      timestamp: DateTime.utc(2026, 6, 12),
    );
    expect(p.fixType, FixType.gps);
    expect(p.altitude, isNull);
  });
}
