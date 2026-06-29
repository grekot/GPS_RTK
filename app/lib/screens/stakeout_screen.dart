import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../map/base_layers.dart';
import '../measure/measuring_banner.dart';
import '../measure/point_averager.dart';
import '../measure/point_detail_sheet.dart';
import '../models/measured_point.dart';
import '../models/parcel.dart';
import '../models/rtk_position.dart';
import '../services/app_settings.dart';
import '../services/export_service.dart';
import '../services/measured_point_store.dart';
import '../services/stakeout_report_pdf.dart';
import '../sources/position_source.dart';
import '../utils/geo.dart';

/// Próg [m], poniżej którego wskaźnik przełącza się ze strzałki na tarczę.
const double _nearThreshold = 3.0;

/// Próg [m], poniżej którego uznajemy, że jesteśmy „na punkcie".
const double _arrivedThreshold = 0.3;

/// Ekran tyczenia: prowadzi użytkownika do kolejnych punktów (granicznych,
/// narożników konstrukcji itp.). Źródłem punktów może być działka albo
/// dowolna lista (np. wygenerowany podjazd).
class StakeoutScreen extends StatefulWidget {
  const StakeoutScreen({
    super.key,
    required this.targets,
    required this.title,
    required this.projectId,
    required this.source,
    this.outline = const [],
    this.labels,
    this.pointBpp,
  });

  /// Działka jako źródło punktów granicznych (wygodny konstruktor).
  factory StakeoutScreen.forParcel(Parcel parcel, PositionSource source) =>
      StakeoutScreen(
        targets: parcel.points,
        outline: parcel.points,
        title: 'Tyczenie — ${parcel.number}',
        projectId: parcel.id,
        source: source,
      );

  /// Punkty do wytyczenia.
  final List<LatLng> targets;

  /// Obrys odniesienia rysowany na mapie (działka / budynek / podjazd).
  final List<LatLng> outline;

  /// Etykiety punktów (np. numery z wykazu) — równolegle do [targets].
  final List<String>? labels;

  /// Błąd położenia punktu (BPP) [m] — równolegle do [targets], jeśli znany.
  final List<double?>? pointBpp;

  final String title;

  /// Identyfikator projektu — klucz, pod którym zapisują się pomiary.
  final String projectId;
  final PositionSource source;

  @override
  State<StakeoutScreen> createState() => _StakeoutScreenState();
}

class _StakeoutScreenState extends State<StakeoutScreen> {
  final _mapController = MapController();

  late final List<LatLng> _vertices = _uniqueVertices(widget.targets);
  late final List<LatLng> _outline =
      widget.outline.isNotEmpty ? widget.outline : widget.targets;
  StreamSubscription<RtkPosition>? _subscription;
  StreamSubscription<CompassEvent>? _compassSub;
  RtkPosition? _position;
  double? _deviceHeading; // kierunek z kompasu (magnetometru), stopnie 0–360
  String? _error;
  int _targetIndex = 0;
  bool _followPosition = false;
  int _lastZone = 0; // 0 = daleko ... 3 = przy punkcie

  final _measureStore = MeasuredPointStore();
  List<MeasuredPoint> _measured = [];
  PointAverager? _averager;

  static List<LatLng> _uniqueVertices(List<LatLng> ring) {
    if (ring.length > 1 && ring.first == ring.last) {
      return ring.sublist(0, ring.length - 1);
    }
    return List.of(ring);
  }

  LatLng get _target => _vertices[_targetIndex];

  String get _targetLabel {
    final l = widget.labels;
    return (l != null && _targetIndex < l.length)
        ? l[_targetIndex]
        : '${_targetIndex + 1}';
  }

  double? get _targetBpp {
    final b = widget.pointBpp;
    return (b != null && _targetIndex < b.length) ? b[_targetIndex] : null;
  }

  /// Kierunek, w który zwrócony jest użytkownik: najpierw kompas (działa też
  /// na stojąco), w razie braku — kurs z GPS (tylko podczas ruchu).
  double? get _effectiveHeading => _deviceHeading ?? _position?.heading;

