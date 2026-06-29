import 'package:latlong2/latlong.dart';

import '../utils/geo.dart';
import 'vec2.dart';

/// Lokalna płaszczyzna metryczna ENU zaczepiona w [origin]. Pozwala liczyć
/// geometrię konstrukcji w metrach (płasko) i wracać do współrzędnych WGS84.
/// Dla obszarów rzędu setek metrów zniekształcenie jest pomijalne.
class LocalFrame {
  LocalFrame(this.origin);

  final LatLng origin;

  /// Punkt geograficzny → wektor lokalny (x = wschód, y = północ) w metrach.
  Vec2 toLocal(LatLng p) {
    final o = offsetNorthEast(origin, p);
    return Vec2(o.east, o.north);
  }

  /// Wektor lokalny (metry) → punkt geograficzny.
  LatLng toLatLng(Vec2 v) => destinationLatLng(origin, v.y, v.x);

  List<Vec2> toLocalAll(List<LatLng> pts) => [for (final p in pts) toLocal(p)];
  List<LatLng> toLatLngAll(List<Vec2> vs) => [for (final v in vs) toLatLng(v)];
}
