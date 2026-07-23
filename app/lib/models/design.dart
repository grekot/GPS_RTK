import 'dart:math';

import 'package:latlong2/latlong.dart';

import '../geometry/construction.dart';
import '../geometry/local_frame.dart';
import '../geometry/vec2.dart';
import 'building.dart';
import 'parcel.dart';

/// Narzędzia konstrukcyjne (typy elementów projektu).
enum ToolType {
  rownolegla,
  prostopadla,
  prostokat,
  punktyWzdluz,
  przedluzenie,
  obrysOdsuniety, // równoległy obrys całej geometrii (offset pierścienia)
  liniaAzymut, // linia z azymutu i długości (od punktu odniesienia)
  kolo, // koło: środek + promień, N punktów na obwodzie
  luk, // łuk: środek + promień + azymut startu + rozwarcie, N punktów
  punktReczny, // pojedynczy punkt wskazany na mapie (stałe współrzędne)
  punktGps, // punkt z pomiaru terenowego (stałe współrzędne)
  punktPrzeciecie, // punkt na przecięciu dwóch linii (ref + ref2)
  liniaPunkty, // linia między dwoma wybranymi punktami (ref = frozen [a,b])
}

/// Odniesienie elementu do krawędzi pewnej geometrii w obszarze:
/// działki / budynku / innego zapisanego projektu / wcześniejszego elementu
/// w tym samym projekcie. Stabilne między sesjami (po id + indeksie krawędzi).
class GeomRef {
  const GeomRef({
    required this.kind, // 'parcel'|'building'|'design'|'element'|'frozen'
    this.sourceId = '', // id działki/budynku/projektu (dla 'element' puste)
    this.element = -1, // indeks elementu (dla 'element' i 'design')
    this.edge = 0,
    this.frozen, // [aLat,aLon,bLat,bLon] dla 'frozen' (zamrożona krawędź)
  });

  final String kind;
  final String sourceId;
  final int element;
  final int edge;
  final List<double>? frozen;

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'sourceId': sourceId,
        'element': element,
        'edge': edge,
        if (frozen != null) 'frozen': frozen,
      };

  factory GeomRef.fromJson(Map<String, dynamic> j) => GeomRef(
        kind: j['kind'] as String,
        sourceId: (j['sourceId'] as String?) ?? '',
        element: (j['element'] as num?)?.toInt() ?? -1,
        edge: (j['edge'] as num?)?.toInt() ?? 0,
        frozen: (j['frozen'] as List?)
            ?.map((e) => (e as num).toDouble())
            .toList(),
      );

  String get sourceKey => '$kind:$sourceId';
}

/// Pojedynczy element projektu — definicja parametryczna (typ + odniesienie +
/// parametry); geometria jest wyliczana przez [DesignWorld]. `offset` (⊥) i
/// `along` (∥) to umiejscowienie względem krawędzi odniesienia.
class DesignElement {
  DesignElement({required this.tool, required this.ref, this.ref2});

  ToolType tool;
  GeomRef ref;
  GeomRef? ref2; // druga krawędź — tylko dla punktu przecięcia

  double offset = 0;
  double along = 0;
  double? lineLen; // null = długość krawędzi (linia równoległa)
  double length = 5;
  double width = 3;
  double interval = 1;
  double extend = 5;
  double azimuth = 0; // [°] kierunek (linia z azymutu / start łuku)
  double radius = 5; // [m] promień (koło / łuk)
  double sweep = 90; // [°] rozwarcie łuku
  double curvePoints = 8; // liczba punktów na krzywej (koło / łuk)

  Map<String, dynamic> toJson() => {
        'tool': tool.name,
        'ref': ref.toJson(),
        if (ref2 != null) 'ref2': ref2!.toJson(),
        'offset': offset,
        'along': along,
        'lineLen': lineLen,
        'length': length,
        'width': width,
        'interval': interval,
        'extend': extend,
        'azimuth': azimuth,
        'radius': radius,
        'sweep': sweep,
        'curvePoints': curvePoints,
      };

