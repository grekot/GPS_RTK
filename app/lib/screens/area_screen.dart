import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../map/base_layers.dart';
import '../models/rtk_position.dart';
import '../services/export_service.dart';
import '../sources/position_source.dart';
import '../utils/dxf.dart';
import '../utils/geo.dart';

/// Pomiar pola i obwodu: wierzchołki dodajesz tapem na mapie lub przyciskiem
/// „Dodaj pozycję" (bieżąca pozycja RTK). Pole liczone w lokalnej płaszczyźnie
/// metrycznej; eksport jako GeoJSON z polem/obwodem w atrybutach.
class AreaScreen extends StatefulWidget {
  const AreaScreen({super.key, required this.source, this.initial = const []});

  final PositionSource source;
  final List<LatLng> initial;

  @override
  State<AreaScreen> createState() => _AreaScreenState();
}

class _AreaScreenState extends State<AreaScreen> {
  final _map = MapController();
  late final List<LatLng> _pts = List.of(widget.initial);
  StreamSubscription<RtkPosition>? _sub;
  RtkPosition? _pos;

  @override
  void initState() {
    super.initState();
    _sub = widget.source.positions().listen(
          (p) => mounted ? setState(() => _pos = p) : null,
          onError: (_) {},
        );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  void _addPosition() {
    final p = _pos;
    if (p == null) {
      _snack('Brak pozycji — uruchom źródło pozycji.');
      return;
    }
    setState(() => _pts.add(LatLng(p.latitude, p.longitude)));
  }

  Future<void> _export() async {
    if (_pts.length < 3) {
      _snack('Potrzebne co najmniej 3 wierzchołki.');
      return;
    }
    final ap = polygonAreaPerimeter(_pts);
    final ring = [
      for (final p in _pts) [p.longitude, p.latitude],
      [_pts.first.longitude, _pts.first.latitude],
    ];
    final gj = const JsonEncoder.withIndent('  ').convert({
      'type': 'FeatureCollection',
      'crs': {
        'type': 'name',
        'properties': {'name': 'urn:ogc:def:crs:OGC:1.3:CRS84'},
      },
      'features': [
        {
          'type': 'Feature',
          'properties': {
            'pole_m2': ap.area,
            'pole_ha': ap.area / 10000,
            'obwod_m': ap.perimeter,
            'wierzcholki': _pts.length,
          },
          'geometry': {
            'type': 'Polygon',
            'coordinates': [ring],
          },
        },
      ],
    });
    final dxf = DxfBuilder()
      ..addLatLngPolyline(_pts, layer: 'POLE', color: 3, closed: true);
    try {
      await ExportService.shareTextFiles({
        'pole.geojson': gj,
        'pole.dxf': dxf.build(),
      }, subject: 'Pomiar pola');
    } catch (e) {
      _snack('Eksport nieudany: $e');
    }
  }

  String _fmtArea(double m2) {
    final ha = m2 / 10000;
    final m = m2 >= 100000
        ? '${(m2 / 10000).toStringAsFixed(2)} ha'
        : '${m2.toStringAsFixed(1)} m²';
    return ha >= 0.01 && m2 < 100000 ? '$m  (${ha.toStringAsFixed(4)} ha)' : m;
  }

  @override
  Widget build(BuildContext context) {
    final p = _pos;
    final current = p == null ? null : LatLng(p.latitude, p.longitude);
    final ap = polygonAreaPerimeter(_pts);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pomiar pola i obwodu'),
        actions: [
          IconButton(
            tooltip: 'Cofnij wierzchołek',
            onPressed: _pts.isEmpty ? null : () => setState(_pts.removeLast),
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            tooltip: 'Wyczyść',
            onPressed: _pts.isEmpty ? null : () => setState(_pts.clear),
            icon: const Icon(Icons.delete_outline),
          ),
          IconButton(
            tooltip: 'Eksport (GeoJSON)',
            onPressed: _pts.length < 3 ? null : _export,
            icon: const Icon(Icons.ios_share),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCameraFit: _pts.isEmpty
                  ? null
                  : CameraFit.coordinates(
                      coordinates: _pts, padding: const EdgeInsets.all(60)),
              initialCenter: _pts.isNotEmpty
                  ? _pts.first
                  : (current ?? const LatLng(49.8964, 20.6156)),
              initialZoom: 18,
              maxZoom: 22,
              onTap: (tp, point) => setState(() => _pts.add(point)),
            ),
            children: [
              ValueListenableBuilder<MapBaseLayer>(
                valueListenable: activeBaseLayer,
                builder: (context, layer, _) => buildBaseTileLayer(layer),
              ),
              const OrtoHighResOverlay(),
              const UtilitiesOverlay(),
              const BuildingsOverlay(),
              if (_pts.length >= 3)
                PolygonLayer(polygons: [
                  Polygon(
                    points: _pts,
                    color: Colors.teal.withValues(alpha: 0.20),
                    borderColor: Colors.teal,
                    borderStrokeWidth: 2,
                  ),
                ])
              else if (_pts.length == 2)
                PolylineLayer(polylines: [
                  Polyline(points: _pts, color: Colors.teal, strokeWidth: 2),
                ]),
              MarkerLayer(
                markers: [
                  for (var i = 0; i < _pts.length; i++)
                    Marker(
                      point: _pts[i],
                      width: 26,
                      height: 26,
                      child: _vertex('${i + 1}'),
                    ),
                  if (current != null)
                    Marker(
                      point: current,
                      width: 18,
                      height: 18,
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                          border: Border.fromBorderSide(
                              BorderSide(color: Colors.white, width: 3)),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          const Positioned(top: 8, right: 8, child: BaseLayerControl()),
          // FAB „Dodaj pozycję" NAD kartą wyniku (nie zasłania pola/obwodu).
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 16, bottom: 10),
                  child: FloatingActionButton.extended(
                    heroTag: 'areaAdd',
                    onPressed: _addPosition,
                    icon: const Icon(Icons.add_location_alt),
                    label: const Text('Dodaj pozycję'),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                      12, 0, 12, 12 + MediaQuery.viewPaddingOf(context).bottom),
                  child: Card(
                    elevation: 4,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _pts.length < 3
                                ? 'Dotknij mapy lub „Dodaj pozycję", aby '
                                    'wyznaczyć wierzchołki (min. 3).'
                                : 'Pole: ${_fmtArea(ap.area)}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (_pts.length >= 2)
                            Text(
                              'Obwód: ${formatDistance(ap.perimeter)}'
                              '   ·   wierzchołków: ${_pts.length}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _vertex(String label) => DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.teal, width: 2),
        ),
        child: Center(
          child: Text(label,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.teal)),
        ),
      );
}
