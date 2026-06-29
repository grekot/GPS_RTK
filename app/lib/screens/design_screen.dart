import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../geometry/construction.dart';
import '../geometry/vec2.dart';
import '../map/base_layers.dart';
import '../models/building.dart';
import '../models/design.dart';
import '../models/measured_point.dart';
import '../models/parcel.dart';
import '../models/stakeout_project.dart';
import '../services/export_service.dart';
import '../sources/position_source.dart';
import '../utils/dxf.dart';
import '../utils/geo.dart';
import 'stakeout_screen.dart';

extension _ToolX on ToolType {
  String get label => switch (this) {
        ToolType.rownolegla => 'Linia równoległa',
        ToolType.prostopadla => 'Linia prostopadła',
        ToolType.prostokat => 'Prostokąt / podjazd',
        ToolType.punktyWzdluz => 'Punkty wzdłuż krawędzi',
        ToolType.przedluzenie => 'Przedłużenie krawędzi',
        ToolType.obrysOdsuniety => 'Odsunięcie całego obrysu',
        ToolType.liniaAzymut => 'Linia z azymutu i długości',
        ToolType.kolo => 'Koło (punkty na obwodzie)',
        ToolType.luk => 'Łuk (punkty na krzywej)',
        ToolType.punktReczny => 'Pojedynczy punkt (wskaż na mapie)',
        ToolType.punktGps => 'Punkt z pomiaru GPS',
        ToolType.punktPrzeciecie => 'Punkt przecięcia linii',
      };
  IconData get icon => switch (this) {
        ToolType.rownolegla => Icons.straighten,
        ToolType.prostopadla => Icons.turn_right,
        ToolType.prostokat => Icons.crop_square,
        ToolType.punktyWzdluz => Icons.more_horiz,
        ToolType.przedluzenie => Icons.arrow_outward,
        ToolType.obrysOdsuniety => Icons.select_all,
        ToolType.liniaAzymut => Icons.explore,
        ToolType.kolo => Icons.circle_outlined,
        ToolType.luk => Icons.architecture,
        ToolType.punktReczny => Icons.add_location_alt,
        ToolType.punktGps => Icons.my_location,
        ToolType.punktPrzeciecie => Icons.close,
      };
  bool get isPoint =>
      this == ToolType.punktReczny ||
      this == ToolType.punktGps ||
      this == ToolType.punktPrzeciecie;
  bool get canResize =>
      this == ToolType.rownolegla || this == ToolType.przedluzenie;
}

class _Drag {
  _Drag({
    required this.elem,
    required this.refA,
    required this.refB,
    required this.offset0,
    required this.along0,
    required this.extend0,
    required this.lineLen0,
    required this.grab0,
    required this.grabIndex,
    required this.startCursor,
    required this.metersPerPx,
    required this.snapTargets,
    required this.snapSegments,
    required this.resize,
  });
  final int elem;
  final Vec2 refA;
  final Vec2 refB;
  final double offset0;
  final double along0;
  final double extend0;
  final double lineLen0; // efektywna długość linii w chwili chwytu
  final Vec2 grab0;
  final int grabIndex; // który wierzchołek ścieżki (0/1) chwycono
  final Vec2 startCursor;
  final double metersPerPx;
  final List<Vec2> snapTargets; // punkty-cele przyciągania
  final List<(Vec2, Vec2)> snapSegments; // krawędzie-cele (rzut/przecięcie osi)
  final bool resize; // tryb zmiany długości (prawy przycisk), drugi koniec stały
}

/// Ekran projektowania nazwanej geometrii. Odnosi się do WSZYSTKICH wczytanych
/// działek, budynków i innych projektów w obszarze oraz do własnych elementów.
class DesignScreen extends StatefulWidget {
  const DesignScreen({
    super.key,
    required this.design,
    required this.parcels,
    required this.buildings,
    required this.designs,
    required this.measuredPoints,
    required this.source,
    required this.onSave,
  });

  final Design design;
  final List<Parcel> parcels;
  final List<Building> buildings;
  final List<Design> designs; // wszystkie projekty (do odniesień cross-design)
  final List<MeasuredPoint> measuredPoints; // punkty z pomiarów terenowych
  final PositionSource source;
  final void Function(Design) onSave;

  @override
  State<DesignScreen> createState() => _DesignScreenState();
}

class _DesignScreenState extends State<DesignScreen> {
  final _mapController = MapController();

  late DesignWorld _world;
  late List<ComputedElement> _computed;
  late Map<String, List<ComputedElement>> _others;

  Design get _design => widget.design;

  int? _selected;
  ToolType? _pendingTool;
  bool _pendingWorking = false; // czekamy na wskazanie krawędzi pod linię roboczą
  GeomRef? _intersectFirst; // pierwsza wskazana linia (punkt przecięcia)
  final Set<String> _hidden = {}; // klucze 'kind:id' ukrytych geometrii
  bool _snap = true; // przyciąganie do punktów (wł/wył)
  bool _showWorking = true; // widoczność linii roboczych
  bool _showDims = true; // wyświetlanie wektorów wymiarowych
  int _lastTapMs = 0; // do wykrycia dwukliku (usuwanie linii roboczej)
  Offset _lastTapPos = Offset.zero;

  _Drag? _drag;
  int? _dragPointer;
  Vec2? _snapHighlight;

  final _offset = TextEditingController();
  final _along = TextEditingController();
  final _lineLen = TextEditingController();
  final _length = TextEditingController();
  final _width = TextEditingController();
  final _interval = TextEditingController();
  final _extend = TextEditingController();
  final _azimuth = TextEditingController();
  final _radius = TextEditingController();
  final _sweep = TextEditingController();
  final _curve = TextEditingController();

  @override
  void initState() {
    super.initState();
    _world = DesignWorld(
      parcels: widget.parcels,
      buildings: widget.buildings,
      designs: widget.designs,
    );
    _others = _world.computeOthers(_design.id);
    _recompute();
  }

  void _recompute() => _computed = _world.computeDesign(_design);

  static double _parse(String s, double dflt) =>
      double.tryParse(s.replaceAll(',', '.')) ?? dflt;

  static double _round(double v) => (v * 1000).roundToDouble() / 1000;

  static String _fmt(double v) {
    final r = _round(v);
    return r == r.roundToDouble() ? r.toInt().toString() : r.toString();
  }

