import 'package:flutter_test/flutter_test.dart';

import 'package:gps_rtk_app/sources/serial_receiver_source.dart';

// Uwaga: testujemy tylko czyste pola/kontrakt. Nie wołamy availablePorts()
// ani positions() — to uruchomiłoby natywne libserialport (FFI), które nie
// jest dostępne w środowisku `flutter test`.
void main() {
  test('nazwa źródła widoczna dla użytkownika', () {
    expect(SerialReceiverSource().name, 'Odbiornik RTK (COM)');
  });

  test('kontrakt NTRIP/port jak w BLE/USB — pola ustawialne', () {
    final src = SerialReceiverSource();
    expect(src.ntripConfig, isNull); // domyślnie bez poprawek
    expect(src.portName, isNull); // domyślnie pierwszy dostępny
    src.portName = 'COM7';
    expect(src.portName, 'COM7');
  });
}
