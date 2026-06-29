import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../geometry/construction.dart';
import '../geometry/local_frame.dart';
import '../geometry/vec2.dart';
import '../map/base_layers.dart';
import '../models/rtk_position.dart';
import '../services/export_service.dart';
import '../sources/position_source.dart';
import '../utils/dxf.dart';
import '../utils/geo.dart';
import '../utils/pl2000.dart';

/// Wytyczenie prostokątnej budowli (altana, garaż, taras, fundament) z kontrolą
/// prostokątności. Krok 1: ustaw pierwszą ścianę A→B (bieżącą pozycją RTK).
/// Krok 2: podaj szerokość i stronę → apka liczy narożniki C, D, długości boków
/// i **przekątną** (do kontroli taśmą: równe przekątne = kąt prosty). Kontrola:
/// zmierz 4 wbite narożniki → różnica przekątnych, kąty i werdykt.
class BuildingLayoutScreen extends StatefulWidget {
  const BuildingLayoutScreen({super.key, required this.source});

  final PositionSource source;

  @override
  State<BuildingLayoutScreen> createState() => _BuildingLayoutScreenState();
}

class _BuildingLayoutScreenState extends State<BuildingLayoutScreen> {
  final _map = MapController();
  final _widthCtrl = TextEditingController(text: '5');
  StreamSubscription<RtkPosition>? _sub;
  RtkPosition? _pos;

  LatLng? _aLL; // narożnik A (początek pierwszej ściany)
  LatLng? _bLL; // narożnik B (koniec pierwszej ściany)
  bool _leftSide = true; // budowla po lewej stronie kierunku A→B
  final _check = <LatLng>[]; // zmierzone, wbite narożniki (kontrola)

  // Tolerancje werdyktu prostokątności.
  static const _diagTol = 0.02; // 2 cm różnicy przekątnych
  static const _angleTol = 0.3; // 0,3° odchylenia kąta od 90°

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
    _widthCtrl.dispose();
    super.dispose();
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  LatLng? get _current {
    final p = _pos;
    return p == null ? null : LatLng(p.latitude, p.longitude);
  }

  double get _width => double.tryParse(_widthCtrl.text.replaceAll(',', '.')) ?? 0;

  /// Narożniki [A, B, C, D] w WGS84, gdy zadana pierwsza ściana i szerokość.
  List<LatLng>? get _cornersLL {
    final a = _aLL, b = _bLL;
    final w = _width;
    if (a == null || b == null || w <= 0) return null;
    final frame = LocalFrame(a);
    final aV = const Vec2(0, 0);
    final bV = frame.toLocal(b);
    if ((bV - aV).length < 0.01) return null; // A i B zbyt blisko
    final corners = rectangleFromEdge(aV, bV,
        offset: 0, length: (bV - aV).length, width: _leftSide ? w : -w);
    return corners.map(frame.toLatLng).toList();
  }

  void _setA() {
    final c = _current;
    if (c == null) return _snack('Brak pozycji — uruchom źródło pozycji.');
    setState(() => _aLL = c);
  }

  void _setB() {
    final c = _current;
    if (c == null) return _snack('Brak pozycji — uruchom źródło pozycji.');
    setState(() => _bLL = c);
  }

  void _addCheck() {
    final c = _current;
    if (c == null) return _snack('Brak pozycji — uruchom źródło pozycji.');
    if (_check.length >= 4) {
      return _snack('Zmierzono już 4 narożniki — wyczyść, by zacząć od nowa.');
    }
    setState(() => _check.add(c));
  }