  @override
  void initState() {
    super.initState();
    _subscription = widget.source.positions().listen(
      _onPosition,
      onError: (Object e) {
        setState(() {
          _error = e is StateError || e is UnimplementedError
              ? e.toString().replaceFirst(RegExp(r'^[^:]+: '), '')
              : 'Błąd źródła pozycji: $e';
        });
      },
    );
    // Kompas: dostępny tylko na urządzeniach mobilnych. Na desktopie/web
    // strumień jest null — wtedy prowadzenie działa względem północy.
    final compass = FlutterCompass.events;
    if (compass != null) {
      _compassSub = compass.listen(
        (e) {
          final h = e.heading;
          if (h == null || !mounted) return;
          // Aktualizuj dopiero przy zauważalnej zmianie — mniej przerysowań.
          if (_deviceHeading == null ||
              (h - _deviceHeading!).abs() > 1.5) {
            setState(() => _deviceHeading = h);
          }
        },
        onError: (_) {},
      );
    }
    _loadMeasured();
  }

  Future<void> _loadMeasured() async {
    final pts = await _measureStore.loadForParcel(widget.projectId);
    if (mounted) setState(() => _measured = pts);
  }

  void _onPosition(RtkPosition p) {
    setState(() {
      _position = p;
      _error = null;
    });
    if (_followPosition) {
      _mapController.move(
        LatLng(p.latitude, p.longitude),
        _mapController.camera.zoom,
      );
    }
    _feedbackForDistance(
      distanceMeters(LatLng(p.latitude, p.longitude), _target),
    );

    final avg = _averager;
    if (avg != null) {
      avg.add(p);
      if (avg.isComplete) _finishMeasure(save: true);
    }
  }

  /// Sygnalizacja zbliżania się do punktu: im bliżej, tym mocniejsza wibracja.
  void _feedbackForDistance(double meters) {
    final zone = meters < _arrivedThreshold
        ? 3
        : meters < 1
            ? 2
            : meters < 5
                ? 1
                : 0;
    if (zone > _lastZone) {
      switch (zone) {
        case 3:
          HapticFeedback.heavyImpact();
          SystemSound.play(SystemSoundType.alert);
        case 2:
          HapticFeedback.mediumImpact();
        case 1:
          HapticFeedback.selectionClick();
      }
    }
    _lastZone = zone;
  }