  factory DesignElement.fromJson(Map<String, dynamic> j) {
    final e = DesignElement(
      tool: ToolType.values.byName(j['tool'] as String),
      ref: GeomRef.fromJson(j['ref'] as Map<String, dynamic>),
      ref2: j['ref2'] == null
          ? null
          : GeomRef.fromJson(j['ref2'] as Map<String, dynamic>),
    );
    e.offset = (j['offset'] as num?)?.toDouble() ?? 0;
    e.along = (j['along'] as num?)?.toDouble() ?? 0;
    e.lineLen = (j['lineLen'] as num?)?.toDouble();
    e.length = (j['length'] as num?)?.toDouble() ?? 5;
    e.width = (j['width'] as num?)?.toDouble() ?? 3;
    e.interval = (j['interval'] as num?)?.toDouble() ?? 1;
    e.extend = (j['extend'] as num?)?.toDouble() ?? 5;
    e.azimuth = (j['azimuth'] as num?)?.toDouble() ?? 0;
    e.radius = (j['radius'] as num?)?.toDouble() ?? 5;
    e.sweep = (j['sweep'] as num?)?.toDouble() ?? 90;
    e.curvePoints = (j['curvePoints'] as num?)?.toDouble() ?? 8;
    return e;
  }
}

/// Nazwany projekt geometrii — zbiór elementów odnoszących się do obiektów
/// w obszarze. Trwały i edytowalny ponownie.
class Design {
  Design({
    required this.id,
    required this.name,
    required this.createdAt,
    List<DesignElement>? elements,
    List<GeomRef>? workingLines,
    this.visibleRefs,
  })  : elements = elements ?? [],
        workingLines = workingLines ?? [];

  final String id;
  String name;
  final DateTime createdAt;
  final List<DesignElement> elements;

  /// Linie robocze (pomocnicze) — przedłużenia wskazanych krawędzi, rysowane
  /// przerywaną kreską. Służą tylko jako prowadnice do przyciągania; NIE są
  /// tyczone ani eksportowane.
  final List<GeomRef> workingLines;

  /// Klucze `kind:id` OBCYCH geometrii widocznych w edytorze tego projektu
  /// (biała lista, zapisywana razem z projektem). `null` = projekt sprzed tej
  /// funkcji → pokaż wszystko (zgodność wstecz). Nowy projekt dostaje pusty
  /// zbiór: startuje z czystą mapą, a to, co użytkownik włączy w „Widoczność
  /// geometrii", zostaje zapamiętane per projekt.
  Set<String>? visibleRefs;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'created': createdAt.toIso8601String(),
        'elements': [for (final e in elements) e.toJson()],
        'working': [for (final w in workingLines) w.toJson()],
        if (visibleRefs != null) 'visible': [...visibleRefs!]..sort(),
      };

  factory Design.fromJson(Map<String, dynamic> j) => Design(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? 'Projekt',
        createdAt:
            DateTime.tryParse(j['created'] as String? ?? '') ?? DateTime.now(),
        elements: [
          for (final e in (j['elements'] as List? ?? const []))
            DesignElement.fromJson(e as Map<String, dynamic>),
        ],
        workingLines: [
          for (final w in (j['working'] as List? ?? const []))
            GeomRef.fromJson(w as Map<String, dynamic>),
        ],
        visibleRefs:
            (j['visible'] as List?)?.map((e) => e as String).toSet(),
      );
}

/// Wyliczona geometria elementu (w lokalnym układzie metrycznym [Vec2]).
class ComputedElement {
  const ComputedElement(this.path, this.stake, this.closed);
  final List<Vec2> path;
  final List<Vec2> stake;
  final bool closed;

  bool get isEmpty => path.isEmpty && stake.isEmpty;
}

/// Krawędź odniesienia z etykietą (do wskazywania rodzica na mapie).
class RefSeg {
  RefSeg(this.ref, this.a, this.b, this.label);
  final GeomRef ref;
  final Vec2 a;
  final Vec2 b;
  final String label;
}

