import 'package:flutter_test/flutter_test.dart';
import 'package:usb_serial/usb_serial.dart';

import 'package:gps_rtk_app/sources/usb_receiver_source.dart';

UsbDevice _dev(int vid, int pid, int id) =>
    UsbDevice('/dev/bus/usb/$id', vid, pid, 'p', 'm', id, null, 1);

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

  group('pickReceiverDevice', () {
    test('pusta lista → null', () {
      expect(pickReceiverDevice([]), isNull);
    });

    test('woli znany mostek USB-UART niż inne urządzenie (np. hub, pendrive)',
        () {
      final other = _dev(0x0781, 0x5567, 1); // SanDisk
      final ch340 = _dev(0x1A86, 0x7523, 2);
      expect(pickReceiverDevice([other, ch340]), same(ch340));
    });

    test('po ponownym wpięciu wybiera to samo VID:PID co ostatnio', () {
      final ftdi = _dev(0x0403, 0x6001, 3);
      final cp = _dev(0x10C4, 0xEA60, 4);
      expect(
          pickReceiverDevice([ftdi, cp],
              preferredVid: 0x10C4, preferredPid: 0xEA60),
          same(cp));
    });

    test('nieznane urządzenie jako ostatnia deska ratunku', () {
      final cdc = _dev(0x2E8A, 0x000A, 5);
      expect(pickReceiverDevice([cdc]), same(cdc));
    });
  });

  group('usbEventAction', () {
    const att = UsbEvent.ACTION_USB_ATTACHED;
    const det = UsbEvent.ACTION_USB_DETACHED;

    test('odpięcie naszego urządzenia zamyka port', () {
      expect(usbEventAction(det, 7, portOpen: true, openDeviceId: 7),
          UsbEventAction.closePort);
    });

    test('odpięcie innego urządzenia jest ignorowane', () {
      expect(usbEventAction(det, 8, portOpen: true, openDeviceId: 7),
          UsbEventAction.ignore);
    });

    test('odpięcie bez znanego id — zamknij ostrożnie', () {
      expect(usbEventAction(det, null, portOpen: true, openDeviceId: 7),
          UsbEventAction.closePort);
      expect(usbEventAction(det, 7, portOpen: true),
          UsbEventAction.closePort);
    });

    test('odpięcie przy zamkniętym porcie — nic do zrobienia', () {
      expect(usbEventAction(det, 7, portOpen: false), UsbEventAction.ignore);
    });

    test('wpięcie przy zamkniętym porcie → ponowne otwarcie', () {
      expect(usbEventAction(att, 9, portOpen: false), UsbEventAction.reopen);
    });

    test('wpięcie, gdy port już działa — ignoruj (drugie urządzenie)', () {
      expect(usbEventAction(att, 9, portOpen: true, openDeviceId: 7),
          UsbEventAction.ignore);
    });

    test('nieznane zdarzenie — ignoruj', () {
      expect(usbEventAction('x', 1, portOpen: false), UsbEventAction.ignore);
    });
  });
}