  void _selectTarget(int index) {
    setState(() {
      _targetIndex = (index + _vertices.length) % _vertices.length;
      _lastZone = 0;
    });
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  void _startMeasure() {
    if (_position == null) {
      _snack('Brak pozycji — nie można rozpocząć pomiaru.');
      return;
    }
    setState(() => _averager = PointAverager(
          targetSamples: AppSettings.instance.samples,
          requireFixed: AppSettings.instance.requireFixed,
        ));
  }

  void _cancelMeasure() => setState(() => _averager = null);

  Future<void> _finishMeasure({required bool save}) async {
    final result = _averager?.finalize();
    setState(() => _averager = null);
    if (!save || result == null) return;

    // Wektor od punktu z ewidencji do punktu zmierzonego.
    final off = offsetNorthEast(_target, result.mean);
    final point = MeasuredPoint(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      latitude: result.mean.latitude,
      longitude: result.mean.longitude,
      altitude: result.meanAltitude,
      rms: result.rms,
      meanAccuracy: result.meanAccuracy,
      samples: result.samples,
      worstFix: result.worstFix,
      measuredAt: DateTime.now(),
      label: 'pkt ${_targetIndex + 1}',
      parcelId: widget.projectId,
      targetIndex: _targetIndex,
      devDistance: distanceMeters(_target, result.mean),
      devNorth: off.north,
      devEast: off.east,
    );
    setState(() => _measured.add(point));
    await _measureStore.add(point);
    if (mounted) _showMeasureResult(result, point);
  }

  void _showMeasureResult(AveragedFix avg, MeasuredPoint p) {
    final fixed = avg.worstFix == FixType.rtkFixed;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Zmierzono punkt ${_targetIndex + 1}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Odchyłka od punktu z ewidencji: '
                '${formatDistance(p.devDistance ?? 0)}'),
            Text('  ${p.devNorth! >= 0 ? 'N' : 'S'} ${formatDistance(p.devNorth!)}'
                '   ${p.devEast! >= 0 ? 'E' : 'W'} ${formatDistance(p.devEast!)}'),
            const SizedBox(height: 8),
            Text('Rozrzut pomiaru (RMS): ${formatDistance(avg.rms)}'),
            Text('Próbek: ${avg.samples} · dokł. ±'
                '${avg.meanAccuracy.toStringAsFixed(2)} m'),
            Text('Jakość fixa: ${fixLabel(avg.worstFix)}'),
            if (!fixed)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Uwaga: pomiar nie był w pełni RTK Fixed — wynik orientacyjny.',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _showMeasuredList() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text('Zmierzone punkty (${_measured.length})'),
              trailing: TextButton.icon(
                onPressed: _measured.isEmpty
                    ? null
                    : () {
                        Navigator.of(context).pop();
                        _exportMeasured();
                      },
                icon: const Icon(Icons.ios_share),
                label: const Text('Udostępnij'),
              ),
            ),
            const Divider(height: 1),
            if (_measured.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Brak pomiarów dla tej działki.'),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final m in _measured)
                      ListTile(
                        leading: Icon(
                          m.photoPath != null ? Icons.photo : Icons.place,
                        ),
                        title: Text(m.label ?? m.id),
                        subtitle: Text(
                          '${m.note?.isNotEmpty == true ? '${m.note}\n' : ''}'
                          'odchyłka ${formatDistance(m.devDistance ?? 0)} · '
                          'RMS ${formatDistance(m.rms)} · ${fixLabel(m.worstFix)}',
                        ),
                        isThreeLine: m.note?.isNotEmpty == true,
                        onTap: () {
                          Navigator.of(context).pop();
                          _showPointDetail(m);
                        },
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            await _measureStore.remove(m.id);
                            setState(
                                () => _measured.removeWhere((x) => x.id == m.id));
                            if (context.mounted) Navigator.of(context).pop();
                          },
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportMeasured() async {
    try {
      await ExportService.sharePoints(
        _measured,
        namePrefix: widget.projectId.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-'),
      );
    } catch (e) {
      _snack('Eksport nieudany: $e');
    }
  }

  Future<void> _exportReport() async {
    if (_measured.isEmpty) {
      _snack('Brak zmierzonych punktów do raportu.');
      return;
    }
    try {
      final bytes = await StakeoutReportPdf.build(
        title: widget.title,
        points: _measured,
      );
      await ExportService.sharePdf(bytes, 'raport_tyczenia.pdf');
    } catch (e) {
      _snack('Nie udało się wygenerować raportu: $e');
    }
  }

  Future<void> _showPointDetail(MeasuredPoint point) => showPointDetailSheet(
        context,
        point,
        _measureStore,
        onUpdated: _refreshMeasuredInState,
      );

  void _refreshMeasuredInState(MeasuredPoint p) {
    final i = _measured.indexWhere((x) => x.id == p.id);
    if (i >= 0) setState(() => _measured[i] = p);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _compassSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = _position;
    final current = p == null ? null : LatLng(p.latitude, p.longitude);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'Zmierzone punkty',
            onPressed: _showMeasuredList,
            icon: const Icon(Icons.list_alt),
          ),
          IconButton(
            tooltip: 'Raport tyczenia (PDF)',
            onPressed: _exportReport,
            icon: const Icon(Icons.picture_as_pdf),
          ),
          IconButton(
            tooltip:
                _followPosition ? 'Mapa podąża za pozycją' : 'Mapa zatrzymana',
            onPressed: () =>
                setState(() => _followPosition = !_followPosition),
            icon: Icon(_followPosition ? Icons.gps_fixed : Icons.gps_not_fixed),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCameraFit: CameraFit.coordinates(
                coordinates: _outline,
                padding: const EdgeInsets.fromLTRB(48, 48, 48, 240),
              ),
              maxZoom: 21,
              onPositionChanged: (camera, hasGesture) {
                if (hasGesture && _followPosition) {
                  setState(() => _followPosition = false);
                }
              },
            ),
            children: [
              ValueListenableBuilder<MapBaseLayer>(
                valueListenable: activeBaseLayer,
                builder: (context, layer, _) => buildBaseTileLayer(layer),
              ),
              const UtilitiesOverlay(),
              const BuildingsOverlay(),
              PolygonLayer(
                polygons: [
                  Polygon(
                    points: _outline,
                    color: Colors.teal.withValues(alpha: 0.10),
                    borderColor: Colors.teal,
                    borderStrokeWidth: 2,
                  ),
                ],
              ),
              if (current != null)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: [current, _target],
                      strokeWidth: 3,
                      color: Colors.redAccent,
                      pattern: const StrokePattern.dotted(),
                    ),
                  ],
                ),
              if (p != null && current != null)
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: current,
                      radius: p.accuracy,
                      useRadiusInMeter: true,
                      color: Colors.blue.withValues(alpha: 0.15),
                      borderColor: Colors.blue.withValues(alpha: 0.5),
                      borderStrokeWidth: 1,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  for (final m in _measured)
                    Marker(
                      point: m.latLng,
                      width: 16,
                      height: 16,
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.orange,
                          shape: BoxShape.circle,
                          border: Border.fromBorderSide(
                            BorderSide(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                    ),
                  for (var i = 0; i < _vertices.length; i++)
                    Marker(
                      point: _vertices[i],
                      width: 30,
                      height: 30,
                      child: GestureDetector(
                        onTap: () => _selectTarget(i),
                        child: _VertexMarker(
                          label: '${i + 1}',
                          selected: i == _targetIndex,
                        ),
                      ),
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
                            BorderSide(color: Colors.white, width: 3),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          const Positioned(top: 8, right: 8, child: BaseLayerControl()),
          const Positioned(
            top: 12,
            left: 12,
            child: BaseLayerAttributionLabel(),
          ),
          if (_averager != null)
            Positioned(
              top: 8,
              left: 56,
              right: 56,
              child: MeasuringBanner(
                count: _averager!.count,
                targetSamples: _averager!.targetSamples,
                rms: _averager!.currentRms(),
                onSave: () => _finishMeasure(save: true),
                onCancel: _cancelMeasure,
              ),
            ),
          // Dół: „Zmierz" NAD panelem nawigacji, by nie zasłaniał odczytów.
          // Puste miejsce po lewej od przycisku przepuszcza dotyk do mapy.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (_averager == null)
                  Padding(
                    padding: const EdgeInsets.only(right: 16, bottom: 10),
                    child: FloatingActionButton.extended(
                      heroTag: 'stakeMeasure',
                      onPressed: _startMeasure,
                      icon: const Icon(Icons.add_location_alt),
                      label: const Text('Zmierz'),
                    ),
                  ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                      12, 0, 12, 12 + MediaQuery.viewPaddingOf(context).bottom),
                  child: _StakeoutPanel(
                    position: p,
                    heading: _effectiveHeading,
                    error: _error,
                    target: _target,
                    label: _targetLabel,
                    bpp: _targetBpp,
                    targetCount: _vertices.length,
                    onPrevious: () => _selectTarget(_targetIndex - 1),
                    onNext: () => _selectTarget(_targetIndex + 1),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VertexMarker extends StatelessWidget {
  const _VertexMarker({required this.label, required this.selected});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: selected ? Colors.redAccent : Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: selected ? Colors.red : Colors.teal, width: 2),
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : Colors.teal,
          ),
        ),
      ),
    );
  }
}

