import 'package:flutter_test/flutter_test.dart';

import 'package:gps_rtk_app/sources/usb_receiver_source.dart';

void main() {
  test('nazwa źródła widoczna dla użytkownika', () {
    expect(UsbReceiverSource().name, 'Odbiornik RTK (USB)');
  });

  test('kontrakt NTRIP jak w BLE — można ustawić/wyczyścić konfigurację', () {
    final src = UsbReceiverSource();
    expect(src.ntripConfig, isNull); // domyślnie bez poprawek
  });

  // Testy biegną na hoście (nie-Android), więc brama platformy zgłasza błąd
  // zamiast wołać natywny usb_serial — to potwierdza, że iOS/desktop nie ruszą
  // kodu USB i pozostają przy BLE.
  test('poza Androidem positions() zgłasza StateError (brama platformy)',
      () async {
    final src = UsbReceiverSource();
    await expectLater(src.positions(), emitsError(isA<StateError>()));
  });
}
