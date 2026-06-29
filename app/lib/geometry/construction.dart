import 'dart:math';

import 'vec2.dart';

/// Operacje konstrukcyjne w lokalnej płaszczyźnie metrycznej (Vec2).
/// Czyste funkcje — wynik zamieniany na WGS84 przez [LocalFrame] w warstwie UI.

/// Odsunięcie odcinka a→b o [distance] m. Dodatnie = w lewo od kierunku a→b,
/// ujemne = w prawo. Zwraca przesunięty odcinek (równoległy).
(Vec2, Vec2) offsetSegment(Vec2 a, Vec2 b, double distance) {
  final n = (b - a).normalized.perpLeft * distance;
  return (a + n, b + n);
}

/// Odsunięcie całego ZAMKNIĘTEGO pierścienia [ring] o [distance] m (dodatnie =
/// w lewo od kierunku obiegu krawędzi). Nowe wierzchołki = przecięcia sąsiednich
/// odsuniętych krawędzi (złącza zaostrzone) — dla wielokątów wypukłych/
/// prostokątnych (typowe działki/budynki) daje równoległy obrys.
List<Vec2> offsetRing(List<Vec2> ring, double distance) {
  final n = ring.length;
  if (n < 3) return List.of(ring);
  final off = [
    for (var i = 0; i < n; i++) offsetSegment(ring[i], ring[(i + 1) % n], distance),
  ];
  return [
    for (var i = 0; i < n; i++)
      lineIntersection(
            off[(i - 1 + n) % n].$1,
            off[(i - 1 + n) % n].$2,
            off[i].$1,
            off[i].$2,
          ) ??
          off[i].$1,
  ];
}

/// Linia równoległa do a→b z pełną kontrolą położenia i długości:
/// początek = a przesunięte o [along] m wzdłuż kierunku a→b (od a) i [offset] m
/// prostopadle (dodatni = w lewo, ujemny = w prawo); długość [length] m w
/// kierunku a→b (ujemna = w przeciwną stronę). Gdy [along]=0 i [length] = |a→b|,
/// wynik jest identyczny jak [offsetSegment].
(Vec2, Vec2) parallelLine(
  Vec2 a,
  Vec2 b, {
  required double offset,
  required double length,
  double along = 0,
}) {
  final dir = (b - a).normalized;
  final start = a + dir * along + dir.perpLeft * offset;
  return (start, start + dir * length);
}

/// Prosta prostopadła do a→b, przechodząca przez [through], o długości [length]
/// (po połowie w każdą stronę od punktu).
(Vec2, Vec2) perpendicularThrough(Vec2 a, Vec2 b, Vec2 through, double length) {
  final perp = (b - a).normalized.perpLeft;
  return (through - perp * (length / 2), through + perp * (length / 2));
}

/// Prostokąt zbudowany od krawędzi a→b (np. podjazd przy ścianie budynku):
/// bok bazowy odsunięty o [offset] m (dodatni = w lewo od a→b), [length] m
/// wzdłuż krawędzi (licząc od a) i [width] m prostopadle. Zwraca 4 narożniki.
List<Vec2> rectangleFromEdge(
  Vec2 a,
  Vec2 b, {
  required double offset,
  required double length,
  required double width,
}) {
  final dir = (b - a).normalized;
  final perp = dir.perpLeft;
  final base = a + perp * offset;
  final c0 = base;
  final c1 = base + dir * length;
  final c2 = c1 + perp * width;
  final c3 = c0 + perp * width;
  return [c0, c1, c2, c3];
}

/// Metryka czworokąta (do kontroli prostokątności wytyczonej budowli):
/// długości 4 boków, obie przekątne (`diag1`=|c0c2|, `diag2`=|c1c3|), ich
/// różnica (`diagDiff` — dla prostokąta = 0), kąty wewnętrzne [°] i największe
/// odchylenie kąta od 90° (`squarenessError`). Wymaga 4 narożników w kolejności
/// obejścia. Klasyczna terenowa kontrola „równych przekątnych".
({
  List<double> sides,
  double diag1,
  double diag2,
  double diagDiff,
  List<double> angles,
  double squarenessError,
}) rectangleMetrics(List<Vec2> c) {
  final n = c.length;
  final sides = [for (var i = 0; i < n; i++) (c[(i + 1) % n] - c[i]).length];
  final angles = <double>[];
  for (var i = 0; i < n; i++) {
    final prev = c[(i - 1 + n) % n], next = c[(i + 1) % n];
    final v1 = prev - c[i], v2 = next - c[i];
    final l1 = v1.length, l2 = v2.length;
    final cosA = (l1 == 0 || l2 == 0) ? 1.0 : (v1.dot(v2) / (l1 * l2)).clamp(-1.0, 1.0);
    angles.add(acos(cosA) * 180 / pi);
  }
  final diag1 = n >= 3 ? (c[2] - c[0]).length : 0.0;
  final diag2 = n >= 4 ? (c[3] - c[1]).length : 0.0;
  final squarenessError =
      angles.map((a) => (a - 90).abs()).fold<double>(0, max);
  return (
    sides: sides,
    diag1: diag1,
    diag2: diag2,
    diagDiff: (diag1 - diag2).abs(),
    angles: angles,
    squarenessError: squarenessError,
  );
}

