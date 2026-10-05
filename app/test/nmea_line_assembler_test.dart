import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gps_rtk_app/rtk/nmea_line_assembler.dart';
import 'package:gps_rtk_app/rtk/nmea_parser.dart';

void main() {
  test('linia rozcięta między porcjami jest składana', () {
    final a = NmeaLineAssembler();
    expect(a.add(ascii.encode(r'$GNGGA,1234')), isEmpty);
    expect(a.add(ascii.encode('56*00\r\n')), [r'$GNGGA,123456*00']);
    expect(a.pendingLength, 0);
  });

  test('kilka linii w jednej porcji, ogon czeka na resztę', () {
    final a = NmeaLineAssembler();
    final lines = a.add(ascii.encode('\$A*00\r\n\$B*00\r\n\$C'));
    expect(lines, [r'$A*00', r'$B*00']);
    expect(a.pendingLength, 2);
  });

  test('puste linie są pomijane', () {
    final a = NmeaLineAssembler();
    expect(a.add(ascii.encode('\r\n\r\n\$X*00\r\n')), [r'$X*00']);
  });

  test('śmieci bez końca linii (zły baud) nie rosną bez limitu', () {
    final a = NmeaLineAssembler(maxPending: 100);
    a.add(List.filled(150, 0x55));
    expect(a.pendingLength, 0);
    // Po porzuceniu śmieci kolejne poprawne linie dalej przechodzą.
    expect(a.add(ascii.encode('\n\$OK*00\n')), [r'$OK*00']);
  });

  test('clear() porzuca niedokończony ogon', () {
    final a = NmeaLineAssembler();
    a.add(ascii.encode(r'$GNGGA,12'));
    a.clear();
    expect(a.add(ascii.encode('34*00\n')), ['34*00']);
  });

  group('receiverSetupCommands', () {
    test('włącza GGA i RMC, wyłącza GLL/GSA/GSV/VTG, włącza PQTMEPE', () {
      final all = receiverSetupCommands.join();
      expect(all, contains(r'$PAIR062,0,1*'));
      expect(all, contains(r'$PAIR062,4,1*'));
      for (final t in [1, 2, 3, 5]) {
        expect(all, contains('\$PAIR062,$t,0*'));
      }
      expect(all, contains('PQTMEPE'));
    });

    test('nie zapisuje konfiguracji do flash modułu', () {
      expect(receiverSetupCommands.join(), isNot(contains('SAVEPAR')));
      expect(receiverSetupCommands.join(), isNot(contains('PAIR513')));
    });

    test('każda komenda ma poprawną sumę kontrolną i CRLF', () {
      for (final c in receiverSetupCommands) {
        expect(c.endsWith('\r\n'), isTrue);
        final body = c.substring(1, c.indexOf('*'));
        expect(c.substring(c.indexOf('*') + 1, c.length - 2),
            NmeaParser.nmeaChecksum(body));
      }
    });
  });
}