/// „Świat" projektowania: wspólny układ lokalny + ringi wszystkich działek i
/// budynków + wszystkie projekty. Wylicza geometrię dowolnego projektu, w tym
/// odniesienia do INNYCH projektów (z cache i przerwaniem cykli).
class DesignWorld {
  DesignWorld({
    required this.parcels,
    required this.buildings,
    required this.designs,
  }) {
    final origin = parcels.isNotEmpty
        ? parcels.first.points.first
        : (buildings.isNotEmpty
            ? buildings.first.points.first
            : const LatLng(0, 0));
    frame = LocalFrame(origin);
    for (final p in parcels) {
      parcelLocal[p.id] = _ring(p.points);
    }
    for (final b in buildings) {
      buildingLocal[b.id] = _ring(b.points);
    }
    _designById = {for (final d in designs) d.id: d};
  }

  final List<Parcel> parcels;
  final List<Building> buildings;
  final List<Design> designs;

  late final LocalFrame frame;
  final Map<String, List<Vec2>> parcelLocal = {};
  final Map<String, List<Vec2>> buildingLocal = {};
  late final Map<String, Design> _designById;
  final Map<String, List<ComputedElement>> _cache = {};

  List<Vec2> _ring(List<LatLng> pts) {
    final v = pts.map(frame.toLocal).toList();
    if (v.length > 1 &&
        v.first.x == v.last.x &&
        v.first.y == v.last.y) {
      v.removeLast();
    }
    return v;
  }

  /// Wylicza geometrię [design] (na żywo). Odniesienia do innych projektów
  /// rozwiązuje przez [_cachedDesign] (z przerwaniem cykli).
  List<ComputedElement> computeDesign(Design design, {Set<String>? visiting}) {
    final v = {...?visiting, design.id};
    final out = <ComputedElement>[];
    for (final el in design.elements) {
      out.add(computeOne(el, out, v));
    }
    return out;
  }

  List<ComputedElement> _cachedDesign(String id, Set<String> visiting) {
    final cached = _cache[id];
    if (cached != null) return cached;
    if (visiting.contains(id)) return const []; // cykl — przerwij
    final d = _designById[id];
    if (d == null) return const [];
    final r = computeDesign(d, visiting: visiting);
    _cache[id] = r;
    return r;
  }

  /// Rozwiązuje odniesienie do odcinka krawędzi (a,b) w układzie lokalnym.
  (Vec2, Vec2)? refSegOf(
    GeomRef ref,
    List<ComputedElement> own,
    Set<String> visiting,
  ) {
    if (ref.kind == 'frozen') {
      final f = ref.frozen;
      if (f == null || f.length != 4) return null;
      return (
        frame.toLocal(LatLng(f[0], f[1])),
        frame.toLocal(LatLng(f[2], f[3])),
      );
    }
    List<Vec2>? ring;
    switch (ref.kind) {
      case 'parcel':
        ring = parcelLocal[ref.sourceId];
      case 'building':
        ring = buildingLocal[ref.sourceId];
      case 'element':
        if (ref.element >= 0 && ref.element < own.length) {
          ring = own[ref.element].path;
        }
      case 'design':
        final g = _cachedDesign(ref.sourceId, visiting);
        if (ref.element >= 0 && ref.element < g.length) {
          ring = g[ref.element].path;
        }
    }
    if (ring == null || ring.length < 2) return null;
    final n = ring.length;
    return (ring[ref.edge % n], ring[(ref.edge + 1) % n]);
  }

  /// Pełny pierścień geometrii wskazanej przez [ref] (cały obrys, nie krawędź).
  List<Vec2>? refRing(
    GeomRef ref,
    List<ComputedElement> own,
    Set<String> visiting,
  ) {
    switch (ref.kind) {
      case 'parcel':
        return parcelLocal[ref.sourceId];
      case 'building':
        return buildingLocal[ref.sourceId];
      case 'element':
        return (ref.element >= 0 && ref.element < own.length)
            ? own[ref.element].path
            : null;
      case 'design':
        final g = _cachedDesign(ref.sourceId, visiting);
        return (ref.element >= 0 && ref.element < g.length)
            ? g[ref.element].path
            : null;
    }
    return null;
  }