  Future<void> _export() async {
    final corners = _cornersLL;
    if (corners == null) return;
    const names = ['A', 'B', 'C', 'D'];
    final csv = StringBuffer()
      ..writeln('naroznik;zone2000;y2000_m;x2000_m;lat;lon');
    for (var i = 0; i < corners.length; i++) {
      final pl = Pl2000.fromLatLon(corners[i].latitude, corners[i].longitude);
      csv.writeln([
        names[i],
        pl.zone,
        pl.easting.toStringAsFixed(2),
        pl.northing.toStringAsFixed(2),
        corners[i].latitude.toStringAsFixed(8),
        corners[i].longitude.toStringAsFixed(8),
      ].join(';'));
    }
    final dxf = DxfBuilder()
      ..addLatLngPolyline(corners,
          layer: DxfBuilder.layerBuildings, color: 3, closed: true);
    for (var i = 0; i < corners.length; i++) {
      dxf.addLatLngPoint(corners[i],
          layer: DxfBuilder.layerPoints, color: 1, label: names[i]);
    }
    try {
      await ExportService.shareTextFiles({
        'budowla_narozniki.csv': csv.toString(),
        'budowla.dxf': dxf.build(),
      }, subject: 'Wytyczenie budowli');
    } catch (e) {
      _snack('Eksport nieudany: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final corners = _cornersLL;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wytyczenie budowli'),
        actions: [
          IconButton(
            tooltip: 'Eksport narożników (CSV PL-2000)',
            onPressed: corners == null ? null : _export,
            icon: const Icon(Icons.ios_share),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.only(
            bottom: 16 + MediaQuery.viewPaddingOf(context).bottom),
        children: [
          _mapPreview(corners),
          _wallCard(),
          _dimsCard(),
          if (corners != null) _targetCard(corners),
          _checkCard(),
        ],
      ),
    );
  }

  Widget _mapPreview(List<LatLng>? corners) {
    final cur = _current;
    final pts = corners ?? [?_aLL, ?_bLL];
    return SizedBox(
      height: 280,
      child: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCameraFit: pts.isEmpty
                  ? null
                  : CameraFit.coordinates(
                      coordinates: pts, padding: const EdgeInsets.all(48)),
              initialCenter:
                  pts.isNotEmpty ? pts.first : (cur ?? const LatLng(52, 19)),
              initialZoom: 19,
              maxZoom: 22,
            ),
            children: [
              ValueListenableBuilder<MapBaseLayer>(
                valueListenable: activeBaseLayer,
                builder: (context, layer, _) => buildBaseTileLayer(layer),
              ),
              if (corners != null) ...[
                PolygonLayer(polygons: [
                  Polygon(
                    points: corners,
                    color: Colors.indigo.withValues(alpha: 0.18),
                    borderColor: Colors.indigo,
                    borderStrokeWidth: 2.5,
                  ),
                ]),
                PolylineLayer(polylines: [
                  // Przekątne (kontrola prostokątności).
                  Polyline(
                      points: [corners[0], corners[2]],
                      color: Colors.indigo.withValues(alpha: 0.6),
                      strokeWidth: 1.5,
                      pattern: const StrokePattern.dotted()),
                  Polyline(
                      points: [corners[1], corners[3]],
                      color: Colors.indigo.withValues(alpha: 0.6),
                      strokeWidth: 1.5,
                      pattern: const StrokePattern.dotted()),
                ]),
              ] else if (pts.length == 2)
                PolylineLayer(polylines: [
                  Polyline(points: pts, color: Colors.indigo, strokeWidth: 2.5),
                ]),
              MarkerLayer(markers: [
                if (corners != null)
                  for (var i = 0; i < corners.length; i++)
                    Marker(
                      point: corners[i],
                      width: 26,
                      height: 26,
                      child: _cornerDot(['A', 'B', 'C', 'D'][i]),
                    )
                else ...[
                  if (_aLL != null)
                    Marker(point: _aLL!, width: 26, height: 26, child: _cornerDot('A')),
                  if (_bLL != null)
                    Marker(point: _bLL!, width: 26, height: 26, child: _cornerDot('B')),
                ],
                for (var i = 0; i < _check.length; i++)
                  Marker(
                    point: _check[i],
                    width: 22,
                    height: 22,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.deepOrange,
                        shape: BoxShape.circle,
                        border: Border.fromBorderSide(
                            BorderSide(color: Colors.white, width: 2)),
                      ),
                    ),
                  ),
                if (cur != null)
                  Marker(
                    point: cur,
                    width: 16,
                    height: 16,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        shape: BoxShape.circle,
                        border: Border.fromBorderSide(
                            BorderSide(color: Colors.white, width: 3)),
                      ),
                    ),
                  ),
              ]),
            ],
          ),
          const Positioned(top: 8, right: 8, child: BaseLayerControl()),
        ],
      ),
    );
  }

  Widget _wallCard() {
    final haveA = _aLL != null, haveB = _bLL != null;
    final wall = (haveA && haveB) ? distanceMeters(_aLL!, _bLL!) : null;
    return _card(
      'Krok 1 · pierwsza ściana (A → B)',
      [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _setA,
                icon: Icon(haveA ? Icons.check_circle : Icons.looks_one_outlined,
                    color: haveA ? Colors.green : null),
                label: const Text('Narożnik A = tu'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _setB,
                icon: Icon(haveB ? Icons.check_circle : Icons.looks_two_outlined,
                    color: haveB ? Colors.green : null),
                label: const Text('Narożnik B = tu'),
              ),
            ),
          ],
        ),
        if (wall != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Długość ściany A→B: ${formatDistance(wall)}',
                style: Theme.of(context).textTheme.bodyMedium),
          )
        else
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Stań w narożniku A i naciśnij „A = tu", potem przejdź do B '
              'wzdłuż pierwszej ściany i naciśnij „B = tu".',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }

  Widget _dimsCard() {
    return _card(
      'Krok 2 · szerokość i strona',
      [
        Row(
          children: [
            SizedBox(
              width: 130,
              child: TextField(
                controller: _widthCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Szerokość [m]',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('W lewo')),
                  ButtonSegment(value: false, label: Text('W prawo')),
                ],
                selected: {_leftSide},
                onSelectionChanged: (s) => setState(() => _leftSide = s.first),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            'Strona względem kierunku A→B (gdzie ma stanąć budowla).',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  Widget _targetCard(List<LatLng> corners) {
    final l = distanceMeters(corners[0], corners[1]);
    final w = distanceMeters(corners[1], corners[2]);
    final diag = sqrt(l * l + w * w);
    final area = l * w;
    final cur = _current;
    return _card(
      'Wymiary i przekątna (kontrola taśmą)',
      [
        Wrap(spacing: 18, runSpacing: 6, children: [
          _metric('Długość', formatDistance(l)),
          _metric('Szerokość', formatDistance(w)),
          _metric('Przekątna', formatDistance(diag), highlight: true),
          _metric('Pole', '${area.toStringAsFixed(1)} m²'),
          _metric('Obwód', formatDistance(2 * (l + w))),
        ]),
        const Divider(height: 18),
        Text('Narożniki do wytyczenia:',
            style: Theme.of(context).textTheme.labelLarge),
        for (var i = 2; i < 4; i++) _cornerNav(['A', 'B', 'C', 'D'][i], corners[i], cur),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            'Obie przekątne równe (${formatDistance(diag)}) = kąt prosty. '
            'Wbij C i D, zmierz taśmą przekątne, potem skontroluj poniżej.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  Widget _cornerNav(String name, LatLng corner, LatLng? cur) {
    String trailing;
    if (cur == null) {
      final pl = Pl2000.fromLatLon(corner.latitude, corner.longitude);
      trailing = 'Y ${pl.easting.toStringAsFixed(2)}  X ${pl.northing.toStringAsFixed(2)}';
    } else {
      final d = distanceMeters(cur, corner);
      final az = bearingDegrees(cur, corner);
      trailing = '${formatDistance(d)} · az ${az.toStringAsFixed(0)}° ${cardinal(az)}';
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          _cornerDot(name),
          const SizedBox(width: 10),
          Expanded(child: Text(trailing)),
        ],
      ),
    );
  }

  Widget _checkCard() {
    Widget? verdict;
    if (_check.length == 4) {
      final frame = LocalFrame(_check.first);
      final m = rectangleMetrics(_check.map(frame.toLocal).toList());
      final ok = m.diagDiff <= _diagTol && m.squarenessError <= _angleTol;
      final color = ok ? Colors.green : Colors.deepOrange;
      verdict = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 18),
          Row(children: [
            Icon(ok ? Icons.check_circle : Icons.warning_amber_rounded,
                color: color),
            const SizedBox(width: 8),
            Text(ok ? 'Prostokąt OK' : 'Odchyłka od prostokąta',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: color, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 6),
          Wrap(spacing: 18, runSpacing: 6, children: [
            _metric('Przekątna 1', formatDistance(m.diag1)),
            _metric('Przekątna 2', formatDistance(m.diag2)),
            _metric('Różnica', formatDistance(m.diagDiff), highlight: !ok),
            _metric('Maks. błąd kąta', '${m.squarenessError.toStringAsFixed(2)}°'),
          ]),
          const SizedBox(height: 6),
          Text(
            'Boki: ${m.sides.map((s) => s.toStringAsFixed(2)).join(' · ')} m',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      );
    }
    return _card(
      'Kontrola prostokątności (zmierz wbite narożniki)',
      [
        Row(children: [
          Expanded(
            child: FilledButton.tonalIcon(
              onPressed: _check.length >= 4 ? null : _addCheck,
              icon: const Icon(Icons.add_location_alt),
              label: Text('Zmierz narożnik (${_check.length}/4)'),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Cofnij',
            onPressed: _check.isEmpty ? null : () => setState(_check.removeLast),
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            tooltip: 'Wyczyść',
            onPressed: _check.isEmpty ? null : () => setState(_check.clear),
            icon: const Icon(Icons.delete_outline),
          ),
        ]),
        Text(
          'Obejdź budowlę i zmierz 4 narożniki po kolei (A→B→C→D).',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        ?verdict,
      ],
    );
  }

  // — drobne helpery UI —

  Widget _card(String title, List<Widget> children) => Card(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              ...children,
            ],
          ),
        ),
      );

  Widget _metric(String label, String value, {bool highlight = false}) {
    final style = Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
          color: highlight ? Theme.of(context).colorScheme.primary : null,
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        Text(value, style: style),
      ],
    );
  }

  Widget _cornerDot(String label) => DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.indigo, width: 2),
        ),
        child: Center(
          child: Text(label,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.indigo)),
        ),
      );
}