  LatLng _ll(Vec2 v) => _world.frame.toLatLng(v);
  // Ochrona mapy: pomijamy geometrię z przekłamaną współrzędną (np. projekt
  // zbudowany na uszkodzonym punkcie) — inaczej flutter_map rzuca asercją
  // LatLngBounds (north ≤ 90) przy liczeniu obrysu do cullingu / CameraFit.
  bool _allValidLL(Iterable<LatLng> pts) =>
      pts.every((p) => isValidLatLng(p.latitude, p.longitude));
  Vec2 _loc(LatLng p) => _world.frame.toLocal(p);

  (Vec2, Vec2)? _parentSeg(int elem) {
    final e = _design.elements[elem];
    return _world.refSegOf(e.ref, _computed, {_design.id});
  }

  /// Czytelna nazwa odniesienia (do nagłówka „względem …").
  String _refLabel(GeomRef ref) {
    switch (ref.kind) {
      case 'parcel':
        final i = widget.parcels.indexWhere((p) => p.id == ref.sourceId);
        return i < 0 ? 'działki' : 'działki ${widget.parcels[i].number}';
      case 'building':
        return 'budynku';
      case 'design':
        final i = widget.designs.indexWhere((d) => d.id == ref.sourceId);
        return i < 0 ? 'projektu' : 'projektu „${widget.designs[i].name}"';
      case 'element':
        return 'elementu ${ref.element + 1}';
      case 'frozen':
        return 'krawędzi zamrożonej';
      default:
        return ref.kind;
    }
  }

