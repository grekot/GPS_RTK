import 'package:flutter_test/flutter_test.dart';

import 'package:gps_rtk_app/models/rtk_position.dart';
import 'package:gps_rtk_app/sources/nmea_log_source.dart';

void main() {
  test('symulator: emituje pozycje z progresją GPS → RTK', () async {
    final src = NmeaLogSource()..interval = const Duration(milliseconds: 1);
    final positions = await src.positions().take(8).toList();
    expect(positions, hasLength(8));
    expect(positions.first.fixType, FixType.gps); // 1. epoka
    expect(positions.last.fixType,
        anyOf(FixType.rtkFixed, FixType.rtkFloat)); // po progresji
  });

  test('odtwarzanie wczytanego logu NMEA', () async {
    final src = NmeaLogSource()
      ..interval = const Duration(milliseconds: 1)
      ..lines = [
        r'$GPGGA,120000.00,4953.7840,N,02036.9360,E,4,18,0.8,250.0,M,0.0,M,,',
      ];
    final positions = await src.positions().take(2).toList();
    expect(positions, hasLength(2)); // zapętlone
    expect(positions.first.fixType, FixType.rtkFixed);
    expect(positions.first.latitude, closeTo(49.8964, 1e-3));
  });
}
