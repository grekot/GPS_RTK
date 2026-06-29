import 'package:latlong2/latlong.dart';

import 'pl2000.dart';

/// Punkt graniczny wczytany z wykazu współrzędnych (PL-2000).
class BoundaryPoint {
  const BoundaryPoint({
    required this.label,
    required this.position,
    this.bpp,
  });

  final String label; // numer/oznaczenie punktu
  final LatLng position;
  final double? bpp; // błąd położenia punktu [m] (atrybut dokładności), jeśli był
}

/// Czy współrzędne mieszczą się w granicach Polski (sanity check transformacji).
bool _inPoland(double lat, double lon) =>
    lat >= 48.5 && lat <= 55.5 && lon >= 13.5 && lon <= 24.5;

/// Próbuje rozwiązać parę dużych liczb jako (northing X, easting Y) w dowolnej
/// kolejności — wybiera ten wariant, który po transformacji wpada w Polskę.
/// Dzięki temu działa i dla `nr;X;Y`, i dla `nr;Y;X`.
LatLng? _resolve(double a, double b) {
  for (final pair in [(a, b), (b, a)]) {
    final x = pair.$1; // northing
    final y = pair.$2; // easting (z prefiksem strefy)
    final zone = Pl2000.zoneFromEasting(y);
    final r = Pl2000.toLatLon(zone, y, x);
    if (_inPoland(r.lat, r.lon)) return LatLng(r.lat, r.lon);
  }
  return null;
}

/// Parsuje listę punktów granicznych w PL-2000 z tekstu CSV/TXT.
/// Akceptuje separatory `;`, tab lub spacje, przecinek lub kropkę dziesiętną,
/// kolejność kolumn `nr X Y` lub `nr Y X` (autodetekcja), opcjonalny BPP
/// (mała liczba). Linie bez dwóch dużych liczb (nagłówki, komentarze) pomija.
List<BoundaryPoint> parseBoundaryPoints(String text) {
  final out = <BoundaryPoint>[];
  for (final raw in text.split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#') || line.startsWith('//')) continue;

    final tokens = line
        .split(line.contains(';')
            ? ';'
            : (line.contains('\t') ? '\t' : RegExp(r'\s+')))
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    if (tokens.length < 3) continue;

    double? toNum(String s) => double.tryParse(s.replaceAll(',', '.'));
    final nums = [for (final t in tokens) toNum(t)];

    // Dwie współrzędne = duże liczby (≥ 100 000 m).
    final coordIdx = [
      for (var i = 0; i < tokens.length; i++)
        if ((nums[i]?.abs() ?? 0) >= 100000) i,
    ];
    if (coordIdx.length < 2) continue; // nagłówek / śmieć

    final pos = _resolve(nums[coordIdx[0]]!, nums[coordIdx[1]]!);
    if (pos == null) continue;

    // Etykieta: pierwszy token, o ile nie jest współrzędną; inaczej kolejny nr.
    final label = coordIdx.contains(0) ? '${out.length + 1}' : tokens.first;

    // BPP: mała dodatnia liczba (0–10 m), nie współrzędna i nie kolumna etykiety.
    double? bpp;
    for (var i = 1; i < tokens.length; i++) {
      if (coordIdx.contains(i)) continue;
      final n = nums[i];
      if (n != null && n > 0 && n < 10) {
        bpp = n;
        break;
      }
    }

    out.add(BoundaryPoint(label: label, position: pos, bpp: bpp));
  }
  return out;
}
