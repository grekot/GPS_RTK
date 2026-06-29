import 'dart:math';

import 'package:latlong2/latlong.dart';

// Elipsoida WGS84.
const double _a = 6378137.0; // półoś wielka [m]
const double _e2 = 0.00669437999014; // kwadrat pierwszego mimośrodu

double _rad(double deg) => deg * pi / 180;
double _deg(double rad) => rad * 180 / pi;

/// Promień krzywizny południka (kierunek N-S) na szerokości [latRad].
double _meridianRadius(double latRad) =>
    _a * (1 - _e2) / pow(1 - _e2 * pow(sin(latRad), 2), 1.5);

/// Promień krzywizny przekroju poprzecznego (kierunek E-W) na [latRad].
double _primeVerticalRadius(double latRad) =>
    _a / sqrt(1 - _e2 * pow(sin(latRad), 2));

/// Przesunięcie z [from] do [to] w metrach: na północ i na wschód
/// (wartości ujemne = na południe / na zachód). Lokalna płaszczyzna styczna
/// na elipsoidzie WGS84 — dokładność milimetrowa do kilku km.
({double north, double east}) offsetNorthEast(LatLng from, LatLng to) {
  final midLat = _rad((from.latitude + to.latitude) / 2);
  final north = _rad(to.latitude - from.latitude) * _meridianRadius(midLat);
  final east = _rad(to.longitude - from.longitude) *
      _primeVerticalRadius(midLat) *
      cos(midLat);
  return (north: north, east: east);
}

/// Punkt oddalony od [origin] o [north]/[east] metrów — odwrotność
/// [offsetNorthEast]. Dla obszarów rzędu setek metrów dokładność milimetrowa.
LatLng destinationLatLng(LatLng origin, double north, double east) {
  final lat0 = _rad(origin.latitude);
  final newLat = origin.latitude + _deg(north / _meridianRadius(lat0));
  final midLat = _rad((origin.latitude + newLat) / 2);
  final newLon =
      origin.longitude + _deg(east / (_primeVerticalRadius(midLat) * cos(midLat)));
  return LatLng(newLat, newLon);
}

/// Odległość pozioma w metrach. Liczona w lokalnej płaszczyźnie stycznej
/// (elipsoida WGS84) — przeznaczona do zastosowań terenowych (do ~50 km).
double distanceMeters(LatLng a, LatLng b) {
  final o = offsetNorthEast(a, b);
  return sqrt(o.north * o.north + o.east * o.east);
}

/// Azymut geograficzny z punktu [from] do [to] w stopniach (0–360, 0 = północ).
double bearingDegrees(LatLng from, LatLng to) {
  final o = offsetNorthEast(from, to);
  return (_deg(atan2(o.east, o.north)) + 360) % 360;
}

/// Kierunek świata dla azymutu, np. 36° -> "NE".
String cardinal(double bearingDeg) {
  const dirs = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
  return dirs[((bearingDeg + 22.5) % 360 ~/ 45)];
}

/// Kąt do celu względem kierunku, w który zwrócony jest użytkownik,
/// znormalizowany do zakresu (-180, 180]. Dodatni = cel po prawej,
/// ujemny = po lewej, 0 = na wprost.
double relativeBearing(double bearingToTarget, double heading) {
  var rel = (bearingToTarget - heading) % 360;
  if (rel > 180) rel -= 360;
  if (rel <= -180) rel += 360;
  return rel;
}

/// Słowna instrukcja skrętu na podstawie kąta względnego (-180..180).
String turnInstruction(double relativeDeg) {
  final a = relativeDeg.abs();
  if (a < 15) return 'prosto';
  final side = relativeDeg > 0 ? 'w prawo' : 'w lewo';
  if (a < 60) return 'lekko $side';
  if (a < 150) return side;
  return 'zawróć';
}

/// Czy punkt leży wewnątrz wielokąta (algorytm ray casting). Współrzędne
/// w stopniach; dla działek (małe obszary) zniekształcenie geograficzne
/// jest pomijalne. Pierścień może być domknięty (pierwszy == ostatni) lub nie.
bool isPointInPolygon(LatLng point, List<LatLng> polygon) {
  if (polygon.length < 3) return false;
  final x = point.longitude;
  final y = point.latitude;
  var inside = false;
  for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    final xi = polygon[i].longitude, yi = polygon[i].latitude;
    final xj = polygon[j].longitude, yj = polygon[j].latitude;
    final intersects = ((yi > y) != (yj > y)) &&
        (x < (xj - xi) * (y - yi) / (yj - yi) + xi);
    if (intersects) inside = !inside;
  }
  return inside;
}