class _StakeoutPanel extends StatelessWidget {
  const _StakeoutPanel({
    required this.position,
    required this.heading,
    required this.error,
    required this.target,
    required this.label,
    required this.bpp,
    required this.targetCount,
    required this.onPrevious,
    required this.onNext,
  });

  final RtkPosition? position;
  final double? heading;
  final String? error;
  final LatLng target;
  final String label;
  final double? bpp; // błąd położenia punktu z ewidencji [m]
  final int targetCount;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  static String _fixLabel(FixType f) => switch (f) {
        FixType.rtkFixed => 'RTK Fixed',
        FixType.rtkFloat => 'RTK Float',
        FixType.dgps => 'DGPS',
        FixType.gps => 'GPS',
        FixType.none => 'brak',
      };

  @override
  Widget build(BuildContext context) {
    final p = position;
    final theme = Theme.of(context);

    Widget content;
    if (error != null) {
      content = Text(error!, style: TextStyle(color: theme.colorScheme.error));
    } else if (p == null) {
      content = const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text('Oczekiwanie na pozycję…'),
      );
    } else {
      final current = LatLng(p.latitude, p.longitude);
      final distance = distanceMeters(current, target);
      final bearing = bearingDegrees(current, target);
      final offset = offsetNorthEast(current, target);
      final hasHeading = heading != null;
      final arrived = distance <= _arrivedThreshold;
      final accentColor = arrived ? Colors.green.shade600 : theme.colorScheme.primary;

      // Słowna wskazówka: kierunek względem ciała (z kompasem) lub świata.
      final String cue;
      if (arrived) {
        cue = 'na punkcie';
      } else if (hasHeading) {
        cue = turnInstruction(relativeBearing(bearing, heading!));
      } else {
        cue = 'kierunek ${cardinal(bearing)} (${bearing.round()}°)';
      }

      content = Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _GuidanceIndicator(
            distance: distance,
            bearing: bearing,
            heading: heading,
            color: accentColor,
            gridColor: theme.dividerColor,
            textColor: theme.textTheme.bodySmall!.color!,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatDistance(distance),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: accentColor,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  cue,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  '${offset.north >= 0 ? 'N' : 'S'} '
                  '${formatDistance(offset.north)}   '
                  '${offset.east >= 0 ? 'E' : 'W'} '
                  '${formatDistance(offset.east)}',
                  style: theme.textTheme.bodySmall,
                ),
                Text(
                  '±${p.accuracy.toStringAsFixed(2)} m · ${_fixLabel(p.fixType)}'
                  '${hasHeading ? '' : ' · brak kompasu'}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Poprzedni punkt',
                  onPressed: onPrevious,
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    'Punkt $label z $targetCount',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Następny punkt',
                  onPressed: onNext,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            if (bpp != null)
              Text(
                'Dokładność ewidencyjna punktu (BPP): ±${bpp!.toStringAsFixed(2)} m'
                '${bpp! > 0.3 ? ' — RTK tego nie poprawi!' : ''}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: bpp! > 0.3 ? theme.colorScheme.error : null,
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: content,
            ),
          ],
        ),
      ),
    );
  }
}

