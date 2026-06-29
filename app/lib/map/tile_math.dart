import 'dart:math';

/// Współrzędne kafelka w schemacie „slippy map" (Web Mercator, EPSG:3857).
typedef TileXYZ = ({int x, int y, int z});

/// Indeks kolumny kafelka (X) dla długości geograficznej na danym zoomie.
int lonToTileX(double lon, int z) {
  final n = 1 << z;
  return ((lon + 180.0) / 360.0 * n).floor().clamp(0, n - 1);
}

/// Indeks wiersza kafelka (Y) dla szerokości geograficznej na danym zoomie.
/// Uwaga: Y rośnie na południe (północ = mniejszy Y).
int latToTileY(double lat, int z) {
  final n = 1 << z;
  final r = lat * pi / 180.0;
  final y = (1 - log(tan(r) + 1 / cos(r)) / pi) / 2 * n;
  return y.floor().clamp(0, n - 1);
}

/// Lista kafelków pokrywających prostokąt (s/w/n/e w stopniach) dla zakresu
/// zoomów [minZoom..maxZoom] włącznie.
List<TileXYZ> tilesForBounds(
  double south,
  double west,
  double north,
  double east,
  int minZoom,
  int maxZoom,
) {
  final out = <TileXYZ>[];
  for (var z = minZoom; z <= maxZoom; z++) {
    final xa = lonToTileX(west, z);
    final xb = lonToTileX(east, z);
    final ya = latToTileY(north, z); // północ = mniejszy Y
    final yb = latToTileY(south, z);
    for (var x = min(xa, xb); x <= max(xa, xb); x++) {
      for (var y = min(ya, yb); y <= max(ya, yb); y++) {
        out.add((x: x, y: y, z: z));
      }
    }
  }
  return out;
}

/// Konwersja długość/szerokość (WGS84, stopnie) → metry EPSG:3857 (Web Mercator).
({double x, double y}) lonLatToMercator(double lon, double lat) {
  const r = 6378137.0;
  final x = r * lon * pi / 180.0;
  final y = r * log(tan(pi / 4 + (lat * pi / 180.0) / 2));
  return (x: x, y: y);
}

/// Liczba kafelków dla prostokąta i zakresu zoomów (do oszacowania pobrania).
int tileCountForBounds(
  double south,
  double west,
  double north,
  double east,
  int minZoom,
  int maxZoom,
) =>
    tilesForBounds(south, west, north, east, minZoom, maxZoom).length;