  ComputedElement computeOne(
    DesignElement e,
    List<ComputedElement> own,
    Set<String> visiting,
  ) {
    const empty = ComputedElement([], [], false);
    // Typy punktowe nie potrzebują krawędzi odniesienia w klasyczny sposób.
    if (e.tool == ToolType.punktGps || e.tool == ToolType.punktReczny) {
      final f = e.ref.frozen;
      if (f == null || f.length < 2) return empty;
      final pt = frame.toLocal(LatLng(f[0], f[1]));
      return ComputedElement([pt], [pt], false);
    }
    if (e.tool == ToolType.punktPrzeciecie) {
      final s1 = refSegOf(e.ref, own, visiting);
      final r2 = e.ref2;
      final s2 = r2 == null ? null : refSegOf(r2, own, visiting);
      if (s1 == null || s2 == null) return empty;
      final ip = lineIntersection(s1.$1, s1.$2, s2.$1, s2.$2);
      return ip == null ? empty : ComputedElement([ip], [ip], false);
    }
    if (e.tool == ToolType.obrysOdsuniety) {
      final ring = refRing(e.ref, own, visiting);
      if (ring == null || ring.length < 3) return empty;
      final r = offsetRing(ring, e.offset);
      return ComputedElement(r, r, true);
    }
    // Koło / łuk zakotwiczone w PUNKCIE: środek koła = punkt, początek łuku =
    // punkt (środek liczony wstecz z azymutu). Bez krawędzi/offset/along.
    if ((e.tool == ToolType.kolo || e.tool == ToolType.luk) &&
        e.ref.kind == 'point') {
      final f = e.ref.frozen;
      if (f == null || f.length < 2) return empty;
      final p = frame.toLocal(LatLng(f[0], f[1]));
      if (e.tool == ToolType.kolo) return _circleAt(p, e);
      final a0 = e.azimuth * pi / 180;
      return _arcFrom(p - Vec2(sin(a0), cos(a0)) * e.radius, e);
    }
    final seg = refSegOf(e.ref, own, visiting);
    if (seg == null) return empty;
    final (a, b) = seg;
    Vec2 t(Vec2 v) => placeOnEdge(v, a, b, offset: e.offset, along: e.along);
    switch (e.tool) {
      case ToolType.rownolegla:
        final len = e.lineLen ?? (b - a).length;
        final dir = (b - a).normalized;
        final p = t(a), q = t(a + dir * len);
        return ComputedElement([p, q], [p, q], false);
      case ToolType.prostopadla:
        final (p, q) = perpendicularThrough(a, b, (a + b) * 0.5, e.length);
        return ComputedElement([t(p), t(q)], [t(p), t(q)], false);
      case ToolType.prostokat:
        final r = rectangleFromEdge(a, b,
                offset: 0, length: e.length, width: e.width)
            .map(t)
            .toList();
        return ComputedElement(r, r, true);
      case ToolType.punktyWzdluz:
        // path = linia bazowa (do narysowania), stake = punkty co interwał.
        final pts = pointsAlong(a, b, e.interval).map(t).toList();
        return ComputedElement([t(a), t(b)], pts, false);
      case ToolType.przedluzenie:
        // path = linia a→koniec (do narysowania), stake = sam koniec.
        final ext = extend(a, b, e.extend);
        return ComputedElement([t(a), t(ext)], [t(ext)], false);
      case ToolType.liniaAzymut:
        final start = t(a);
        final az = e.azimuth * pi / 180;
        final end = start + Vec2(sin(az), cos(az)) * e.length;
        return ComputedElement([start, end], [start, end], false);
      case ToolType.kolo:
        return _circleAt(t(a), e); // środek na krawędzi (offset/along)
      case ToolType.luk:
        return _arcFrom(t(a), e); // start łuku na krawędzi (offset/along)
      case ToolType.liniaPunkty:
        // Odcinek między dwoma zamrożonymi punktami (ref = frozen [a,b]),
        // bez offset/along — po prostu łączy wskazane punkty.
        return ComputedElement([a, b], [a, b], false);
      case ToolType.obrysOdsuniety:
      case ToolType.punktReczny:
      case ToolType.punktGps:
      case ToolType.punktPrzeciecie:
        return empty; // obsłużone wyżej
    }
  }

  /// Koło o środku [center]: [DesignElement.curvePoints] pkt (clamp 3–720) na
  /// obwodzie o promieniu [DesignElement.radius]. Zamknięte.
  ComputedElement _circleAt(Vec2 center, DesignElement e) {
    final n = e.curvePoints.round().clamp(3, 720);
    final pts = [
      for (var i = 0; i < n; i++)
        center + Vec2(sin(2 * pi * i / n), cos(2 * pi * i / n)) * e.radius,
    ];
    return ComputedElement(pts, pts, true);
  }