/// Wskaźnik kierunku: duża strzałka na dystansie, tarcza celownicza z bliska.
/// Zawsze „idź w stronę wskaźnika" — góra = kierunek, w który patrzysz
/// (gdy jest kompas) lub północ (gdy go brak).
class _GuidanceIndicator extends StatelessWidget {
  const _GuidanceIndicator({
    required this.distance,
    required this.bearing,
    required this.heading,
    required this.color,
    required this.gridColor,
    required this.textColor,
  });

  final double distance;
  final double bearing;
  final double? heading;
  final Color color;
  final Color gridColor;
  final Color textColor;

  static const double _size = 132;

  @override
  Widget build(BuildContext context) {
    final hasHeading = heading != null;
    final dirDeg = hasHeading ? relativeBearing(bearing, heading!) : bearing;
    final angleRad = dirDeg * pi / 180;

    final Widget core = distance >= _nearThreshold
        ? Transform.rotate(
            angle: angleRad,
            child: Icon(Icons.navigation, size: 96, color: color),
          )
        : CustomPaint(
            size: const Size.square(_size),
            painter: _BullseyePainter(
              distance: distance,
              angleRad: angleRad,
              color: color,
              gridColor: gridColor,
              textColor: textColor,
            ),
          );

    return SizedBox(
      width: _size,
      height: _size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          core,
          if (!hasHeading)
            Positioned(
              top: 0,
              child: Text(
                'N',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BullseyePainter extends CustomPainter {
  _BullseyePainter({
    required this.distance,
    required this.angleRad,
    required this.color,
    required this.gridColor,
    required this.textColor,
  });

  final double distance;
  final double angleRad; // 0 = góra
  final Color color;
  final Color gridColor;
  final Color textColor;

  static const _rings = [0.2, 0.5, 1.0, 2.0, 3.0]; // metry

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = size.shortestSide / 2 - 12;
    final scale = maxR / _rings.last;
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = gridColor;

    for (final r in _rings) {
      canvas.drawCircle(center, r * scale, ringPaint);
      final label = r < 1 ? '${(r * 100).round()} cm' : '${r.toInt()} m';
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(color: textColor, fontSize: 9),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, center + Offset(-tp.width / 2, -r * scale - tp.height));
    }

    // Środek = Twoja pozycja (krzyżyk).
    final cross = Paint()
      ..color = textColor
      ..strokeWidth = 1.5;
    canvas.drawLine(center + const Offset(-6, 0), center + const Offset(6, 0), cross);
    canvas.drawLine(center + const Offset(0, -6), center + const Offset(0, 6), cross);

    // Cel jako punkt; idź tak, by sprowadzić go do środka.
    final r = distance.clamp(0.0, _rings.last) * scale;
    final dot = center + Offset(sin(angleRad) * r, -cos(angleRad) * r);
    canvas.drawLine(
      center,
      dot,
      Paint()
        ..color = color
        ..strokeWidth = 2,
    );
    canvas.drawCircle(dot, 8, Paint()..color = color);
    canvas.drawCircle(
      dot,
      8,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = Colors.white
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _BullseyePainter old) =>
      old.distance != distance ||
      old.angleRad != angleRad ||
      old.color != color;
}
