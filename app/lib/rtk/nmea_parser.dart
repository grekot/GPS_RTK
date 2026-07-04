import 'dart:math';

import '../models/rtk_position.dart';

/// Buduje zdanie `$GPGGA` z pozycji — używane do wysyłania pozycji do castera
/// NTRIP (sieci VRS tego wymagają). Czas w UTC.
String buildGgaSentence(
  double lat,
  double lon, {
  DateTime? timeUtc,
  int fixQuality = 1,
  int satellites = 10,
  double hdop = 1.0,
  double altitude = 100.0,
}) {
  final t = (timeUtc ?? DateTime.now().toUtc());
  String two(int v) => v.toString().padLeft(2, '0');
  final time = '${two(t.hour)}${two(t.minute)}${two(t.second)}.00';

  String dm(double value, int degWidth) {
    final a = value.abs();
    final d = a.floor();
    final m = (a - d) * 60.0;
    return '${d.toString().padLeft(degWidth, '0')}'
        '${m.toStringAsFixed(5).padLeft(8, '0')}';
  }

  final body = 'GPGGA,$time,'
      '${dm(lat, 2)},${lat >= 0 ? 'N' : 'S'},'
      '${dm(lon, 3)},${lon >= 0 ? 'E' : 'W'},'
      '$fixQuality,${two(satellites)},${hdop.toStringAsFixed(1)},'
      '${altitude.toStringAsFixed(1)},M,0.0,M,,';
  return '\$$body*${NmeaParser.nmeaChecksum(body)}';
}

/// Parser strumienia NMEA z odbiornika GNSS. Akumuluje stan między zdaniami:
/// GGA daje pozycję i typ fixa, GST dokładność, RMC kurs. Pozycję emituje przy
/// zdaniu GGA. Wymaga poprawnej sumy kontrolnej `*HH`.
class NmeaParser {
  double? _accuracy; // z GST [m]
  double? _course; // z RMC [°]

  /// Dodaje jedną linię NMEA. Zwraca [RtkPosition] dla ważnej GGA, inaczej null.
  RtkPosition? addLine(String line) {
    line = line.trim();
    if (line.length < 6 || !line.startsWith(r'$')) return null;
    if (!_checksumOk(line)) return null;

    final star = line.indexOf('*');
    final body = line.substring(1, star == -1 ? line.length : star);
    final f = body.split(',');
    if (f[0].length < 3) return null;
    final type = f[0].substring(f[0].length - 3);

    switch (type) {
      case 'GST':
        _gst(f);
        return null;
      case 'RMC':
        _rmc(f);
        return null;
      case 'GGA':
        return _gga(f);
    }
    return null;
  }

  void _gst(List<String> f) {
    // GST: ...,stdMajor,stdMinor,orient,stdLat(6),stdLon(7),stdAlt(8)
    if (f.length < 8) return;
    final sLat = double.tryParse(f[6]);
    final sLon = double.tryParse(f[7]);
    if (sLat != null && sLon != null) {
      _accuracy = sqrt(sLat * sLat + sLon * sLon);
    }
  }

  void _rmc(List<String> f) {
    // RMC: ...,speed(7),course(8),...
    if (f.length < 9) return;
    final c = double.tryParse(f[8]);
    if (c != null) _course = c;
  }

  RtkPosition? _gga(List<String> f) {
    // GGA: time(1),lat(2),N/S(3),lon(4),E/W(5),fix(6),sats(7),hdop(8),alt(9),...
    if (f.length < 10) return null;
    final lat = _coord(f[2], f[3]);
    final lon = _coord(f[4], f[5]);
    if (lat == null || lon == null) return null;
    // Odrzuć przekłamane zdanie (sklejone/uszkodzone bajty, np. po USB 460800):
    // poza zakresem lat ±90 / lon ±180. Inaczej mapa dostaje śmieci (lat 1054°)
    // i flutter_map wywala się asercją LatLngBounds (north <= 90).
    if (lat.abs() > 90 || lon.abs() > 180 || !lat.isFinite || !lon.isFinite) {
      return null;
    }
    final fixQ = int.tryParse(f[6]) ?? 0;
    final sats = int.tryParse(f[7]);
    final hdop = double.tryParse(f[8]);
    final alt = double.tryParse(f[9]);
    final fix = fixTypeFromGga(fixQ);

    return RtkPosition(
      latitude: lat,
      longitude: lon,
      altitude: alt,
      accuracy: _accuracy ?? estimateAccuracy(fix, hdop),
      fixType: fix,
      satellites: sats,
      heading: _course,
      timestamp: DateTime.now(),
    );
  }

  /// ddmm.mmmm / dddmm.mmmm + półkula → stopnie dziesiętne.
  static double? _coord(String value, String hemi) {
    if (value.isEmpty) return null;
    final dot = value.indexOf('.');
    if (dot < 3) return null;
    final deg = double.tryParse(value.substring(0, dot - 2));
    final min = double.tryParse(value.substring(dot - 2));
    if (deg == null || min == null) return null;
    var dd = deg + min / 60.0;
    if (hemi == 'S' || hemi == 'W') dd = -dd;
    return dd;
  }

  /// Mapowanie pola „fix quality" z GGA na [FixType].
  static FixType fixTypeFromGga(int q) => switch (q) {
        0 => FixType.none,
        2 => FixType.dgps,
        4 => FixType.rtkFixed,
        5 => FixType.rtkFloat,
        _ => FixType.gps, // 1 i pozostałe (np. 6 estymacja) traktuj jak GPS
      };

  /// Zgrubna dokładność pozioma, gdy brak GST (np. LC29HEA nie wysyła GST).
  static double estimateAccuracy(FixType fix, double? hdop) {
    final base = switch (fix) {
      FixType.rtkFixed => 0.02,
      FixType.rtkFloat => 0.5,
      FixType.dgps => 1.0,
      FixType.gps => 2.5,
      FixType.none => 99.0,
    };
    return base * (hdop == null || hdop <= 0 ? 1.0 : hdop.clamp(0.5, 5.0));
  }

  /// XOR sumy kontrolnej NMEA dla treści (bez `$`/`*`).
  static String nmeaChecksum(String body) {
    var x = 0;
    for (final c in body.codeUnits) {
      x ^= c;
    }
    return x.toRadixString(16).toUpperCase().padLeft(2, '0');
  }

  /// Weryfikuje sumę kontrolną NMEA (XOR znaków między `$` a `*`).
  /// Zdanie **bez** `*HH` odrzucamy: odbiornik zawsze ją wysyła, a brak
  /// gwiazdki to niemal na pewno ucięta/sklejona linia (zgubione bajty na USB
  /// przy 460800 bps). Przepuszczanie takich zdań dawało „odskoki" pozycji
  /// przy wciąż pokazywanym RTK Fixed.
  static bool _checksumOk(String line) {
    final star = line.indexOf('*');
    if (star == -1 || star + 3 > line.length) return false;
    var x = 0;
    for (var i = 1; i < star; i++) {
      x ^= line.codeUnitAt(i);
    }
    final given = int.tryParse(line.substring(star + 1, star + 3), radix: 16);
    return given != null && given == x;
  }
}
