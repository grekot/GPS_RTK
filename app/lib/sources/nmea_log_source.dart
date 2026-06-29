import 'dart:async';
import 'dart:math';

import 'package:latlong2/latlong.dart';

import '../models/rtk_position.dart';
import '../rtk/nmea_parser.dart';
import 'position_source.dart';

/// Źródło pozycji do testów bez sprzętu: odtwarza wczytany **log NMEA**
/// (zapętlony, w tempie [interval]) albo — gdy logu brak — **symuluje** strumień
/// (zimny start → RTK Float → RTK Fixed) wokół [demoCenter], generując zdania
/// GGA tym samym parserem, którego używa odbiornik BLE.
class NmeaLogSource implements PositionSource {
  NmeaLogSource();

  @override
  String get name => 'Log NMEA / symulator';

  /// Wczytane linie logu NMEA. Null/puste → tryb symulacji.
  List<String>? lines;

  /// Środek symulacji (ustawiany na pierwszą wczytaną działkę).
  LatLng demoCenter = const LatLng(49.8964, 20.6156);

  /// Odstęp między kolejnymi pozycjami.
  Duration interval = const Duration(milliseconds: 500);

  final _rng = Random();

  @override
  Stream<RtkPosition> positions() {
    final parser = NmeaParser();
    var running = true;
    late final StreamController<RtkPosition> ctrl;

    Future<void> playLog(List<String> log) async {
      while (running) {
        for (final line in log) {
          if (!running || ctrl.isClosed) return;
          final pos = parser.addLine(line);
          if (pos != null) {
            ctrl.add(pos);
            await Future<void>.delayed(interval);
          }
        }
      }
    }

    Future<void> simulate() async {
      var i = 0;
      while (running) {
        if (ctrl.isClosed) return;
        // Progresja: 3 epoki GPS, kilka Float, potem Fixed (z rzadkim Float).
        final fix = i < 3
            ? 1
            : i < 7
                ? 5
                : (i % 13 == 0 ? 5 : 4);
        // Dryf zależny od jakości (Fixed ~cm, Float ~dm, GPS ~m).
        final jitter =
            fix == 4 ? 0.00000012 : (fix == 5 ? 0.000002 : 0.00002);
        // Dryf pionowy ~1,5× poziomego [m] — realistyczny rozrzut wysokości.
        final vJitter = fix == 4 ? 0.02 : (fix == 5 ? 0.3 : 3.0);
        final lat = demoCenter.latitude + (_rng.nextDouble() - 0.5) * 2 * jitter;
        final lon =
            demoCenter.longitude + (_rng.nextDouble() - 0.5) * 2 * jitter;
        final gga = buildGgaSentence(
          lat,
          lon,
          fixQuality: fix,
          satellites: 12 + i % 6,
          hdop: fix == 4 ? 0.7 : (fix == 5 ? 1.1 : 1.8),
          altitude: 250 + (_rng.nextDouble() - 0.5) * 2 * vJitter,
        );
        final pos = parser.addLine(gga);
        if (pos != null) ctrl.add(pos);
        i++;
        await Future<void>.delayed(interval);
      }
    }

    ctrl = StreamController<RtkPosition>(
      onListen: () {
        final log = lines;
        if (log != null && log.isNotEmpty) {
          playLog(log);
        } else {
          simulate();
        }
      },
      onCancel: () => running = false,
    );
    return ctrl.stream;
  }
}