  /// Łuk o środku [center]: [DesignElement.curvePoints] pkt (clamp 2–720) od
  /// azymutu startu przez rozwarcie [DesignElement.sweep]. Otwarty.
  ComputedElement _arcFrom(Vec2 center, DesignElement e) {
    final n = e.curvePoints.round().clamp(2, 720);
    final a0 = e.azimuth * pi / 180;
    final sw = e.sweep * pi / 180;
    final pts = [
      for (var i = 0; i < n; i++)
        center +
            Vec2(sin(a0 + sw * i / (n - 1)), cos(a0 + sw * i / (n - 1))) *
                e.radius,
    ];
    return ComputedElement(pts, pts, false);
  }

  /// Wszystkie krawędzie odniesienia dla edytowanego [current] (jego własne
  /// elementy + działki + budynki + inne projekty), z pominięciem [hidden]
  /// (klucze `kind:id`) i samego edytowanego projektu wśród „design".
  List<RefSeg> refSegments(
    Design current,
    List<ComputedElement> currentComputed, {
    Set<String> hidden = const {},
  }) {
    final segs = <RefSeg>[];
    void addRing(
        String kind, String id, List<Vec2>? ring, String label) {
      if (ring == null || ring.length < 2) return;
      if (hidden.contains('$kind:$id')) return;
      for (var i = 0; i < ring.length; i++) {
        segs.add(RefSeg(GeomRef(kind: kind, sourceId: id, edge: i), ring[i],
            ring[(i + 1) % ring.length], '$label k.${i + 1}'));
      }
    }

    // Własne, wcześniejsze elementy (krawędzie ścieżki).
    for (var j = 0; j < currentComputed.length; j++) {
      final c = currentComputed[j];
      if (c.path.length < 2) continue;
      final count = c.closed ? c.path.length : c.path.length - 1;
      for (var k = 0; k < count; k++) {
        segs.add(RefSeg(GeomRef(kind: 'element', element: j, edge: k),
            c.path[k], c.path[(k + 1) % c.path.length], 'Element ${j + 1}·${k + 1}'));
      }
    }
    for (final p in parcels) {
      addRing('parcel', p.id, parcelLocal[p.id], 'Działka ${p.number}');
    }
    for (final b in buildings) {
      addRing('building', b.id, buildingLocal[b.id], 'Budynek');
    }
    for (final d in designs) {
      if (d.id == current.id) continue; // nie odnosimy się do samych siebie
      final g = _cachedDesign(d.id, {});
      for (var j = 0; j < g.length; j++) {
        final c = g[j];
        if (c.path.length < 2) continue;
        if (hidden.contains('design:${d.id}')) continue;
        final count = c.closed ? c.path.length : c.path.length - 1;
        for (var k = 0; k < count; k++) {
          segs.add(RefSeg(
              GeomRef(kind: 'design', sourceId: d.id, element: j, edge: k),
              c.path[k],
              c.path[(k + 1) % c.path.length],
              '${d.name} ${j + 1}·${k + 1}'));
        }
      }
    }
    return segs;
  }

  /// Linia robocza = krawędź [ref] przedłużona o duży zapas [ext] w obie strony
  /// (prowadnica do przyciągania). Null, gdy odniesienie nierozwiązywalne.
  (Vec2, Vec2)? workingLine(
    GeomRef ref,
    List<ComputedElement> own,
    Set<String> visiting, {
    double ext = 500,
  }) {
    final seg = refSegOf(ref, own, visiting);
    if (seg == null) return null;
    final ab = seg.$2 - seg.$1;
    if (ab.length == 0) return null;
    final dir = ab.normalized;
    return (seg.$1 - dir * ext, seg.$2 + dir * ext);
  }

  /// Geometria innych projektów (do narysowania jako tło/odniesienie).
  Map<String, List<ComputedElement>> computeOthers(String exceptId) {
    final out = <String, List<ComputedElement>>{};
    for (final d in designs) {
      if (d.id == exceptId) continue;
      out[d.id] = _cachedDesign(d.id, {});
    }
    return out;
  }
}