/// Punkty co [interval] m wzdłuż odcinka a→b (z oboma końcami).
List<Vec2> pointsAlong(Vec2 a, Vec2 b, double interval) {
  final total = (b - a).length;
  if (interval <= 0 || total == 0) return [a, b];
  final dir = (b - a).normalized;
  final out = <Vec2>[];
  for (var d = 0.0; d < total - 1e-6; d += interval) {
    out.add(a + dir * d);
  }
  out.add(b);
  return out;
}

/// Przecięcie dwóch prostych (przez a1a2 i b1b2). Null, gdy równoległe.
Vec2? lineIntersection(Vec2 a1, Vec2 a2, Vec2 b1, Vec2 b2) {
  final d1 = a2 - a1;
  final d2 = b2 - b1;
  final denom = d1.x * d2.y - d1.y * d2.x;
  if (denom.abs() < 1e-9) return null;
  final t = ((b1.x - a1.x) * d2.y - (b1.y - a1.y) * d2.x) / denom;
  return a1 + d1 * t;
}

/// Przedłużenie odcinka a→b o [byMeters] poza punkt b.
Vec2 extend(Vec2 a, Vec2 b, double byMeters) =>
    b + (b - a).normalized * byMeters;

/// Przyciąganie: zwraca najbliższy z [candidates] punktów leżący w promieniu
/// [maxDist] od [p], a gdy żaden nie jest dość blisko — sam [p] (bez zmiany).
/// Używane do „zaczepiania" przeciąganego punktu w punkcie innego elementu.
Vec2 snapToNearest(Vec2 p, List<Vec2> candidates, double maxDist) {
  var best = p;
  var bestD = maxDist;
  for (final c in candidates) {
    final d = (c - p).length;
    if (d <= bestD) {
      bestD = d;
      best = c;
    }
  }
  return best;
}

/// Umiejscowienie punktu [v] względem krawędzi a→b: przesunięcie o [along] m
/// wzdłuż kierunku a→b i [offset] m prostopadle (dodatni = w lewo). To wspólny
/// sposób pozycjonowania elementów konstrukcyjnych względem krawędzi-rodzica.
Vec2 placeOnEdge(Vec2 v, Vec2 a, Vec2 b,
    {required double offset, required double along}) {
  final dir = (b - a).normalized;
  return v + dir * along + dir.perpLeft * offset;
}

/// Najbliższy punkt na PROSTEJ a→b względem [p] (rzut prostopadły, bez
/// ograniczania do odcinka). Używane do przyciągania punktu do linii roboczej.
Vec2 closestPointOnLine(Vec2 p, Vec2 a, Vec2 b) {
  final ab = b - a;
  final len2 = ab.dot(ab);
  if (len2 == 0) return a;
  final t = (p - a).dot(ab) / len2;
  return a + ab * t;
}

/// Najbliższy punkt na ODCINKU a→b względem [p] (rzut z ograniczeniem do
/// końców) — przyciąganie przeciąganego punktu do realnej krawędzi, nie do jej
/// przedłużenia.
Vec2 closestPointOnSegment(Vec2 p, Vec2 a, Vec2 b) {
  final ab = b - a;
  final len2 = ab.dot(ab);
  if (len2 == 0) return a;
  final t = ((p - a).dot(ab) / len2).clamp(0.0, 1.0);
  return a + ab * t;
}

/// Rozkład wektora [delta] na składowe w ramce krawędzi a→b:
/// (wzdłuż ∥ kierunku a→b, prostopadle ⊥). Odwrotność [placeOnEdge] —
/// zamienia przesunięcie z przeciągania na zmianę parametrów along/offset.
(double along, double offset) decomposeOnEdge(Vec2 delta, Vec2 a, Vec2 b) {
  final dir = (b - a).normalized;
  return (delta.dot(dir), delta.dot(dir.perpLeft));
}

/// Odległość punktu [p] od odcinka a→b (z rzutowaniem na odcinek).
double pointToSegmentDistance(Vec2 p, Vec2 a, Vec2 b) {
  final ab = b - a;
  final len2 = ab.dot(ab);
  if (len2 == 0) return (p - a).length;
  final t = ((p - a).dot(ab) / len2).clamp(0.0, 1.0);
  return (p - (a + ab * t)).length;
}

/// Indeks krawędzi pierścienia [ring] (i → (i+1)%n) najbliższej punktowi [p].
int nearestEdgeIndex(List<Vec2> ring, Vec2 p) {
  var best = 0;
  var bestD = double.infinity;
  for (var i = 0; i < ring.length; i++) {
    final d = pointToSegmentDistance(p, ring[i], ring[(i + 1) % ring.length]);
    if (d < bestD) {
      bestD = d;
      best = i;
    }
  }
  return best;
}

/// Indeks odcinka z dowolnej listy [segments] najbliższego punktowi [p].
/// Pozwala wybierać krawędź spośród obrysu I wcześniej dodanych elementów.
int nearestSegmentIndex(List<(Vec2, Vec2)> segments, Vec2 p) {
  var best = 0;
  var bestD = double.infinity;
  for (var i = 0; i < segments.length; i++) {
    final d = pointToSegmentDistance(p, segments[i].$1, segments[i].$2);
    if (d < bestD) {
      bestD = d;
      best = i;
    }
  }
  return best;
}