  static double _distToSeg(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (len2 == 0) return (p - a).distance;
    final t = (((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / len2)
        .clamp(0.0, 1.0);
    return (p - Offset(a.dx + ab.dx * t, a.dy + ab.dy * t)).distance;
  }

  /// Usuwa linię roboczą pod pozycją [px] (ekran). Zwraca true, gdy usunięto.
  bool _deleteWorkingLineAt(Offset px) {
    final camera = _mapController.camera;
    for (var i = 0; i < _design.workingLines.length; i++) {
      final ws = _world.workingLine(_design.workingLines[i], _computed, {
        _design.id,
      });
      if (ws == null) continue;
      final a = camera.latLngToScreenOffset(_ll(ws.$1));
      final b = camera.latLngToScreenOffset(_ll(ws.$2));
      if (_distToSeg(px, a, b) < 10) {
        setState(() => _design.workingLines.removeAt(i));
        _snack('Usunięto linię roboczą.');
        return true;
      }
    }
    return false;
  }

  // ——— Dodawanie / wybór / usuwanie ———

  Future<void> _pickToolToAdd() async {
    final picked = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true, // lista typów jest długa — pozwól na pełną wysokość
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              dense: true,
              title: Text('Dodaj — wybierz typ, potem wskaż krawędź'),
            ),
            const Divider(height: 1),
            for (final t in ToolType.values)
              ListTile(
                leading: Icon(t.icon),
                title: Text(t.label),
                onTap: () => Navigator.pop(ctx, t),
              ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.timeline),
              title: const Text('Linia robocza (przedłużenie)'),
              subtitle: const Text('przerywana prowadnica do przyciągania '
                  '— nie jest tyczona'),
              onTap: () => Navigator.pop(ctx, 'working'),
            ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    if (picked == 'working') {
      setState(() {
        _pendingWorking = true;
        _pendingTool = null;
        _intersectFirst = null;
        _selected = null;
      });
      _bindControllers();
      return;
    }
    final tool = picked as ToolType;
    if (tool == ToolType.punktGps) {
      await _addGpsPoint();
      return;
    }
    setState(() {
      _pendingTool = tool;
      _pendingWorking = false;
      _intersectFirst = null;
      _selected = null;
    });
    _bindControllers();
  }

  void _createElementWith(DesignElement e) {
    setState(() {
      _design.elements.add(e);
      _pendingTool = null;
      _intersectFirst = null;
      _selected = _design.elements.length - 1;
      _recompute();
    });
    _bindControllers();
  }

  void _createElement(ToolType tool, GeomRef ref) {
    final e = DesignElement(tool: tool, ref: ref);
    if (tool == ToolType.rownolegla) e.offset = 3;
    _createElementWith(e);
  }

  Future<void> _addGpsPoint() async {
    if (widget.measuredPoints.isEmpty) {
      _snack('Brak zapisanych punktów. Zmierz punkt na mapie głównej '
          '(„Zmierz punkt").');
      return;
    }
    final mp = await showModalBottomSheet<MeasuredPoint>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
                dense: true, title: Text('Dodaj punkt z pomiaru GPS')),
            const Divider(height: 1),
            for (final p in widget.measuredPoints)
              ListTile(
                leading: const Icon(Icons.my_location),
                title: Text(p.label ?? p.id),
                subtitle: Text('±${p.meanAccuracy.toStringAsFixed(2)} m · '
                    '${p.latitude.toStringAsFixed(6)}, '
                    '${p.longitude.toStringAsFixed(6)}'),
                onTap: () => Navigator.pop(ctx, p),
              ),
          ],
        ),
      ),
    );
    if (mp == null) return;
    _createElementWith(DesignElement(
      tool: ToolType.punktGps,
      ref: GeomRef(kind: 'point', frozen: [mp.latitude, mp.longitude]),
    ));
  }

  void _selectElement(int? i) {
    setState(() => _selected = i);
    _bindControllers();
  }

  /// „Zamraża" krawędź elementu [elem] (tę o indeksie [edge]) w obecnym
  /// położeniu — referencja absolutna (LatLng), niezależna od tego elementu.
  GeomRef _frozenRefFor(int elem, int edge) {
    final path = _computed[elem].path;
    if (path.length < 2) return const GeomRef(kind: 'frozen');
    final n = path.length;
    final a = _ll(path[edge % n]);
    final b = _ll(path[(edge + 1) % n]);
    return GeomRef(
      kind: 'frozen',
      frozen: [a.latitude, a.longitude, b.latitude, b.longitude],
    );
  }

  Future<void> _deleteSelected() async {
    final i = _selected;
    if (i == null) return;
    final dependents = <int>[
      for (var j = 0; j < _design.elements.length; j++)
        if (_design.elements[j].ref.kind == 'element' &&
            _design.elements[j].ref.element == i)
          j,
    ];
    if (dependents.isNotEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Element ma zależne elementy'),
          content: Text(
            'Na tym elemencie zbudowano ${dependents.length} '
            '${dependents.length == 1 ? 'element' : 'elementy'}. '
            'Zostaną „zamrożone" w obecnym położeniu (przestaną podążać za tym '
            'elementem), a element pomocniczy zostanie usunięty.',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Anuluj')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Usuń i zamroź')),
          ],
        ),
      );
      if (ok != true) return;
      // Zamroź zależne na obecnej krawędzi usuwanego elementu.
      for (final j in dependents) {
        final e = _design.elements[j];
        e.ref = _frozenRefFor(i, e.ref.edge);
      }
    }
    setState(() {
      _design.elements.removeAt(i);
      for (final e in _design.elements) {
        if (e.ref.kind == 'element' && e.ref.element > i) {
          e.ref =
              GeomRef(kind: 'element', element: e.ref.element - 1, edge: e.ref.edge);
        }
      }
      _selected = null;
      _recompute();
    });
    _bindControllers();
  }

  void _bindControllers() {
    final e = _selected == null ? null : _design.elements[_selected!];
    _offset.text = e == null ? '' : _fmt(e.offset);
    _along.text = e == null ? '' : _fmt(e.along);
    _lineLen.text = (e == null || e.lineLen == null) ? '' : _fmt(e.lineLen!);
    _length.text = e == null ? '' : _fmt(e.length);
    _width.text = e == null ? '' : _fmt(e.width);
    _interval.text = e == null ? '' : _fmt(e.interval);
    _extend.text = e == null ? '' : _fmt(e.extend);
    _azimuth.text = e == null ? '' : _fmt(e.azimuth);
    _radius.text = e == null ? '' : _fmt(e.radius);
    _sweep.text = e == null ? '' : _fmt(e.sweep);
    _curve.text = e == null ? '' : _fmt(e.curvePoints);
  }

  void _editParam(VoidCallback apply) {
    setState(() {
      apply();
      _recompute();
    });
  }

  // ——— Przeciąganie (raw pointer; aktualizuje offset / along / extend) ———

  Vec2 _pxToLocal(Offset px) => _loc(_mapController.camera.screenOffsetToLatLng(px));

  double _metersPerPx() {
    final c = _mapController.camera;
    final p1 = _loc(c.screenOffsetToLatLng(const Offset(0, 100)));
    return (p1 - _pxToLocal(Offset.zero)).length / 100.0;
  }

  void _onPointerDown(PointerDownEvent ev) {
    if (_drag != null) return;
    final isRight = ev.buttons == kSecondaryButton;
    final camera = _mapController.camera;
    final cursor = ev.localPosition;
    // Dwuklik lewym → usuń linię roboczą pod kursorem.
    if (!isRight) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final isDouble =
          (now - _lastTapMs) < 350 && (cursor - _lastTapPos).distance < 24;
      _lastTapMs = now;
      _lastTapPos = cursor;
      if (isDouble && _deleteWorkingLineAt(cursor)) return;
    }
    var bestD = 30.0;
    int? hitElem;
    var hitIndex = 0;
    Vec2? grab;
    for (var i = 0; i < _computed.length; i++) {
      final path = _computed[i].path;
      if (path.length < 2) continue; // punkty nie mają uchwytów
      for (var k = 0; k < path.length; k++) {
        final d = (camera.latLngToScreenOffset(_ll(path[k])) - cursor).distance;
        if (d <= bestD) {
          bestD = d;
          hitElem = i;
          hitIndex = k;
          grab = path[k];
        }
      }
    }
    if (hitElem == null || grab == null) return;
    final elem = hitElem;
    final e = _design.elements[elem];
    if (isRight && !e.tool.canResize) return; // resize tylko dla linii
    final seg = _parentSeg(elem);
    if (seg == null) return;
    final effLen = e.lineLen ?? (seg.$2 - seg.$1).length;
    final targets = <Vec2>[
      for (final ring in _world.parcelLocal.values) ...ring,
      for (final ring in _world.buildingLocal.values) ...ring,
      for (final g in _others.values)
        for (final c in g) ...c.path,
    ];
    for (var i = 0; i < _computed.length; i++) {
      if (i == elem) continue;
      targets
        ..addAll(_computed[i].path)
        ..addAll(_computed[i].stake);
    }
    // Linie robocze (widoczne) jako prowadnice przyciągania.
    final workingSegs = <(Vec2, Vec2)>[
      if (_showWorking)
        for (final ref in _design.workingLines)
          ?_world.workingLine(ref, _computed, {_design.id}),
    ];
    // Krawędzie-cele do przyciągania długości (oś linii ∩ krawędź), bez krawędzi
    // samego przeciąganego elementu + linie robocze.
    final snapSegs = <(Vec2, Vec2)>[
      for (final s in _world.refSegments(_design, _computed, hidden: _hidden))
        if (!(s.ref.kind == 'element' && s.ref.element == elem)) (s.a, s.b),
      ...workingSegs,
    ];
    setState(() {
      _selected = elem;
      _dragPointer = ev.pointer;
      if (isRight && e.tool == ToolType.rownolegla && e.lineLen == null) {
        e.lineLen = effLen; // skonkretyzuj długość przed zmianą
      }
      _drag = _Drag(
        elem: elem,
        refA: seg.$1,
        refB: seg.$2,
        offset0: e.offset,
        along0: e.along,
        extend0: e.extend,
        lineLen0: effLen,
        grab0: grab!,
        grabIndex: hitIndex,
        startCursor: _pxToLocal(cursor),
        metersPerPx: _metersPerPx(),
        snapTargets: targets,
        snapSegments: snapSegs,
        resize: isRight,
      );
      _snapHighlight = null;
    });
    _bindControllers();
  }

  void _onPointerMove(PointerMoveEvent ev) {
    final drag = _drag;
    if (drag == null || ev.pointer != _dragPointer) return;
    final cursor = _pxToLocal(ev.localPosition);
    final e = _design.elements[drag.elem];

    // Resize (prawy przycisk): zmiana długości wzdłuż osi linii, drugi koniec stały.
    if (drag.resize) {
      double atLeast(double v) => v < 0.1 ? 0.1 : v;
      final dir = (drag.refB - drag.refA).normalized;
      // Surowy koniec na osi linii, potem przyciąganie do pobliskiego punktu LUB
      // do przecięcia osi z pobliską krawędzią; długość = rzut na oś (kierunek stały).
      final rawEnd = drag.grab0 + dir * (cursor - drag.startCursor).dot(dir);
      Vec2 snapped = rawEnd;
      if (_snap) {
        final candidates = <Vec2>[...drag.snapTargets];
        final axisP2 = drag.grab0 + dir;
        for (final s in drag.snapSegments) {
          final ip = lineIntersection(drag.grab0, axisP2, s.$1, s.$2);
          // Tylko przecięcie leżące na RZECZYWISTYM odcinku (nie na jego
          // przedłużeniu) — inaczej koniec skakał do pustych miejsc.
          if (ip != null && pointToSegmentDistance(ip, s.$1, s.$2) < 1e-3) {
            candidates.add(ip);
          }
        }
        snapped = snapToNearest(rawEnd, candidates, 24 * drag.metersPerPx);
      }
      final isSnapped = (snapped - rawEnd).length > 1e-9;
      final d = (snapped - drag.grab0).dot(dir);
      setState(() {
        if (e.tool == ToolType.rownolegla) {
          if (drag.grabIndex == 1) {
            e.lineLen = _round(atLeast(drag.lineLen0 + d));
          } else {
            e.along = _round(drag.along0 + d);
            e.lineLen = _round(atLeast(drag.lineLen0 - d));
          }
        } else {
          // przedłużenie
          if (drag.grabIndex == 1) {
            e.extend = _round(drag.extend0 + d);
          } else {
            e.along = _round(drag.along0 + d);
            e.extend = _round(drag.extend0 - d);
          }
        }
        _recompute();
        _snapHighlight = isSnapped ? snapped : null;
      });
      _lineLen.text = e.lineLen == null ? '' : _fmt(e.lineLen!);
      _along.text = _fmt(e.along);
      _extend.text = _fmt(e.extend);
      return;
    }

    final raw = drag.grab0 + (cursor - drag.startCursor);
    Vec2 target = raw;
    if (_snap) {
      // Kandydaci: punkty + rzut na krawędzie/linie robocze (na odcinek, więc
      // ląduje na realnej krawędzi, nie na jej przedłużeniu).
      final candidates = <Vec2>[
        ...drag.snapTargets,
        for (final s in drag.snapSegments)
          closestPointOnSegment(raw, s.$1, s.$2),
      ];
      target = snapToNearest(raw, candidates, 24 * drag.metersPerPx);
    }
    final snapped = (target - raw).length > 1e-9;
    final (dAlong, dPerp) =
        decomposeOnEdge(target - drag.grab0, drag.refA, drag.refB);
    setState(() {
      e.offset = _round(drag.offset0 + dPerp);
      if (e.tool == ToolType.przedluzenie) {
        e.extend = _round(drag.extend0 + dAlong);
      } else {
        e.along = _round(drag.along0 + dAlong);
      }
      _recompute();
      _snapHighlight = snapped ? target : null;
    });
    _offset.text = _fmt(e.offset);
    if (e.tool == ToolType.przedluzenie) {
      _extend.text = _fmt(e.extend);
    } else {
      _along.text = _fmt(e.along);
    }
  }

  void _onPointerUp(PointerEvent ev) {
    if (ev.pointer != _dragPointer) return;
    setState(() {
      _drag = null;
      _dragPointer = null;
      _snapHighlight = null;
    });
  }

  // ——— Mapa: wskazanie odniesienia / wybór elementu ———

  void _onMapTap(LatLng point) {
    final local = _loc(point);
    if (_pendingWorking) {
      final segs = _world.refSegments(_design, _computed, hidden: _hidden);
      if (segs.isEmpty) {
        _snack('Brak widocznych krawędzi.');
        return;
      }
      final i = nearestSegmentIndex([for (final s in segs) (s.a, s.b)], local);
      setState(() {
        _design.workingLines.add(segs[i].ref);
        _pendingWorking = false;
      });
      _snack('Dodano linię roboczą (dwuklik usuwa).');
      return;
    }
    if (_pendingTool == ToolType.punktReczny) {
      var pos = local;
      if (_snap) {
        final candidates = <Vec2>[
          for (final ring in _world.parcelLocal.values) ...ring,
          for (final ring in _world.buildingLocal.values) ...ring,
          for (final g in _others.values)
            for (final c in g) ...c.path,
          for (final c in _computed) ...[...c.path, ...c.stake],
        ];
        if (_showWorking) {
          for (final ref in _design.workingLines) {
            final ws = _world.workingLine(ref, _computed, {_design.id});
            if (ws != null) {
              candidates.add(closestPointOnLine(local, ws.$1, ws.$2));
            }
          }
        }
        pos = snapToNearest(local, candidates, 24 * _metersPerPx());
      }
      final ll = _ll(pos);
      _createElementWith(DesignElement(
        tool: ToolType.punktReczny,
        ref: GeomRef(kind: 'point', frozen: [ll.latitude, ll.longitude]),
      ));
      return;
    }
    if (_pendingTool != null) {
      final segs = _world.refSegments(_design, _computed, hidden: _hidden);
      if (segs.isEmpty) {
        _snack('Brak widocznych linii/krawędzi.');
        return;
      }
      final i = nearestSegmentIndex([for (final s in segs) (s.a, s.b)], local);
      if (_pendingTool == ToolType.punktPrzeciecie) {
        if (_intersectFirst == null) {
          setState(() => _intersectFirst = segs[i].ref);
          _snack('Wskaż drugą linię.');
        } else {
          _createElementWith(DesignElement(
            tool: ToolType.punktPrzeciecie,
            ref: _intersectFirst!,
            ref2: segs[i].ref,
          ));
        }
      } else {
        _createElement(_pendingTool!, segs[i].ref);
      }
      return;
    }
    final mpp = _metersPerPx();
    int? best;
    var bestD = 24 * mpp;
    for (var i = 0; i < _computed.length; i++) {
      final c = _computed[i];
      final n = c.closed ? c.path.length : c.path.length - 1;
      for (var k = 0; k < n && c.path.length >= 2; k++) {
        final d = pointToSegmentDistance(
            local, c.path[k], c.path[(k + 1) % c.path.length]);
        if (d < bestD) {
          bestD = d;
          best = i;
        }
      }
      for (final v in c.stake) {
        final d = (v - local).length;
        if (d < bestD) {
          bestD = d;
          best = i;
        }
      }
    }
    _selectElement(best);
  }

  // ——— Nazwa / zapis / tyczenie / eksport ———

  void _save() {
    widget.onSave(_design);
    _snack('Zapisano projekt „${_design.name}".');
  }

  Future<void> _rename() async {
    final ctrl = TextEditingController(text: _design.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nazwa projektu'),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Anuluj')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('OK')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      setState(() => _design.name = name);
    }
  }

  Future<void> _visibility() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          Widget tile(String key, String label, IconData icon) => SwitchListTile(
                dense: true,
                secondary: Icon(icon),
                title: Text(label, overflow: TextOverflow.ellipsis),
                value: !_hidden.contains(key),
                onChanged: (v) {
                  setLocal(() => setState(() {
                        if (v) {
                          _hidden.remove(key);
                        } else {
                          _hidden.add(key);
                        }
                      }));
                },
              );
          return SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                const ListTile(
                    dense: true, title: Text('Widoczność geometrii')),
                const Divider(height: 1),
                for (final p in widget.parcels)
                  tile('parcel:${p.id}', 'Działka ${p.number}', Icons.crop_free),
                for (final b in widget.buildings)
                  tile('building:${b.id}', 'Budynek ${b.id}',
                      Icons.home_work_outlined),
                for (final d in widget.designs)
                  if (d.id != _design.id)
                    tile('design:${d.id}', 'Projekt: ${d.name}',
                        Icons.architecture),
              ],
            ),
          );
        },
      ),
    );
  }

  List<LatLng> _allStakeLL() =>
      [for (final c in _computed) for (final v in c.stake) _ll(v)];

  void _goStakeout() {
    final stake = _allStakeLL();
    if (stake.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StakeoutScreen(
          targets: stake,
          outline: (_computed.length == 1 && _computed.first.closed)
              ? _computed.first.path.map(_ll).toList()
              : (widget.parcels.isNotEmpty
                  ? widget.parcels.first.points
                  : const []),
          title: 'Tyczenie — ${_design.name}',
          projectId: 'design:${_design.id}',
          source: widget.source,
        ),
      ),
    );
  }

  Future<void> _exportProject() async {
    final stake = _allStakeLL();
    if (stake.isEmpty) return;
    final shapes = [
      for (final c in _computed)
        if (c.path.isNotEmpty) (path: c.path.map(_ll).toList(), closed: c.closed),
    ];
    final project = StakeoutProject(
      name: _design.name,
      createdAt: DateTime.now(),
      reference: widget.parcels.isNotEmpty
          ? widget.parcels.first.points
          : (widget.buildings.isNotEmpty ? widget.buildings.first.points : const []),
      construction: shapes.isEmpty ? const [] : shapes.first.path,
      constructionClosed: shapes.isNotEmpty && shapes.first.closed,
      extraConstructions: shapes.skip(1).toList(),
      stakePoints: stake,
    );
    final dxf = DxfBuilder();
    if (project.reference.length >= 2) {
      dxf.addLatLngPolyline(project.reference,
          layer: DxfBuilder.layerParcels, color: 5, closed: true);
    }
    for (final s in shapes) {
      dxf.addLatLngPolyline(s.path,
          layer: DxfBuilder.layerConstructions, color: 6, closed: s.closed);
    }
    for (var i = 0; i < stake.length; i++) {
      dxf.addLatLngPoint(stake[i],
          layer: DxfBuilder.layerPoints, color: 1, label: '${i + 1}');
    }
    try {
      await ExportService.shareTextFiles({
        'projekt.geojson': project.toGeoJson(),
        'projekt.dxf': dxf.build(),
      }, subject: 'Projekt tyczenia');
    } catch (e) {
      _snack('Eksport nieudany: $e');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    for (final c in [
      _offset,
      _along,
      _lineLen,
      _length,
      _width,
      _interval,
      _extend,
      _azimuth,
      _radius,
      _sweep,
      _curve,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sel = _selected == null ? null : _design.elements[_selected!];

    final allPts = <LatLng>[
      for (final p in widget.parcels) ...p.points,
      for (final b in widget.buildings) ...b.points,
    ].where((p) => isValidLatLng(p.latitude, p.longitude)).toList();

    final closedPolys = <({List<LatLng> pts, bool selected})>[];
    final openLines = <({List<LatLng> pts, bool selected})>[];
    final stakeLL = <LatLng>[];
    final selStakeLL = <LatLng>[]; // punkty wybranego elementu (podświetlenie)
    final handleLL = <LatLng>[];
    for (var i = 0; i < _computed.length; i++) {
      final c = _computed[i];
      if (c.isEmpty) continue;
      final isSel = i == _selected;
      (isSel ? selStakeLL : stakeLL).addAll(
          c.stake.map(_ll).where((p) => isValidLatLng(p.latitude, p.longitude)));
      // Linie/wielokąty (≥2 pkt) rysujemy i dajemy uchwyty; punkty — tylko kropka.
      if (c.path.length >= 2) {
        final pathLL = c.path.map(_ll).toList();
        if (_allValidLL(pathLL)) {
          (c.closed ? closedPolys : openLines)
              .add((pts: pathLL, selected: isSel));
          handleLL.addAll(pathLL);
        }
      }
    }
    // Inne projekty (tło/odniesienie).
    final otherLines = <List<LatLng>>[];
    _others.forEach((id, g) {
      if (_hidden.contains('design:$id')) return;
      for (final c in g) {
        if (c.path.length < 2) continue;
        final ll = c.path.map(_ll).toList();
        if (_allValidLL(ll)) otherLines.add(ll);
      }
    });
    // Linie robocze (przerywane prowadnice).
    final workingLL = <List<LatLng>>[];
    if (_showWorking) {
      for (final ref in _design.workingLines) {
        final ws = _world.workingLine(ref, _computed, {_design.id});
        if (ws != null) {
          final ll = [_ll(ws.$1), _ll(ws.$2)];
          if (_allValidLL(ll)) workingLL.add(ll);
        }
      }
    }
    List<LatLng>? refEdgeLL;
    final dimMain = <List<LatLng>>[]; // główne linie wymiarowe (przerywane)
    final dimHeads = <List<LatLng>>[]; // groty (wypełnione trójkąty)
    final dimLabels = <({LatLng at, String text})>[];
    void addDim(Vec2 p, Vec2 q, String text, {required bool withLine}) {
      if ((q - p).length < 1e-6) return;
      final pll = _ll(p), qll = _ll(q);
      if (!_allValidLL([pll, qll])) return;
      if (withLine) dimMain.add([pll, qll]);
      dimHeads.addAll(_dimHeads(p, q).where(_allValidLL));
      dimLabels.add((at: _ll((p + q) * 0.5), text: text));
    }

    if (sel != null) {
      final seg = _parentSeg(_selected!);
      if (seg != null) {
        final ll = [_ll(seg.$1), _ll(seg.$2)];
        if (_allValidLL(ll)) refEdgeLL = ll;
      }
      if (_showDims && seg != null && !sel.tool.isPoint) {
        // 1) Umiejscowienie względem krawędzi bazowej (∥ along, ⊥ offset).
        final (a, b) = seg;
        final dir = (b - a).normalized;
        final corner = a + dir * sel.along;
        final anchor = corner + dir.perpLeft * sel.offset; // placeOnEdge(a)
        if (sel.along.abs() > 0.01) {
          addDim(a, corner, '∥ ${_fmt(sel.along.abs())} m', withLine: true);
        }
        if (sel.offset.abs() > 0.01) {
          addDim(corner, anchor, '⊥ ${_fmt(sel.offset.abs())} m',
              withLine: true);
        }
      }
      if (_showDims && !sel.tool.isPoint) {
        // 2) Wymiary własne geometrii: długość linii / boki prostokąta.
        final path = _computed[_selected!].path;
        const lineTools = {
          ToolType.rownolegla,
          ToolType.prostopadla,
          ToolType.przedluzenie,
          ToolType.punktyWzdluz,
          ToolType.liniaAzymut,
        };
        final sides = <(Vec2, Vec2)>[
          if (sel.tool == ToolType.prostokat && path.length >= 3) ...[
            (path[0], path[1]),
            (path[1], path[2]),
          ] else if (lineTools.contains(sel.tool) && path.length >= 2)
            (path[0], path[1]),
        ];
        for (final s in sides) {
          // linia geometrii jest już narysowana → tylko groty + etykieta.
          addDim(s.$1, s.$2, '${_fmt((s.$2 - s.$1).length)} m',
              withLine: false);
        }
      }
    }

    final pointCount = _computed.fold<int>(0, (s, c) => s + c.stake.length);

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) widget.onSave(_design);
      },
      child: Scaffold(
        appBar: AppBar(
          title: GestureDetector(
            onTap: _rename,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                    child: Text(_design.name, overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 6),
                const Icon(Icons.edit, size: 16),
              ],
            ),
          ),
          actions: [
            IconButton(
              tooltip: _snap
                  ? 'Przyciąganie do punktów: WŁ'
                  : 'Przyciąganie do punktów: WYŁ',
              isSelected: _snap,
              onPressed: () => setState(() => _snap = !_snap),
              icon: Icon(_snap ? Icons.adjust : Icons.location_disabled),
            ),
            IconButton(
              tooltip: _showWorking
                  ? 'Linie robocze: WŁ'
                  : 'Linie robocze: WYŁ',
              isSelected: _showWorking,
              onPressed: () => setState(() => _showWorking = !_showWorking),
              icon: const Icon(Icons.timeline),
            ),
            IconButton(
              tooltip: _showDims ? 'Wymiary: WŁ' : 'Wymiary: WYŁ',
              isSelected: _showDims,
              onPressed: () => setState(() => _showDims = !_showDims),
              icon: const Icon(Icons.square_foot),
            ),
            IconButton(
              tooltip: 'Widoczność geometrii',
              onPressed: _visibility,
              icon: const Icon(Icons.layers_outlined),
            ),
            IconButton(
              tooltip: 'Zapisz projekt',
              onPressed: _save,
              icon: const Icon(Icons.save_outlined),
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  Listener(
                    onPointerDown: _onPointerDown,
                    onPointerMove: _onPointerMove,
                    onPointerUp: _onPointerUp,
                    onPointerCancel: _onPointerUp,
                    child: FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCameraFit: allPts.isEmpty
                            ? null
                            : CameraFit.coordinates(
                                coordinates: allPts,
                                padding: const EdgeInsets.all(40)),
                        initialCenter: _world.frame.origin,
                        initialZoom: 17,
                        maxZoom: 22,
                        interactionOptions: InteractionOptions(
                          // Bez dwukliku-zoom — dwuklik usuwa linię roboczą.
                          flags: (_drag != null
                                  ? (InteractiveFlag.all & ~InteractiveFlag.drag)
                                  : InteractiveFlag.all) &
                              ~InteractiveFlag.doubleTapZoom,
                        ),
                        onTap: (tapPosition, point) => _onMapTap(point),
                      ),
                      children: [
                        ValueListenableBuilder<MapBaseLayer>(
                          valueListenable: activeBaseLayer,
                          builder: (context, layer, _) =>
                              buildBaseTileLayer(layer),
                        ),
                        const UtilitiesOverlay(),
                        const BuildingsOverlay(),
                        PolygonLayer(
                          polygons: [
                            for (final b in widget.buildings)
                              if (!_hidden.contains('building:${b.id}'))
                                Polygon(
                                  points: b.points,
                                  color: Colors.brown.withValues(alpha: 0.15),
                                  borderColor: Colors.brown,
                                  borderStrokeWidth: 1.5,
                                ),
                            for (final p in widget.parcels)
                              if (!_hidden.contains('parcel:${p.id}'))
                                Polygon(
                                  points: p.points,
                                  color: Colors.teal.withValues(alpha: 0.10),
                                  borderColor: Colors.teal,
                                  borderStrokeWidth: 1.5,
                                ),
                            for (final poly in closedPolys)
                              Polygon(
                                points: poly.pts,
                                color:
                                    (poly.selected ? Colors.green : Colors.blue)
                                        .withValues(alpha: 0.18),
                                borderColor:
                                    poly.selected ? Colors.green : Colors.blue,
                                borderStrokeWidth: poly.selected ? 3 : 2,
                              ),
                          ],
                        ),
                        PolylineLayer(
                          polylines: [
                            for (final w in workingLL)
                              Polyline(
                                points: w,
                                color: Colors.amber.shade800,
                                strokeWidth: 2,
                                pattern: StrokePattern.dashed(
                                    segments: const [10, 6]),
                              ),
                            for (final line in otherLines)
                              Polyline(
                                  points: line,
                                  color: Colors.purple.withValues(alpha: 0.6),
                                  strokeWidth: 2),
                            if (refEdgeLL != null)
                              Polyline(
                                  points: refEdgeLL,
                                  color: Colors.red,
                                  strokeWidth: 4),
                            for (final m in dimMain)
                              Polyline(
                                points: m,
                                color: Colors.deepOrange,
                                strokeWidth: 2,
                                pattern: StrokePattern.dashed(
                                    segments: const [6, 4]),
                              ),
                            for (final line in openLines)
                              Polyline(
                                points: line.pts,
                                color:
                                    line.selected ? Colors.green : Colors.blue,
                                strokeWidth: line.selected ? 4 : 3,
                              ),
                          ],
                        ),
                        if (dimHeads.isNotEmpty)
                          PolygonLayer(
                            polygons: [
                              for (final h in dimHeads)
                                Polygon(
                                  points: h,
                                  color: Colors.deepOrange,
                                  borderStrokeWidth: 0,
                                ),
                            ],
                          ),
                        MarkerLayer(
                          markers: [
                            for (final pt in stakeLL) _dot(pt, Colors.orange),
                            for (final pt in selStakeLL)
                              _dot(pt, Colors.green, big: true),
                            for (final pt in handleLL) _handleDot(pt),
                            if (_snapHighlight != null)
                              _snapRing(_ll(_snapHighlight!)),
                            for (final d in dimLabels)
                              Marker(
                                point: d.at,
                                width: 96,
                                height: 24,
                                child: _dimChip(d.text),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Positioned(top: 8, right: 8, child: BaseLayerControl()),
                  if (_pendingWorking)
                    const Positioned(
                      top: 8,
                      left: 12,
                      right: 64,
                      child: _Banner(
                        icon: Icons.timeline,
                        text: 'Wskaż krawędź do przedłużenia (linia robocza)',
                      ),
                    ),
                  if (_pendingTool != null)
                    Positioned(
                      top: 8,
                      left: 12,
                      right: 64,
                      child: _Banner(
                        icon: Icons.touch_app,
                        text: switch (_pendingTool!) {
                          ToolType.punktReczny =>
                            'Dotknij miejsca, by wstawić punkt',
                          ToolType.punktPrzeciecie => _intersectFirst == null
                              ? 'Wskaż pierwszą linię'
                              : 'Wskaż drugą linię',
                          _ => 'Wskaż krawędź odniesienia dla: '
                              '${_pendingTool!.label}',
                        },
                      ),
                    ),
                  if (_drag != null && sel != null)
                    Positioned(
                      top: 8,
                      left: 12,
                      right: 64,
                      child: _Banner(
                        icon: _drag!.resize ? Icons.straighten : Icons.open_with,
                        text: _drag!.resize
                            ? (sel.tool == ToolType.przedluzenie
                                ? 'Długość przedłużenia ${_fmt(sel.extend)} m'
                                : 'Długość ${_fmt(sel.lineLen ?? 0)} m')
                            : (sel.tool == ToolType.przedluzenie
                                ? 'Wysunięcie ∥ ${_fmt(sel.extend)} m   '
                                    'Odsunięcie ⊥ ${_fmt(sel.offset)} m'
                                : 'Odsunięcie ⊥ ${_fmt(sel.offset)} m   '
                                    'Wzdłuż ∥ ${_fmt(sel.along)} m'),
                      ),
                    ),
                ],
              ),
            ),
            _controls(sel, pointCount),
          ],
        ),
      ),
    );
  }

  Marker _dot(LatLng p, Color color, {bool big = false}) => Marker(
        point: p,
        width: big ? 18 : 13,
        height: big ? 18 : 13,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: const Border.fromBorderSide(
                BorderSide(color: Colors.white, width: 2)),
          ),
        ),
      );

  Marker _handleDot(LatLng p) => Marker(
        point: p,
        width: 18,
        height: 18,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.indigo, width: 3),
          ),
        ),
      );

  /// Wypełnione groty (trójkąty) na obu końcach wymiaru p→q — małe, w metrach.
  /// Zwraca listę trójkątów (po 3 punkty LatLng) do narysowania w PolygonLayer.
  List<List<LatLng>> _dimHeads(Vec2 p, Vec2 q) {
    final u = q - p;
    final len = u.length;
    if (len < 1e-6) return const [];
    final dir = u.normalized;
    final perp = dir.perpLeft;
    final l = (len * 0.12).clamp(0.1, 0.35).toDouble(); // długość grotu
    final w = l * 0.5;
    return [
      // wierzchołek w q, podstawa cofnięta o l (grot „na zewnątrz")
      [_ll(q), _ll(q - dir * l + perp * w), _ll(q - dir * l - perp * w)],
      // wierzchołek w p
      [_ll(p), _ll(p + dir * l + perp * w), _ll(p + dir * l - perp * w)],
    ];
  }

  Widget _dimChip(String text) => Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.deepOrange,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            text,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600),
          ),
        ),
      );

  Marker _snapRing(LatLng p) => Marker(
        point: p,
        width: 30,
        height: 30,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.green, width: 3),
            color: Colors.green.withValues(alpha: 0.25),
          ),
        ),
      );

  Widget _controls(DesignElement? sel, int pointCount) {
    final theme = Theme.of(context);
    return Material(
      elevation: 8,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            // Stała wysokość paska — zaznaczenie elementu nie przesuwa mapy.
            // Nadmiar (np. 2 rzędy pól na wąskim ekranie) przewija się wewnątrz.
            height: 148,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
            if (_pendingTool != null || _pendingWorking)
              Row(
                children: [
                  Expanded(
                    child: Text(_pendingWorking
                        ? 'Dotknij krawędzi, którą przedłużyć jako linię roboczą.'
                        : _pendingTool == ToolType.punktReczny
                            ? 'Dotknij miejsca na mapie, by wstawić pojedynczy '
                                'punkt.'
                            : 'Dotknij krawędzi (działka, budynek, inny projekt '
                                'lub element), względem której utworzyć.'),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _pendingTool = null;
                      _pendingWorking = false;
                    }),
                    child: const Text('Anuluj'),
                  ),
                ],
              )
            else ...[
              if (sel != null) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        sel.tool.isPoint
                            ? 'Element ${_selected! + 1}: ${sel.tool.label}'
                            : 'Element ${_selected! + 1}: ${sel.tool.label} · '
                                'względem ${_refLabel(sel.ref)}',
                        style: theme.textTheme.labelLarge,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Usuń element',
                      onPressed: () {
                        _deleteSelected();
                      },
                      icon: const Icon(Icons.delete_outline),
                    ),
                    IconButton(
                      tooltip: 'Odznacz',
                      onPressed: () => _selectElement(null),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                if (sel.tool.isPoint)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      switch (sel.tool) {
                        ToolType.punktGps =>
                          'Punkt stały z pomiaru GPS (bez parametrów).',
                        ToolType.punktPrzeciecie =>
                          'Punkt na przecięciu dwóch linii (bez parametrów).',
                        _ => 'Pojedynczy punkt wskazany na mapie '
                            '(bez parametrów).',
                      },
                      style: theme.textTheme.bodySmall,
                    ),
                  )
                else
                  _paramRow(sel),
                const SizedBox(height: 8),
              ] else
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _design.elements.isEmpty
                        ? 'Dodaj element i wskaż krawędź odniesienia '
                            '(dowolna geometria w obszarze).'
                        : 'Dotknij elementu, by go edytować, lub przeciągnij ⬤.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_design.elements.length} elem. · $pointCount pkt',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _pickToolToAdd,
                    icon: const Icon(Icons.add),
                    label: const Text('Dodaj'),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: 'Eksport (GeoJSON)',
                    onPressed: pointCount == 0 ? null : _exportProject,
                    icon: const Icon(Icons.ios_share),
                  ),
                  const SizedBox(width: 2),
                  FilledButton.icon(
                    onPressed: pointCount == 0 ? null : _goStakeout,
                    icon: const Icon(Icons.flag_outlined),
                    label: const Text('Tycz'),
                  ),
                ],
              ),
            ],
                ],
              ),
            ),
          ),
          SizedBox(height: MediaQuery.viewPaddingOf(context).bottom),
        ],
      ),
    );
  }

  Widget _paramRow(DesignElement e) {
    final fields = _paramFields(e);
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 8.0;
        final w = constraints.maxWidth;
        final n = fields.length;
        final cols = (w >= 480 ? n : (w >= 320 ? 2 : 1)).clamp(1, n);
        final fieldW = (w - (cols - 1) * gap) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: 8,
          children: [for (final f in fields) SizedBox(width: fieldW, child: f)],
        );
      },
    );
  }

  List<Widget> _paramFields(DesignElement e) {
    Widget field(
      TextEditingController c,
      String label,
      void Function(String) onChanged, {
      bool flip = false,
      VoidCallback? onFlip,
      String? hint,
      String unit = 'm',
    }) {
      return Row(
        children: [
          Expanded(
            child: TextField(
              controller: c,
              keyboardType: const TextInputType.numberWithOptions(
                  decimal: true, signed: true),
              decoration: InputDecoration(
                  labelText: '$label [$unit]', isDense: true, hintText: hint),
              onChanged: onChanged,
            ),
          ),
          if (flip)
            IconButton(
              tooltip: 'Zmień stronę (+/−)',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
              iconSize: 20,
              onPressed: onFlip,
              icon: const Icon(Icons.swap_horiz),
            ),
        ],
      );
    }

    final offsetField = field(
      _offset,
      'Odsunięcie ⊥',
      (t) => _editParam(() => e.offset = _parse(t, e.offset)),
      flip: true,
      onFlip: () {
        _editParam(() => e.offset = -e.offset);
        _offset.text = _fmt(e.offset);
      },
    );
    final alongField = field(_along, 'Wzdłuż ∥',
        (t) => _editParam(() => e.along = _parse(t, e.along)));

    switch (e.tool) {
      case ToolType.rownolegla:
        final seg = _parentSeg(_selected!);
        final edgeLen = seg == null ? 0.0 : (seg.$2 - seg.$1).length;
        return [
          offsetField,
          alongField,
          field(
              _lineLen,
              'Długość',
              (t) => _editParam(
                  () => e.lineLen = t.trim().isEmpty ? null : _parse(t, 0)),
              hint: edgeLen.toStringAsFixed(2)),
        ];
      case ToolType.prostopadla:
        return [
          field(_length, 'Długość',
              (t) => _editParam(() => e.length = _parse(t, e.length))),
          alongField,
          offsetField,
        ];
      case ToolType.prostokat:
        return [
          field(_length, 'Długość',
              (t) => _editParam(() => e.length = _parse(t, e.length))),
          field(_width, 'Szerokość',
              (t) => _editParam(() => e.width = _parse(t, e.width))),
          offsetField,
          alongField,
        ];
      case ToolType.punktyWzdluz:
        return [
          field(_interval, 'Co ile',
              (t) => _editParam(() => e.interval = _parse(t, e.interval))),
          offsetField,
          alongField,
        ];
      case ToolType.przedluzenie:
        return [
          field(_extend, 'Wysunięcie',
              (t) => _editParam(() => e.extend = _parse(t, e.extend))),
          offsetField,
        ];
      case ToolType.obrysOdsuniety:
        return [
          field(
            _offset,
            'Odsunięcie',
            (t) => _editParam(() => e.offset = _parse(t, e.offset)),
            flip: true,
            onFlip: () {
              _editParam(() => e.offset = -e.offset);
              _offset.text = _fmt(e.offset);
            },
          ),
        ];
      case ToolType.liniaAzymut:
        return [
          field(_azimuth, 'Azymut',
              (t) => _editParam(() => e.azimuth = _parse(t, e.azimuth)),
              unit: '°'),
          field(_length, 'Długość',
              (t) => _editParam(() => e.length = _parse(t, e.length))),
          offsetField,
          alongField,
        ];
      case ToolType.kolo:
        return [
          field(_radius, 'Promień',
              (t) => _editParam(() => e.radius = _parse(t, e.radius))),
          field(_curve, 'Punktów',
              (t) => _editParam(() => e.curvePoints = _parse(t, e.curvePoints)),
              unit: 'pkt'),
          offsetField,
          alongField,
        ];
      case ToolType.luk:
        return [
          field(_radius, 'Promień',
              (t) => _editParam(() => e.radius = _parse(t, e.radius))),
          field(_azimuth, 'Azymut startu',
              (t) => _editParam(() => e.azimuth = _parse(t, e.azimuth)),
              unit: '°'),
          field(_sweep, 'Rozwarcie',
              (t) => _editParam(() => e.sweep = _parse(t, e.sweep)), unit: '°'),
          field(_curve, 'Punktów',
              (t) => _editParam(() => e.curvePoints = _parse(t, e.curvePoints)),
              unit: 'pkt'),
          offsetField,
          alongField,
        ];
      case ToolType.punktReczny:
      case ToolType.punktGps:
      case ToolType.punktPrzeciecie:
        return const []; // punkty nie mają parametrów liczbowych
    }
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 8),
            Flexible(child: Text(text, style: const TextStyle(fontSize: 13))),
          ],
        ),
      ),
    );
  }
}
