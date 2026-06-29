import 'dart:math';

import 'package:latlong2/latlong.dart';

import '../models/rtk_position.dart';
import '../utils/geo.dart';

/// Wynik uśrednienia pomiaru punktu.
class AveragedFix {
  const AveragedFix({
    required this.mean,
    required this.rms,
    required this.meanAccuracy,
    required this.samples,
    required this.worstFix,
    required this.bestFix,
    this.meanAltitude,
    this.verticalRms = 0,
  });

  /// Uśredniona pozycja.
  final LatLng mean;

  /// Rozrzut poziomy próbek względem średniej (RMS) [m] — miara powtarzalności.
  final double rms;

  /// Średnia z raportowanej dokładności urządzenia [m].
  final double meanAccuracy;

  /// Uśredniona wysokość [m] (z GGA) — null, gdy żadna próbka jej nie miała.
  final double? meanAltitude;

  /// Rozrzut pionowy próbek względem średniej wysokości (RMS) [m].
  final double verticalRms;

  final int samples;

  /// Najgorszy i najlepszy typ fixa zaobserwowany w trakcie uśredniania.
  final FixType worstFix;
  final FixType bestFix;
}

/// Uśrednia kolejne próbki pozycji w jeden punkt. Bramka jakości: odrzuca
/// próbki bez fixa (FixType.none). Pozostałe akceptuje, ale zapamiętuje
/// najgorszy fix — UI ostrzega, jeśli pomiar nie był w pełni RTK Fixed.
class PointAverager {
  PointAverager({this.targetSamples = 20, this.requireFixed = false});

  final int targetSamples;

  /// Gdy true — przyjmuje tylko próbki RTK Fixed (odrzuca Float/DGPS/GPS).
  final bool requireFixed;

  final List<LatLng> _pts = [];
  final List<double> _alts = []; // tylko próbki, które miały wysokość
  double _accSum = 0;
  int _worstRank = 4;
  int _bestRank = 0;

  int get count => _pts.length;
  bool get isComplete => count >= targetSamples;

  /// Dodaje próbkę. Zwraca true, gdy przyjęta (false = odrzucona przez bramkę).
  bool add(RtkPosition p) {
    if (p.fixType == FixType.none) return false;
    if (requireFixed && p.fixType != FixType.rtkFixed) return false;
    _pts.add(LatLng(p.latitude, p.longitude));
    if (p.altitude != null) _alts.add(p.altitude!);
    _accSum += p.accuracy;
    final r = fixRank(p.fixType);
    if (r < _worstRank) _worstRank = r;
    if (r > _bestRank) _bestRank = r;
    return true;
  }

  double? _meanAltitude() {
    if (_alts.isEmpty) return null;
    var sum = 0.0;
    for (final a in _alts) {
      sum += a;
    }
    return sum / _alts.length;
  }

  /// Rozrzut pionowy (RMS) względem średniej wysokości [m]. 0 dla <2 próbek.
  double _verticalRms() {
    if (_alts.length < 2) return 0;
    final m = _meanAltitude()!;
    var sumSq = 0.0;
    for (final a in _alts) {
      final d = a - m;
      sumSq += d * d;
    }
    return sqrt(sumSq / _alts.length);
  }

  LatLng _mean() {
    var lat = 0.0, lon = 0.0;
    for (final p in _pts) {
      lat += p.latitude;
      lon += p.longitude;
    }
    return LatLng(lat / _pts.length, lon / _pts.length);
  }

  /// Bieżący rozrzut poziomy (RMS) względem średniej [m].
  double currentRms() {
    if (_pts.length < 2) return 0;
    final m = _mean();
    var sumSq = 0.0;
    for (final p in _pts) {
      final o = offsetNorthEast(m, p);
      sumSq += o.north * o.north + o.east * o.east;
    }
    return sqrt(sumSq / _pts.length);
  }

  /// Zamyka uśrednianie. Zwraca null, gdy nie przyjęto żadnej próbki.
  AveragedFix? finalize() {
    if (_pts.isEmpty) return null;
    return AveragedFix(
      mean: _mean(),
      rms: currentRms(),
      meanAccuracy: _accSum / _pts.length,
      samples: _pts.length,
      worstFix: _fixOfRank(_worstRank),
      bestFix: _fixOfRank(_bestRank),
      meanAltitude: _meanAltitude(),
      verticalRms: _verticalRms(),
    );
  }

  static FixType _fixOfRank(int r) => switch (r) {
        0 => FixType.none,
        1 => FixType.gps,
        2 => FixType.dgps,
        3 => FixType.rtkFloat,
        _ => FixType.rtkFixed,
      };
}
