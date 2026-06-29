import 'package:latlong2/latlong.dart';

import '../models/measured_point.dart';
import 'pl2000.dart';

/// Minimalny pisarz DXF (format klasyczny POLYLINE/VERTEX, zgodny od R12 —
/// czytają go AutoCAD, LibreCAD, QGIS itd.). Współrzędne w PL-2000:
/// DXF x = easting (Y-2000), y = northing (X-2000) → północ w górę, wschód
/// w prawo, więc rysunek jest zorientowany jak mapa geodezyjna.
///
/// Indeksy kolorów ACI: 1=czerwony, 3=zielony, 4=cyan, 5=niebieski, 6=magenta.
class DxfBuilder {
  final StringBuffer _entities = StringBuffer();
  final Map<String, int> _layers = {}; // nazwa → kolor ACI

  // Standardowe warstwy używane przez konwertery.
  static const layerParcels = 'DZIALKI';
  static const layerBuildings = 'BUDYNKI';
  static const layerConstructions = 'KONSTRUKCJE';
  static const layerPoints = 'PUNKTY';

  void _pair(int code, String value) => _entities.write('$code\r\n$value\r\n');

  void _useLayer(String name, int color) =>
      _layers.putIfAbsent(name, () => color);

  String _num(double v) => v.toStringAsFixed(3);

  /// Polilinia z punktów [x,y] (metry PL-2000). [closed]=true domyka obrys.
  void addPolyline(
    List<List<double>> pts, {
    required String layer,
    int color = 7,
    bool closed = false,
  }) {
    if (pts.length < 2) return;
    _useLayer(layer, color);
    _pair(0, 'POLYLINE');
    _pair(8, layer);
    _pair(66, '1'); // wierzchołki następują
    _pair(70, closed ? '1' : '0');
    for (final p in pts) {
      _pair(0, 'VERTEX');
      _pair(8, layer);
      _pair(10, _num(p[0]));
      _pair(20, _num(p[1]));
      _pair(30, '0.0');
    }
    _pair(0, 'SEQEND');
    _pair(8, layer);
  }

  /// Punkt (metry PL-2000) z opcjonalną etykietą TEXT obok.
  void addPoint(
    double x,
    double y, {
    required String layer,
    int color = 7,
    String? label,
    double textHeight = 0.4,
  }) {
    _useLayer(layer, color);
    _pair(0, 'POINT');
    _pair(8, layer);
    _pair(10, _num(x));
    _pair(20, _num(y));
    _pair(30, '0.0');
    if (label != null && label.isNotEmpty) {
      _pair(0, 'TEXT');
      _pair(8, layer);
      _pair(10, _num(x + textHeight * 0.8));
      _pair(20, _num(y + textHeight * 0.8));
      _pair(30, '0.0');
      _pair(40, _num(textHeight));
      _pair(1, label.replaceAll('\n', ' '));
    }
  }

  // — warianty WGS84 (konwersja do PL-2000 w środku) —

  void addLatLngPolyline(
    List<LatLng> pts, {
    required String layer,
    int color = 7,
    bool closed = false,
  }) {
    addPolyline(
      [
        for (final p in pts)
          [
            Pl2000.fromLatLon(p.latitude, p.longitude).easting,
            Pl2000.fromLatLon(p.latitude, p.longitude).northing,
          ],
      ],
      layer: layer,
      color: color,
      closed: closed,
    );
  }

  void addLatLngPoint(
    LatLng p, {
    required String layer,
    int color = 7,
    String? label,
  }) {
    final pl = Pl2000.fromLatLon(p.latitude, p.longitude);
    addPoint(pl.easting, pl.northing, layer: layer, color: color, label: label);
  }

  /// Składa kompletny dokument DXF (HEADER pusty + TABLES/LAYER + ENTITIES).
  String build() {
    final b = StringBuffer();
    void pair(int code, String value) => b.write('$code\r\n$value\r\n');

    pair(0, 'SECTION');
    pair(2, 'HEADER');
    pair(0, 'ENDSEC');

    pair(0, 'SECTION');
    pair(2, 'TABLES');
    pair(0, 'TABLE');
    pair(2, 'LAYER');
    pair(70, '${_layers.length}');
    _layers.forEach((name, color) {
      pair(0, 'LAYER');
      pair(2, name);
      pair(70, '0');
      pair(62, '$color');
      pair(6, 'CONTINUOUS');
    });
    pair(0, 'ENDTAB');
    pair(0, 'ENDSEC');

    pair(0, 'SECTION');
    pair(2, 'ENTITIES');
    b.write(_entities.toString());
    pair(0, 'ENDSEC');

    pair(0, 'EOF');
    return b.toString();
  }
}

/// Eksport zmierzonych punktów do DXF (warstwa PUNKTY, PL-2000, etykiety).
String measuredPointsToDxf(List<MeasuredPoint> points) {
  final dxf = DxfBuilder();
  for (final p in points) {
    dxf.addLatLngPoint(
      p.latLng,
      layer: DxfBuilder.layerPoints,
      color: 1,
      label: p.label ?? p.id,
    );
  }
  return dxf.build();
}