/// Pole [m²] i obwód [m] wielokąta (domkniętego automatycznie). Liczone w
/// lokalnej płaszczyźnie metrycznej względem pierwszego wierzchołka (shoelace).
({double area, double perimeter}) polygonAreaPerimeter(List<LatLng> pts) {
  if (pts.length < 2) return (area: 0, perimeter: 0);
  final origin = pts.first;
  final local = [for (final p in pts) offsetNorthEast(origin, p)];
  var perimeter = 0.0;
  var twiceArea = 0.0;
  for (var i = 0; i < local.length; i++) {
    final a = local[i];
    final b = local[(i + 1) % local.length];
    perimeter += sqrt(pow(b.east - a.east, 2) + pow(b.north - a.north, 2));
    twiceArea += a.east * b.north - b.east * a.north;
  }
  return (area: twiceArea.abs() / 2, perimeter: perimeter);
}

/// Czy współrzędne są w prawidłowym zakresie (lat ±90, lon ±180, skończone).
/// Strażnik przed asercją flutter_map (`LatLngBounds`: north ≤ 90), gdy do mapy
/// trafi przekłamana pozycja (np. uszkodzone zdanie NMEA → lat 1054°).
bool isValidLatLng(double lat, double lon) =>
    lat.isFinite &&
    lon.isFinite &&
    lat.abs() <= 90 &&
    lon.abs() <= 180;

/// Spadek między dwoma punktami z wysokościami. `horizontal` = odległość
/// pozioma [m], `deltaH` = różnica wysokości [m] (b−a; dodatni = b wyżej),
/// `percent` = nachylenie [%], `permille` = [‰], `angleDeg` = kąt od poziomu
/// [°]. Dla pokrywających się punktów (horizontal≈0) procent/promil = 0.
({
  double horizontal,
  double deltaH,
  double percent,
  double permille,
  double angleDeg,
}) slopeBetween(LatLng a, double altA, LatLng b, double altB) {
  final horizontal = distanceMeters(a, b);
  final deltaH = altB - altA;
  final flat = horizontal < 1e-9;
  return (
    horizontal: horizontal,
    deltaH: deltaH,
    percent: flat ? 0 : deltaH / horizontal * 100,
    permille: flat ? 0 : deltaH / horizontal * 1000,
    angleDeg: _deg(atan2(deltaH, horizontal)),
  );
}

/// Format spadku w % ze znakiem (np. „+2,5 %"). Dwie cyfry znaczące przy
/// małych wartościach typowych dla podjazdów/odwodnień.
String formatSlope(double percent) {
  final sign = percent > 0 ? '+' : (percent < 0 ? '−' : '');
  final v = percent.abs();
  final s = v < 10
      ? v.toStringAsFixed(2)
      : (v < 100 ? v.toStringAsFixed(1) : v.toStringAsFixed(0));
  return '$sign${s.replaceAll('.', ',')} %';
}

/// Spadek jako stosunek „1:n" (n = pozioma/|Δh|). Pusty dla zerowego spadku.
String slopeRatio(double horizontal, double deltaH) {
  if (deltaH.abs() < 1e-6 || horizontal < 1e-9) return '';
  final n = horizontal / deltaH.abs();
  return '1:${n.toStringAsFixed(n < 10 ? 1 : 0).replaceAll('.', ',')}';
}

/// Format odległości czytelny w terenie: centymetry poniżej metra,
/// rosnąca precyzja im bliżej celu.
String formatDistance(double meters) {
  final m = meters.abs();
  if (m < 1) return '${(m * 100).round()} cm';
  if (m < 10) return '${m.toStringAsFixed(2).replaceAll('.', ',')} m';
  if (m < 1000) return '${m.toStringAsFixed(1).replaceAll('.', ',')} m';
  return '${(m / 1000).toStringAsFixed(2).replaceAll('.', ',')} km';
}
