import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:open_filex/open_filex.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'map/base_layers.dart';
import 'map/tile_cache.dart';
import 'map/tile_math.dart';
import 'measure/measuring_banner.dart';
import 'measure/point_averager.dart';
import 'measure/point_detail_sheet.dart';
import 'measure/utility_category.dart';
import 'models/building.dart';
import 'models/design.dart';
import 'models/device_telemetry.dart';
import 'models/measured_point.dart';
import 'models/parcel.dart';
import 'models/rtk_position.dart';
import 'models/stakeout_project.dart';
import 'rtk/ntrip_client.dart';
import 'screens/area_screen.dart';
import 'screens/building_layout_screen.dart';
import 'screens/design_screen.dart';
import 'screens/heights_screen.dart';
import 'screens/mountpoint_picker.dart';
import 'screens/settings_screen.dart';
import 'screens/stakeout_screen.dart';
import 'services/app_settings.dart';
import 'services/backup_service.dart';
import 'services/building_store.dart';
import 'services/design_store.dart';
import 'services/export_service.dart';
import 'services/kiut_service.dart';
import 'services/manual_pdf.dart';
import 'services/measured_point_store.dart';
import 'services/ntrip_store.dart';
import 'services/parcel_store.dart';
import 'services/uldk_service.dart';
import 'services/update_service.dart';
import 'sources/ble_receiver_source.dart';
import 'sources/nmea_log_source.dart';
import 'sources/phone_gnss_source.dart';
import 'sources/position_source.dart';
import 'sources/serial_receiver_source.dart';
import 'sources/usb_receiver_source.dart';
import 'utils/boundary_import.dart';
import 'utils/geo.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Przepnij wbudowany cache kafelków na trwały katalog (offline po restarcie).
  await MapCache.init();
  await AppSettings.load();
  // Ukryj paski systemowe (m.in. dolny pasek nawigacji) — więcej miejsca na mapę.
  // Tryb „sticky": paski pojawiają się po przeciągnięciu palcem od krawędzi i
  // po chwili znów się chowają. Na desktopie to no-op.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const GpsRtkApp());
}

class GpsRtkApp extends StatefulWidget {
  const GpsRtkApp({super.key});

  @override
  State<GpsRtkApp> createState() => _GpsRtkAppState();
}

class _GpsRtkAppState extends State<GpsRtkApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Po powrocie z tła system potrafi przywrócić paski — wymuś tryb ponownie.
    if (state == AppLifecycleState.resumed) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GPS RTK',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _mapController = MapController();
  final _bleSource = BleReceiverSource();
  final _nmeaSource = NmeaLogSource();
  // USB-serial: tylko Android (usb_serial nie ma natywnej części gdzie indziej).
  final UsbReceiverSource? _usbSource =
      Platform.isAndroid ? UsbReceiverSource() : null;
  // Port szeregowy / COM: desktop (Windows pokazuje odbiornik jako COMx).
  final SerialReceiverSource? _serialSource =
      (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
          ? SerialReceiverSource()
          : null;
  late final List<PositionSource> _sources = [
    PhoneGnssSource(),
    _bleSource,
    if (_usbSource != null) _usbSource,
    if (_serialSource != null) _serialSource,
    _nmeaSource,
  ];
  final _ntripStore = NtripStore();
  StreamSubscription<String>? _bleStatusSub;
  StreamSubscription<String>? _usbStatusSub;
  StreamSubscription<String>? _serialStatusSub;
  StreamSubscription<DeviceTelemetry>? _bleTelemetrySub;
  DeviceTelemetry? _telemetry;
  final _uldk = UldkService();
  final _store = ParcelStore();
  final _measureStore = MeasuredPointStore();
  final _kiut = KiutService();
  final _buildingStore = BuildingStore();
  final _designStore = DesignStore();

  late PositionSource _source = _sources.first;
  StreamSubscription<RtkPosition>? _subscription;
  RtkPosition? _position;

  // Watchdog świeżości: licznik sekund od ostatniej pozycji (zerowany przy
  // każdej nowej). Licznik tyknięć zamiast DateTime.now() — testowalny
  // sztucznym zegarem i odporny na zmianę czasu systemowego.
  Timer? _staleTimer;
  int _staleTicks = 0;
  String? _error;
  bool _followPosition = true;
  bool _busy = false;
  List<Parcel> _parcels = [];

  // Zbieranie punktów uzbrojenia / odniesienia.
  PointAverager? _averager;
  UtilityCategory? _measuringCategory;
  String? _measuringLabel; // etykieta pomiaru, gdy bez kategorii (punkt odniesienia)
  List<MeasuredPoint> _utilityPoints = [];
  List<MeasuredPoint> _allMeasured = []; // wszystkie zmierzone (dla designera)

  List<Building> _buildings = [];
  List<Design> _designs = [];
  final Set<String> _hiddenLayers = {}; // ukryte warstwy mapy ('parcel:id' itd.)

  @override
  void initState() {
    super.initState();
    _initParcels();
    _loadUtilityPoints();
    _loadBuildings();
    _loadDesigns();
    _loadNtrip();
    _bleStatusSub = _bleSource.statusMessages.listen(_showMessage);
    _usbStatusSub = _usbSource?.statusMessages.listen(_showMessage);
    _serialStatusSub = _serialSource?.statusMessages.listen(_showMessage);
    _bleTelemetrySub = _bleSource.telemetry.listen((t) {
      if (mounted) setState(() => _telemetry = t);
    });
  }

  Future<void> _loadNtrip() async {
    _applyNtrip(await _ntripStore.load());
  }

  /// Ustawia konfigurację NTRIP na wszystkich źródłach-odbiornikach (BLE + USB
  /// + COM) — caster i poprawki są wspólne, niezależnie od transportu.
  void _applyNtrip(NtripConfig? c) {
    _bleSource.ntripConfig = c;
    _usbSource?.ntripConfig = c;
    _serialSource?.ntripConfig = c;
  }

  Future<void> _loadUtilityPoints() async {
    final all = await _measureStore.loadAll();
    if (!mounted) return;
    setState(() {
      _allMeasured = all;
      _utilityPoints = all.where((p) => p.category != null).toList();
    });
  }

  Future<void> _loadBuildings() async {
    final b = await _buildingStore.load();
    if (!mounted) return;
    setState(() => _buildings = b);
  }

  Future<void> _loadDesigns() async {
    final d = await _designStore.load();
    if (!mounted) return;
    setState(() => _designs = d);
  }

  Future<void> _saveDesign(Design design) async {
    final all = await _designStore.saveOne(design);
    if (!mounted) return;
    setState(() => _designs = all);
  }

  Future<void> _openDesign(Design design) async {
    // Odśwież punkty z pomiarów ze schowka (także te zmierzone w tyczeniu),
    // żeby były widoczne w „Dodaj → Punkt z pomiaru GPS" — inaczej designer
    // dostawał nieaktualną listę i świeżo zmierzonego punktu nie było.
    await _loadUtilityPoints();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DesignScreen(
          design: design,
          parcels: _parcels,
          buildings: _buildings,
          designs: _designs,
          measuredPoints: _allMeasured,
          source: _source,
          onSave: _saveDesign,
        ),
      ),
    );
  }

  /// Ekran „Wysokości i spadki" — z odświeżoną listą punktów ze schowka.
  Future<void> _openHeights() async {
    await _loadUtilityPoints();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HeightsScreen(points: _allMeasured),
      ),
    );
  }

  Future<void> _newDesign() async {
    if (_parcels.isEmpty && _buildings.isEmpty) {
      _showMessage('Najpierw wczytaj działkę lub budynek — to punkty odniesienia.');
      return;
    }
    final controller =
        TextEditingController(text: 'Projekt ${_designs.length + 1}');
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nowy projekt geometrii'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nazwa projektu'),
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Anuluj')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('Projektuj')),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    await _openDesign(Design(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name.trim(),
      createdAt: DateTime.now(),
    ));
  }

  Future<void> _showDesignList() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text('Projekty geometrii (${_designs.length})'),
              trailing: TextButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  _newDesign();
                },
                icon: const Icon(Icons.add),
                label: const Text('Nowy'),
              ),
            ),
            const Divider(height: 1),
            if (_designs.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Brak projektów. „Nowy" tworzy projekt względem '
                    'wczytanych działek/budynków.'),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final d in _designs)
                      ListTile(
                        leading: const Icon(Icons.architecture),
                        title: Text(d.name),
                        subtitle: Text('${d.elements.length} elem.'),
                        onTap: () {
                          Navigator.of(context).pop();
                          _openDesign(d);
                        },
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            final all = await _designStore.delete(d.id);
                            if (!mounted) return;
                            setState(() => _designs = all);
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

  Future<void> _openSettings() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
    if (saved == true && mounted) {
      if (_isRunning && AppSettings.instance.keepAwake) {
        WakelockPlus.enable();
      } else {
        WakelockPlus.disable();
      }
    }
  }

  /// Widoczność warstw mapy (działki, budynki, projekty, uzbrojenie).
  Future<void> _showVisibility() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) {
          Widget tile(String key, String label, IconData icon) =>
              SwitchListTile(
                dense: true,
                secondary: Icon(icon),
                title: Text(label, overflow: TextOverflow.ellipsis),
                value: !_hiddenLayers.contains(key),
                onChanged: (v) => setLocal(() => setState(() {
                      if (v) {
                        _hiddenLayers.remove(key);
                      } else {
                        _hiddenLayers.add(key);
                      }
                    })),
              );
          final empty = _parcels.isEmpty &&
              _buildings.isEmpty &&
              _designs.isEmpty &&
              _utilityPoints.isEmpty;
          return SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                const ListTile(dense: true, title: Text('Widoczność warstw')),
                const Divider(height: 1),
                if (empty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Brak warstw do ukrycia.'),
                  ),
                if (_utilityPoints.isNotEmpty)
                  tile('utilities', 'Punkty uzbrojenia (${_utilityPoints.length})',
                      Icons.account_tree_outlined),
                for (final p in _parcels)
                  tile('parcel:${p.id}', 'Działka ${p.number}', Icons.crop_free),
                for (final b in _buildings)
                  tile('building:${b.id}', 'Budynek ${b.id}',
                      Icons.home_work_outlined),
                for (final d in _designs)
                  tile('design:${d.id}', 'Projekt: ${d.name}',
                      Icons.architecture),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Lista niepusta i wszystkie wierzchołki w poprawnym zakresie? (ochrona mapy
  /// przed wyjątkiem flutter_map, gdy w danych trafi się przekłamana lub pusta
  /// geometria). Alias na wspólny, przetestowany `allValidLatLng`.
  bool _allValidLL(Iterable<LatLng> pts) => allValidLatLng(pts);

  List<Widget> _designMapLayers() {
    if (_designs.isEmpty) return const [];
    final world = DesignWorld(
      parcels: _parcels,
      buildings: _buildings,
      designs: _designs,
    );
    final lines = <List<LatLng>>[];
    final polys = <List<LatLng>>[];
    final stakes = <LatLng>[];
    for (final d in _designs) {
      if (_hiddenLayers.contains('design:${d.id}')) continue;
      for (final c in world.computeDesign(d)) {
        if (c.path.length >= 2) {
          final ll = c.path.map(world.frame.toLatLng).toList();
          // Pomiń geometrię z przekłamaną współrzędną (np. projekt zbudowany na
          // uszkodzonym punkcie) — inaczej flutter_map wywala asercję
          // LatLngBounds przy liczeniu obrysu do cullingu.
          if (ll.every((p) => isValidLatLng(p.latitude, p.longitude))) {
            (c.closed ? polys : lines).add(ll);
          }
        }
        stakes.addAll(c.stake
            .map(world.frame.toLatLng)
            .where((p) => isValidLatLng(p.latitude, p.longitude)));
      }
    }
    return [
      if (polys.isNotEmpty)
        PolygonLayer(
          polygons: [
            for (final pts in polys)
              Polygon(
                points: pts,
                color: Colors.purple.withValues(alpha: 0.15),
                borderColor: Colors.purple,
                borderStrokeWidth: 2,
              ),
          ],
        ),
      if (lines.isNotEmpty)
        PolylineLayer(
          polylines: [
            for (final pts in lines)
              Polyline(points: pts, color: Colors.purple, strokeWidth: 3),
          ],
        ),
      if (stakes.isNotEmpty)
        MarkerLayer(
          markers: [
            for (final p in stakes)
              Marker(
                point: p,
                width: 12,
                height: 12,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.purple,
                    shape: BoxShape.circle,
                    border: Border.fromBorderSide(
                        BorderSide(color: Colors.white, width: 2)),
                  ),
                ),
              ),
          ],
        ),
    ];
  }

  Future<void> _initParcels() async {
    var parcels = await _store.load();
    if (parcels.isEmpty) {
      parcels = [await _loadAssetParcel()];
      await _store.save(parcels);
    }
    if (!mounted) return;
    setState(() => _parcels = parcels);
    if (parcels.isNotEmpty) _nmeaSource.demoCenter = parcels.first.points.first;
  }

  Future<void> _loadNmeaLog() async {
    const group = XTypeGroup(label: 'Log NMEA', extensions: ['txt', 'nmea', 'log']);
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null) return;
    final content = await file.readAsString();
    final parsed = content
        .split(RegExp(r'\r?\n'))
        .where((l) => l.trim().startsWith(r'$'))
        .toList();
    setState(() => _nmeaSource.lines = parsed.isEmpty ? null : parsed);
    await _switchSource(_nmeaSource);
    if (!_isRunning) _start();
    _showMessage(parsed.isEmpty
        ? 'Brak zdań NMEA w pliku — uruchamiam symulator.'
        : 'Wczytano log NMEA (${parsed.length} zdań).');
  }

  Future<Parcel> _loadAssetParcel() async {
    final raw = await rootBundle.loadString('assets/dzialka_222_1.geojson');
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final feature = (json['features'] as List).first as Map<String, dynamic>;
    final coords =
        ((feature['geometry'] as Map<String, dynamic>)['coordinates'] as List)
            .first as List;
    return Parcel(
      id: '120205_2.0001.222/1',
      number: '222/1',
      region: 'Gnojnik',
      commune: 'Gnojnik',
      county: 'brzeski',
      fetchedAt: DateTime.now(),
      points: [
        for (final c in coords)
          LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
      ],
    );
  }

  bool get _isRunning => _subscription != null;

  /// Sekundy od ostatniej pozycji, gdy dane są już nieświeże (inaczej null).
  int? get _staleSeconds => _isRunning &&
          _position != null &&
          _staleTicks >= positionStaleSeconds
      ? _staleTicks
      : null;

  void _start() {
    setState(() => _error = null);
    if (AppSettings.instance.keepAwake) WakelockPlus.enable();
    _staleTicks = 0;
    _staleTimer?.cancel();
    _staleTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _staleTicks++;
      // Przerysowanie tylko gdy ostrzeżenie widoczne (aktualizacja licznika).
      if (_staleSeconds != null && mounted) setState(() {});
    });
    _subscription = _source.positions().listen(
      (p) {
        // Strażnik: odrzuć przekłamaną pozycję, by nie zatruć kamery mapy
        // (lat > 90 → asercja flutter_map). Parser i tak powinien ją odrzucić.
        if (!isValidLatLng(p.latitude, p.longitude)) return;
        _staleTicks = 0;
        setState(() => _position = p);
        if (_followPosition) {
          _mapController.move(
            LatLng(p.latitude, p.longitude),
            _mapController.camera.zoom,
          );
        }
        final avg = _averager;
        if (avg != null) {
          avg.add(p);
          if (avg.isComplete) _finishMeasure(save: true);
        }
      },
      onError: (Object e) {
        // Strumień broadcast nie kończy subskrypcji przy błędzie — anuluj
        // jawnie, żeby licznik słuchaczy źródła spadł do zera i połączenie
        // zostało zamknięte (inaczej kolejny Start nie odpaliłby connect()).
        _subscription?.cancel();
        _staleTimer?.cancel();
        _staleTimer = null;
        setState(() {
          _error = e is StateError || e is UnimplementedError
              ? e.toString().replaceFirst(RegExp(r'^[^:]+: '), '')
              : 'Błąd źródła pozycji: $e';
          _subscription = null;
        });
      },
    );
    setState(() {});
  }

  Future<void> _stop() async {
    WakelockPlus.disable();
    _staleTimer?.cancel();
    _staleTimer = null;
    await _subscription?.cancel();
    setState(() {
      _subscription = null;
      _telemetry = null;
    });
  }

  Future<void> _switchSource(PositionSource source) async {
    final wasRunning = _isRunning;
    await _stop();
    setState(() {
      _source = source;
      _telemetry = null;
    });
    if (wasRunning) _start();
  }

  /// Desktop: przed przełączeniem na źródło COM pozwól wybrać port (gdy jest
  /// więcej niż jeden; przy jednym wybiera automatycznie).
  Future<void> _pickSerialPortThenSwitch() async {
    final src = _serialSource;
    if (src == null) return;
    final ports = SerialReceiverSource.portsWithInfo();
    if (ports.isEmpty) {
      _showMessage('Nie wykryto portów COM. Podłącz odbiornik kablem USB '
          'i poczekaj na sterownik (CP210x/CH340).');
      return;
    }
    String? chosen;
    if (ports.length == 1) {
      chosen = ports.first.name;
    } else {
      chosen = await showModalBottomSheet<String>(
        context: context,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                dense: true,
                title: Text('Wybierz port odbiornika (COM)'),
              ),
              const Divider(height: 1),
              for (final p in ports)
                ListTile(
                  leading: const Icon(Icons.usb),
                  title: Text(p.name),
                  subtitle: p.description == null ? null : Text(p.description!),
                  onTap: () => Navigator.of(context).pop(p.name),
                ),
            ],
          ),
        ),
      );
    }
    if (chosen == null || !mounted) return;
    src.portName = chosen;
    await _switchSource(src);
  }

  void _fitToParcel(Parcel parcel) {
    final pts = parcel.points
        .where((p) => isValidLatLng(p.latitude, p.longitude))
        .toList();
    if (pts.isEmpty) return;
    _mapController.fitCamera(
      CameraFit.coordinates(
        coordinates: pts,
        padding: const EdgeInsets.all(48),
      ),
    );
    setState(() => _followPosition = false);
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _addParcel(Parcel parcel, {bool focus = true}) async {
    final existing = _parcels.indexWhere((p) => p.id == parcel.id);
    setState(() {
      if (existing >= 0) {
        _parcels[existing] = parcel;
      } else {
        _parcels.add(parcel);
      }
    });
    await _store.save(_parcels);
    if (focus) _fitToParcel(parcel);
    _showMessage(existing >= 0
        ? 'Odświeżono działkę ${parcel.label}'
        : 'Dodano działkę ${parcel.label}');
  }

  Future<void> _removeParcel(Parcel parcel) async {
    setState(() => _parcels.removeWhere((p) => p.id == parcel.id));
    await _store.save(_parcels);
  }

  Future<T?> _withBusy<T>(Future<T> Function() action) async {
    setState(() => _busy = true);
    try {
      return await action();
    } on UldkException catch (e) {
      _showMessage(e.message);
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _fetchParcelAt(LatLng point) async {
    final parcel =
        await _withBusy(() => _uldk.findByPoint(point.longitude, point.latitude));
    if (parcel != null) await _addParcel(parcel, focus: false);
  }

  Future<void> _fetchBuildingAt(LatLng point) async {
    final building = await _withBusy(
      () => _uldk.findBuildingByXY(point.longitude, point.latitude),
    );
    if (building == null) return;
    final exists = _buildings.indexWhere((b) => b.id == building.id);
    setState(() {
      if (exists >= 0) {
        _buildings[exists] = building;
      } else {
        _buildings.add(building);
      }
    });
    await _buildingStore.save(_buildings);
    _showMessage(exists >= 0 ? 'Odświeżono budynek' : 'Dodano budynek');
  }

  /// Długie przytrzymanie na mapie — wybór, co pobrać w tym miejscu z ULDK.
  Future<void> _onLongPress(LatLng point) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.crop_free),
              title: const Text('Wczytaj działkę tutaj'),
              onTap: () => Navigator.of(context).pop('parcel'),
            ),
            ListTile(
              leading: const Icon(Icons.home_work_outlined),
              title: const Text('Wczytaj budynek tutaj'),
              onTap: () => Navigator.of(context).pop('building'),
            ),
          ],
        ),
      ),
    );
    if (choice == 'parcel') {
      await _fetchParcelAt(point);
    } else if (choice == 'building') {
      await _fetchBuildingAt(point);
    }
  }

  void _fitToPoints(List<LatLng> points) {
    final pts =
        points.where((p) => isValidLatLng(p.latitude, p.longitude)).toList();
    if (pts.isEmpty) return;
    _mapController.fitCamera(
      CameraFit.coordinates(
        coordinates: pts,
        padding: const EdgeInsets.all(48),
      ),
    );
    setState(() => _followPosition = false);
  }

  Future<void> _showBuildingList() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: _buildings.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Brak wczytanych budynków. Przytrzymaj palec na '
                    'mapie i wybierz „Wczytaj budynek tutaj".'),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final b in _buildings)
                    ListTile(
                      leading: const Icon(Icons.home_work_outlined),
                      title: Text('Budynek ${b.id}'),
                      subtitle: Text('${b.points.length} pkt obrysu'),
                      onTap: () {
                        Navigator.of(context).pop();
                        _fitToPoints(b.points);
                      },
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Usuń',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              setState(() =>
                                  _buildings.removeWhere((x) => x.id == b.id));
                              await _buildingStore.save(_buildings);
                              if (context.mounted) Navigator.of(context).pop();
                            },
                          ),
                        ],
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  /// Pierwsza wczytana działka zawierająca wskazany punkt (lub null).
  Parcel? _parcelAt(LatLng point) {
    for (final p in _parcels) {
      if (_hiddenLayers.contains('parcel:${p.id}')) continue; // ukryte nie reagują
      if (isPointInPolygon(point, p.points)) return p;
    }
    return null;
  }

  /// Tapnięcie w mapę: działka → tyczenie; poza działką z włączoną nakładką
  /// uzbrojenia → identyfikacja KIUT w tym punkcie.
  Future<void> _onMapTap(LatLng point) async {
    final parcel = _parcelAt(point);
    if (parcel == null) {
      if (utilitiesOverlayEnabled.value) await _identifyUtilities(point);
      return;
    }
    final start = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tyczenie działki'),
        content: Text('Włączyć tyczenie działki ${parcel.label}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Tycz'),
          ),
        ],
      ),
    );
    if (start == true) _openStakeout(parcel);
  }

  void _openStakeout(Parcel parcel) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StakeoutScreen.forParcel(parcel, _source),
      ),
    );
  }

  Future<void> _fetchParcelAtPosition() async {
    final p = _position;
    if (p == null) {
      _showMessage('Najpierw uruchom pomiar pozycji (Start).');
      return;
    }
    final parcel = await _withBusy(
      () => _uldk.findByPoint(p.longitude, p.latitude),
    );
    if (parcel != null) await _addParcel(parcel);
  }

  Future<void> _searchParcel() async {
    final controller = TextEditingController();
    final query = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Wyszukaj działkę'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'np. Gnojnik 222/1 lub 120205_2.0001.222/1',
          ),
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Szukaj'),
          ),
        ],
      ),
    );
    if (query == null || query.trim().isEmpty) return;

    final results = await _withBusy(() => _uldk.findByIdOrNumber(query));
    if (results == null || results.isEmpty) return;

    Parcel? chosen;
    if (results.length == 1) {
      chosen = results.first;
    } else if (mounted) {
      chosen = await showDialog<Parcel>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text('Znaleziono ${results.length} działek'),
          children: [
            for (final p in results)
              SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop(p),
                child: Text('${p.number} — ${p.region}, gm. ${p.commune}, '
                    'pow. ${p.county}'),
              ),
          ],
        ),
      );
    }
    if (chosen != null) await _addParcel(chosen);
  }

  Future<void> _showParcelList() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: _parcels.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Brak wczytanych działek.'),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final p in _parcels)
                    ListTile(
                      leading: const Icon(Icons.crop_free),
                      title: Text(p.number),
                      subtitle: Text(
                        '${p.region}, gm. ${p.commune}, pow. ${p.county}\n'
                        '${p.id}',
                      ),
                      isThreeLine: true,
                      onTap: () {
                        Navigator.of(context).pop();
                        _fitToParcel(p);
                      },
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Tycz punkty graniczne',
                            icon: const Icon(Icons.flag_outlined),
                            onPressed: () {
                              Navigator.of(context).pop();
                              _openStakeout(p);
                            },
                          ),
                          IconButton(
                            tooltip: 'Usuń',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () {
                              Navigator.of(context).pop();
                              _removeParcel(p);
                            },
                          ),
                        ],
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Future<void> _startUtilityMeasure() async {
    if (_position == null) {
      _showMessage('Najpierw uruchom pomiar pozycji (Start).');
      return;
    }
    final cat = await showDialog<UtilityCategory>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Kategoria punktu'),
        children: [
          for (final c in UtilityCategory.values)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(c),
              child: Row(
                children: [
                  Container(
                    width: 14,
                    height: 14,
                    decoration:
                        BoxDecoration(color: c.color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 10),
                  Text(c.label),
                ],
              ),
            ),
        ],
      ),
    );
    if (cat == null) return;
    setState(() {
      _measuringCategory = cat;
      _averager = PointAverager(
        targetSamples: AppSettings.instance.samples,
        requireFixed: AppSettings.instance.requireFixed,
      );
    });
  }

  void _cancelMeasure() => setState(() {
        _averager = null;
        _measuringCategory = null;
        _measuringLabel = null;
      });

  /// Pomiar ogólnego punktu odniesienia (bez kategorii) — bankuje punkt terenowy
  /// do późniejszego użycia w projektancie geometrii.
  Future<void> _startReferenceMeasure() async {
    if (_position == null) {
      _showMessage('Najpierw uruchom pomiar pozycji (Start).');
      return;
    }
    final controller =
        TextEditingController(text: 'Punkt ${_allMeasured.length + 1}');
    final label = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Zmierz punkt odniesienia'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nazwa punktu'),
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Anuluj')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('Mierz')),
        ],
      ),
    );
    if (label == null) return;
    setState(() {
      _measuringCategory = null;
      _measuringLabel = label.trim().isEmpty ? 'Punkt' : label.trim();
      _averager = PointAverager(
        targetSamples: AppSettings.instance.samples,
        requireFixed: AppSettings.instance.requireFixed,
      );
    });
  }

  Future<void> _finishMeasure({required bool save}) async {
    final result = _averager?.finalize();
    final cat = _measuringCategory;
    final label = _measuringLabel;
    setState(() {
      _averager = null;
      _measuringCategory = null;
      _measuringLabel = null;
    });
    if (!save || result == null) return;
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
      label: cat?.label ?? label ?? 'Punkt',
      category: cat?.code,
    );
    await _measureStore.add(point);
    setState(() {
      _allMeasured = [..._allMeasured, point];
      if (cat != null) _utilityPoints = [..._utilityPoints, point];
    });
    _showMessage('Zapisano: ${point.label} · RMS ${formatDistance(result.rms)} · '
        '${fixLabel(result.worstFix)}');
  }

  Future<void> _showUtilityList() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text('Punkty uzbrojenia (${_utilityPoints.length})'),
              trailing: TextButton.icon(
                onPressed: _utilityPoints.isEmpty
                    ? null
                    : () {
                        Navigator.of(context).pop();
                        _exportUtilityPoints();
                      },
                icon: const Icon(Icons.ios_share),
                label: const Text('Udostępnij'),
              ),
            ),
            const Divider(height: 1),
            if (_utilityPoints.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Brak zmierzonych punktów uzbrojenia.'),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final u in _utilityPoints)
                      ListTile(
                        leading: Icon(Icons.circle,
                            size: 16,
                            color: UtilityCategory.fromCode(u.category)?.color),
                        title: Row(
                          children: [
                            Flexible(child: Text(u.label ?? u.id)),
                            if (u.photoPath != null)
                              const Padding(
                                padding: EdgeInsets.only(left: 6),
                                child: Icon(Icons.photo, size: 14),
                              ),
                          ],
                        ),
                        subtitle: Text(
                          '${u.note?.isNotEmpty == true ? '${u.note}\n' : ''}'
                          'RMS ${formatDistance(u.rms)} · ${fixLabel(u.worstFix)}',
                        ),
                        isThreeLine: u.note?.isNotEmpty == true,
                        onTap: () {
                          Navigator.of(context).pop();
                          _showPointDetail(u);
                        },
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            await _measureStore.remove(u.id);
                            setState(() =>
                                _utilityPoints.removeWhere((x) => x.id == u.id));
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

  Future<void> _exportUtilityPoints() async {
    try {
      await ExportService.sharePoints(_utilityPoints, namePrefix: 'uzbrojenie');
    } catch (e) {
      _showMessage('Eksport nieudany: $e');
    }
  }

  Future<void> _importBoundaryPoints() async {
    const group =
        XTypeGroup(label: 'Punkty PL-2000', extensions: ['csv', 'txt']);
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null) return;
    final pts = parseBoundaryPoints(await file.readAsString());
    if (pts.isEmpty) {
      _showMessage(
          'Nie rozpoznano punktów (format: nr; X; Y; [BPP], PL-2000).');
      return;
    }
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StakeoutScreen(
          targets: [for (final p in pts) p.position],
          labels: [for (final p in pts) p.label],
          pointBpp: [for (final p in pts) p.bpp],
          title: 'Tyczenie — wykaz (${pts.length} pkt)',
          projectId: 'import:${file.name}',
          source: _source,
        ),
      ),
    );
    _showMessage('Wczytano ${pts.length} punktów granicznych.');
  }

  Future<void> _importProject() async {
    const group = XTypeGroup(
      label: 'Projekt / GeoJSON',
      extensions: ['geojson', 'json'],
    );
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null) return;
    try {
      final project = StakeoutProject.fromGeoJson(await file.readAsString());
      if (project.stakePoints.isEmpty) {
        _showMessage('Projekt nie zawiera punktów do tyczenia.');
        return;
      }
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => StakeoutScreen(
            targets: project.stakePoints,
            outline: project.outline,
            title: 'Projekt: ${project.name}',
            projectId: 'project:${project.name}',
            source: _source,
          ),
        ),
      );
    } catch (e) {
      _showMessage('Nie udało się wczytać projektu: $e');
    }
  }

  /// Eksport kopii WSZYSTKICH danych (punkty + projekty + działki + budynki)
  /// do jednego pliku JSON — do przeniesienia na inne urządzenie.
  Future<void> _exportBackup() async {
    try {
      final json = await BackupService().exportJson();
      await ExportService.shareTextFile(json, 'gps_rtk_kopia.json',
          subject: 'Kopia danych GPS RTK');
    } catch (e) {
      _showMessage('Eksport kopii nieudany: ${_shortError(e)}');
    }
  }

  /// Wczytanie kopii z pliku JSON — scala z danymi na urządzeniu (po id).
  Future<void> _importBackup() async {
    const group = XTypeGroup(label: 'Kopia danych', extensions: ['json']);
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null) return;
    try {
      final r = await BackupService().importJson(await file.readAsString());
      final parcels = await _store.load();
      final buildings = await _buildingStore.load();
      final designs = await _designStore.load();
      final all = await _measureStore.loadAll();
      if (!mounted) return;
      setState(() {
        _parcels = parcels;
        _buildings = buildings;
        _designs = designs;
        _allMeasured = all;
        _utilityPoints = all.where((p) => p.category != null).toList();
      });
      _showMessage('Wczytano kopię: ${r.points} pkt · ${r.designs} proj. · '
          '${r.parcels} dz. · ${r.buildings} bud.');
    } catch (e) {
      _showMessage('Nie udało się wczytać kopii: ${_shortError(e)}');
    }
  }

  /// Sprawdza najnowszy release w GitHub i — gdy jest nowszy — proponuje
  /// pobranie APK (Android: przeglądarka → instalator) lub otwarcie strony.
  Future<void> _checkUpdate() async {
    _showMessage('Sprawdzam aktualizacje…');
    UpdateInfo u;
    try {
      u = await UpdateService().check();
    } catch (e) {
      _showMessage('Nie udało się sprawdzić aktualizacji: ${_shortError(e)}');
      return;
    }
    if (!mounted) return;
    final wantUpdate = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(u.updateAvailable
            ? 'Dostępna aktualizacja'
            : 'Masz najnowszą wersję'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Zainstalowana: ${u.currentVersion}'),
              Text('Najnowsza: ${u.latestVersion.isEmpty ? '—' : u.latestVersion}'),
              if (u.notes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(u.notes, style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Zamknij')),
          if (u.updateAvailable)
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(true),
              icon: const Icon(Icons.download),
              label: Text(Platform.isAndroid && u.apkUrl != null
                  ? 'Pobierz i zainstaluj'
                  : (u.apkUrl != null ? 'Pobierz APK' : 'Otwórz release')),
            ),
        ],
      ),
    );
    if (wantUpdate != true || !mounted) return;
    // Android z assetem .apk → pobranie w apce + systemowy instalator (bez
    // przeglądarki). Inne platformy / brak .apk → otwarcie linku.
    if (Platform.isAndroid && u.apkUrl != null) {
      await _downloadAndInstall(u.apkUrl!);
    } else {
      try {
        await launchUrl(Uri.parse(u.apkUrl ?? u.releaseUrl),
            mode: LaunchMode.externalApplication);
      } catch (_) {/* brak przeglądarki — nic nie rób */}
    }
  }

  /// Pobiera APK z [apkUrl] z paskiem postępu i uruchamia systemowy instalator.
  /// Warunek powodzenia: nowy APK podpisany TYM SAMYM kluczem co zainstalowana
  /// wersja (stały debug-keystore w repo) — inaczej Android odmówi instalacji
  /// („package conflicts with an existing package"). Pierwszą wersję z nowym
  /// kluczem trzeba zainstalować raz ręcznie.
  Future<void> _downloadAndInstall(String apkUrl) async {
    final progress = ValueNotifier<double>(0);
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Pobieranie aktualizacji…'),
        content: ValueListenableBuilder<double>(
          valueListenable: progress,
          builder: (context, v, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: v > 0 ? v : null),
              const SizedBox(height: 12),
              Text(v > 0 ? '${(v * 100).toStringAsFixed(0)}%' : 'Łączenie…'),
            ],
          ),
        ),
      ),
    ));
    try {
      final path = await UpdateService()
          .downloadApk(apkUrl, onProgress: (v) => progress.value = v);
      if (!mounted) return;
      Navigator.of(context).pop(); // zamknij dialog postępu
      final res = await OpenFilex.open(
        path,
        type: 'application/vnd.android.package-archive',
      );
      if (res.type != ResultType.done && mounted) {
        _showMessage(
            'Nie udało się otworzyć instalatora (${res.message}). Zezwól '
            'aplikacji na „Instalowanie nieznanych aplikacji" i spróbuj ponownie.');
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // zamknij dialog postępu
        _showMessage('Pobieranie nie powiodło się: ${_shortError(e)}');
      }
    } finally {
      progress.dispose();
    }
  }

  Future<void> _shareManual() async {
    try {
      final bytes = await ManualPdf.build();
      await ExportService.sharePdf(bytes, 'instrukcja_gps_rtk.pdf');
    } catch (e) {
      _showMessage('Nie udało się wygenerować PDF: $e');
    }
  }

  Future<void> _showPointDetail(MeasuredPoint point) => showPointDetailSheet(
        context,
        point,
        _measureStore,
        onUpdated: _refreshUtilityInState,
      );

  void _refreshUtilityInState(MeasuredPoint p) {
    final i = _utilityPoints.indexWhere((x) => x.id == p.id);
    if (i >= 0) setState(() => _utilityPoints[i] = p);
  }

  Future<void> _identifyUtilities(LatLng point) async {
    setState(() => _busy = true);
    String? info;
    String? err;
    try {
      info = await _kiut.identify(point.longitude, point.latitude);
    } catch (e) {
      err = 'Błąd zapytania KIUT: $e';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Uzbrojenie terenu (KIUT)'),
        content: SingleChildScrollView(
          child: Text(err ??
              info ??
              'Brak zmapowanego uzbrojenia w tym punkcie '
                  '(lub brak danych dla tego powiatu).'),
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

  ({double s, double w, double n, double e})? _loadedBounds() {
    if (_parcels.isEmpty) return null;
    double? s, w, n, e;
    for (final parcel in _parcels) {
      for (final pt in parcel.points) {
        s = (s == null || pt.latitude < s) ? pt.latitude : s;
        n = (n == null || pt.latitude > n) ? pt.latitude : n;
        w = (w == null || pt.longitude < w) ? pt.longitude : w;
        e = (e == null || pt.longitude > e) ? pt.longitude : e;
      }
    }
    return (s: s!, w: w!, n: n!, e: e!);
  }

  static String _fmtBytes(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
    return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  static String _shortError(Object e) {
    final s = e.toString().replaceFirst(RegExp(r'^(Exception|FormatException): '), '');
    return s.length > 120 ? '${s.substring(0, 120)}…' : s;
  }

  Future<void> _showOfflineMap() async {
    const minZ = 15, maxZ = 19;
    final bounds = _loadedBounds();
    final est = bounds == null
        ? 0
        : tileCountForBounds(bounds.s, bounds.w, bounds.n, bounds.e, minZ, maxZ);
    var size = await MapCache.sizeBytes();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) {
        var running = false;
        var done = 0, total = est;
        return StatefulBuilder(
          builder: (context, setLocal) {
            Future<void> refreshSize() async {
              final s = await MapCache.sizeBytes();
              if (context.mounted) setLocal(() => size = s);
            }

            Future<void> doPrefetch() async {
              if (bounds == null) return;
              setLocal(() {
                running = true;
                done = 0;
                total = est;
              });
              await MapCache.prefetchArea(
                layer: activeBaseLayer.value,
                south: bounds.s - 0.0006,
                west: bounds.w - 0.0009,
                north: bounds.n + 0.0006,
                east: bounds.e + 0.0009,
                minZoom: minZ,
                maxZoom: maxZ,
                onProgress: (d, t) {
                  if (context.mounted) {
                    setLocal(() {
                      done = d;
                      total = t;
                    });
                  }
                },
              );
              await refreshSize();
              if (context.mounted) setLocal(() => running = false);
            }

            return AlertDialog(
              title: const Text('Mapa offline'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Rozmiar cache: ${_fmtBytes(size)}'),
                  const SizedBox(height: 8),
                  Text('Warstwa: ${activeBaseLayer.value.label}'),
                  const SizedBox(height: 8),
                  if (bounds == null)
                    const Text('Brak wczytanych działek — wczytaj działkę, '
                        'aby pobrać jej okolicę offline.')
                  else
                    Text('Okolica działek, zoom $minZ–$maxZ: ~$est kafelków'),
                  if (running)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Column(
                        children: [
                          LinearProgressIndicator(
                              value: total == 0 ? null : done / total),
                          const SizedBox(height: 4),
                          Text('Pobrano $done / $total'),
                        ],
                      ),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: running
                      ? null
                      : () async {
                          await MapCache.clear();
                          await refreshSize();
                        },
                  child: const Text('Wyczyść'),
                ),
                TextButton(
                  onPressed: running ? null : () => Navigator.of(context).pop(),
                  child: const Text('Zamknij'),
                ),
                FilledButton.icon(
                  onPressed: (running || bounds == null) ? null : doPrefetch,
                  icon: const Icon(Icons.download),
                  label: const Text('Pobierz'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _ntripSettings() async {
    final cfg = _bleSource.ntripConfig;
    final host =
        TextEditingController(text: cfg?.host ?? 'system.asgeupos.pl');
    final port = TextEditingController(text: (cfg?.port ?? 2101).toString());
    final mount = TextEditingController(text: cfg?.mountpoint ?? '');
    final user = TextEditingController(text: cfg?.username ?? '');
    final pass = TextEditingController(text: cfg?.password ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        var loadingMounts = false;
        return StatefulBuilder(
          builder: (context, setLocal) {
            Future<void> pickMountpoint() async {
              final h = host.text.trim();
              if (h.isEmpty) {
                _showMessage('Podaj host castera, aby pobrać listę.');
                return;
              }
              setLocal(() => loadingMounts = true);
              try {
                final list = await fetchSourcetable(
                  h,
                  int.tryParse(port.text) ?? 2101,
                  username: user.text.trim(),
                  password: pass.text,
                );
                if (!context.mounted) return;
                if (list.isEmpty) {
                  _showMessage('Caster nie zwrócił żadnych mountpointów.');
                  return;
                }
                final chosen = await showMountpointPicker(
                  context,
                  list,
                  from: _position == null
                      ? null
                      : LatLng(_position!.latitude, _position!.longitude),
                );
                if (chosen != null) mount.text = chosen;
              } catch (e) {
                _showMessage('Nie udało się pobrać listy: ${_shortError(e)}');
              } finally {
                if (context.mounted) setLocal(() => loadingMounts = false);
              }
            }

            return AlertDialog(
              title: const Text('Ustawienia NTRIP'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                        controller: host,
                        decoration: const InputDecoration(
                            labelText: 'Host castera')),
                    TextField(
                        controller: port,
                        decoration: const InputDecoration(labelText: 'Port'),
                        keyboardType: TextInputType.number),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: TextField(
                              controller: mount,
                              decoration: const InputDecoration(
                                  labelText: 'Mountpoint (VRS)')),
                        ),
                        IconButton(
                          tooltip: 'Pobierz listę mountpointów z castera',
                          onPressed: loadingMounts ? null : pickMountpoint,
                          icon: loadingMounts
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                              : const Icon(Icons.cloud_download_outlined),
                        ),
                      ],
                    ),
                    TextField(
                        controller: user,
                        decoration:
                            const InputDecoration(labelText: 'Użytkownik')),
                    TextField(
                        controller: pass,
                        decoration: const InputDecoration(labelText: 'Hasło'),
                        obscureText: true),
                  ],
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Anuluj')),
                FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Zapisz')),
              ],
            );
          },
        );
      },
    );
    if (saved != true) return;
    final c = NtripConfig(
      host: host.text.trim(),
      port: int.tryParse(port.text) ?? 2101,
      mountpoint: mount.text.trim(),
      username: user.text.trim(),
      password: pass.text,
    );
    await _ntripStore.save(c);
    setState(() => _applyNtrip(c));
    _showMessage('Zapisano NTRIP. Wybierz źródło „Odbiornik RTK" i naciśnij Start.');
  }

  @override
  void dispose() {
    _staleTimer?.cancel();
    _subscription?.cancel();
    _bleStatusSub?.cancel();
    _usbStatusSub?.cancel();
    _serialStatusSub?.cancel();
    _bleTelemetrySub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = _position;
    return Scaffold(
      appBar: AppBar(
        title: const Text('GPS RTK'),
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3),
                child: LinearProgressIndicator(minHeight: 3),
              )
            : null,
        actions: [
          IconButton(
            tooltip: 'Wyszukaj działkę',
            onPressed: _busy ? null : _searchParcel,
            icon: const Icon(Icons.search),
          ),
          IconButton(
            tooltip: 'Działka, na której stoję',
            onPressed: _busy ? null : _fetchParcelAtPosition,
            icon: const Icon(Icons.travel_explore),
          ),
          PopupMenuButton<String>(
            tooltip: 'Więcej',
            icon: const Icon(Icons.more_vert),
            onSelected: (v) {
              if (v == 'parcels') {
                _showParcelList();
              } else if (v == 'utilities') {
                _showUtilityList();
              } else if (v == 'buildings') {
                _showBuildingList();
              } else if (v == 'design') {
                _newDesign();
              } else if (v == 'designs') {
                _showDesignList();
              } else if (v == 'area') {
                Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => AreaScreen(source: _source),
                ));
              } else if (v == 'heights') {
                _openHeights();
              } else if (v == 'building') {
                Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => BuildingLayoutScreen(source: _source),
                ));
              } else if (v == 'visibility') {
                _showVisibility();
              } else if (v == 'boundary') {
                _importBoundaryPoints();
              } else if (v == 'import') {
                _importProject();
              } else if (v == 'backupExport') {
                _exportBackup();
              } else if (v == 'backupImport') {
                _importBackup();
              } else if (v == 'ntrip') {
                _ntripSettings();
              } else if (v == 'nmea') {
                _loadNmeaLog();
              } else if (v == 'settings') {
                _openSettings();
              } else if (v == 'offline') {
                _showOfflineMap();
              } else if (v == 'manual') {
                _shareManual();
              } else if (v == 'update') {
                _checkUpdate();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'design',
                child: ListTile(
                  leading: Icon(Icons.architecture),
                  title: Text('Zaprojektuj geometrię'),
                ),
              ),
              PopupMenuItem(
                value: 'designs',
                child: ListTile(
                  leading: Icon(Icons.dashboard_customize_outlined),
                  title: Text('Projekty geometrii'),
                ),
              ),
              PopupMenuItem(
                value: 'area',
                child: ListTile(
                  leading: Icon(Icons.square_foot),
                  title: Text('Pomiar pola i obwodu'),
                ),
              ),
              PopupMenuItem(
                value: 'heights',
                child: ListTile(
                  leading: Icon(Icons.terrain),
                  title: Text('Wysokości i spadki'),
                ),
              ),
              PopupMenuItem(
                value: 'building',
                child: ListTile(
                  leading: Icon(Icons.foundation),
                  title: Text('Wytyczenie budowli'),
                ),
              ),
              PopupMenuItem(
                value: 'visibility',
                child: ListTile(
                  leading: Icon(Icons.layers_outlined),
                  title: Text('Widoczność warstw'),
                ),
              ),
              PopupMenuItem(
                value: 'parcels',
                child: ListTile(
                  leading: Icon(Icons.format_list_bulleted),
                  title: Text('Wczytane działki'),
                ),
              ),
              PopupMenuItem(
                value: 'utilities',
                child: ListTile(
                  leading: Icon(Icons.account_tree_outlined),
                  title: Text('Punkty uzbrojenia'),
                ),
              ),
              PopupMenuItem(
                value: 'buildings',
                child: ListTile(
                  leading: Icon(Icons.home_work_outlined),
                  title: Text('Budynki'),
                ),
              ),
              PopupMenuItem(
                value: 'boundary',
                child: ListTile(
                  leading: Icon(Icons.flag_circle_outlined),
                  title: Text('Tycz punkty z wykazu (PL-2000)'),
                ),
              ),
              PopupMenuItem(
                value: 'import',
                child: ListTile(
                  leading: Icon(Icons.folder_open),
                  title: Text('Wczytaj projekt'),
                ),
              ),
              PopupMenuItem(
                value: 'backupExport',
                child: ListTile(
                  leading: Icon(Icons.backup_outlined),
                  title: Text('Eksportuj dane (kopia)'),
                ),
              ),
              PopupMenuItem(
                value: 'backupImport',
                child: ListTile(
                  leading: Icon(Icons.restore_page_outlined),
                  title: Text('Wczytaj dane (kopia)'),
                ),
              ),
              PopupMenuItem(
                value: 'ntrip',
                child: ListTile(
                  leading: Icon(Icons.satellite_alt),
                  title: Text('Ustawienia NTRIP'),
                ),
              ),
              PopupMenuItem(
                value: 'nmea',
                child: ListTile(
                  leading: Icon(Icons.route_outlined),
                  title: Text('Wczytaj log NMEA (test)'),
                ),
              ),
              PopupMenuItem(
                value: 'offline',
                child: ListTile(
                  leading: Icon(Icons.download_for_offline),
                  title: Text('Mapa offline'),
                ),
              ),
              PopupMenuItem(
                value: 'settings',
                child: ListTile(
                  leading: Icon(Icons.settings_outlined),
                  title: Text('Ustawienia'),
                ),
              ),
              PopupMenuItem(
                value: 'manual',
                child: ListTile(
                  leading: Icon(Icons.picture_as_pdf),
                  title: Text('Instrukcja (PDF)'),
                ),
              ),
              PopupMenuItem(
                value: 'update',
                child: ListTile(
                  leading: Icon(Icons.system_update),
                  title: Text('Sprawdź aktualizacje'),
                ),
              ),
            ],
          ),
          IconButton(
            tooltip:
                _followPosition ? 'Mapa podąża za pozycją' : 'Mapa zatrzymana',
            onPressed: () =>
                setState(() => _followPosition = !_followPosition),
            icon: Icon(_followPosition ? Icons.gps_fixed : Icons.gps_not_fixed),
          ),
          PopupMenuButton<PositionSource>(
            tooltip: 'Źródło pozycji',
            icon: const Icon(Icons.settings_input_antenna),
            onSelected: (s) => identical(s, _serialSource)
                ? _pickSerialPortThenSwitch()
                : _switchSource(s),
            itemBuilder: (context) => [
              for (final s in _sources)
                PopupMenuItem(
                  value: s,
                  child: Row(
                    children: [
                      Icon(
                        identical(s, _source)
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(s.name),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: (_parcels.isNotEmpty &&
                      _parcels.first.points.isNotEmpty &&
                      isValidLatLng(_parcels.first.points.first.latitude,
                          _parcels.first.points.first.longitude))
                  ? _parcels.first.points.first
                  : const LatLng(49.8964, 20.6156),
              initialZoom: 17,
              maxZoom: 21,
              onTap: (tapPosition, point) => _onMapTap(point),
              onLongPress: (tapPosition, point) => _onLongPress(point),
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
              // Najnowsze ortofoto wysokiej rozdzielczości NA WIERZCHU podkładu
              // GUGiK (przezroczyste tam, gdzie brak nalotu 10 cm).
              const OrtoHighResOverlay(),
              const UtilitiesOverlay(),
              const BuildingsOverlay(),
              if (_buildings.isNotEmpty)
                PolygonLayer(
                  polygons: [
                    for (final b in _buildings)
                      if (!_hiddenLayers.contains('building:${b.id}') &&
                          _allValidLL(b.points))
                        Polygon(
                          points: b.points,
                          color: Colors.brown.withValues(alpha: 0.18),
                          borderColor: Colors.brown,
                          borderStrokeWidth: 1.5,
                        ),
                  ],
                ),
              if (_parcels.isNotEmpty)
                PolygonLayer(
                  polygons: [
                    for (final parcel in _parcels)
                      if (!_hiddenLayers.contains('parcel:${parcel.id}') &&
                          _allValidLL(parcel.points))
                      Polygon(
                        points: parcel.points,
                        color: Colors.teal.withValues(alpha: 0.12),
                        borderColor: Colors.teal,
                        borderStrokeWidth: 2,
                        label: parcel.number,
                        labelStyle: const TextStyle(
                          color: Color(0xFF00504B),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ..._designMapLayers(),
              if (_utilityPoints.isNotEmpty &&
                  !_hiddenLayers.contains('utilities'))
                MarkerLayer(
                  markers: [
                    for (final u in _utilityPoints)
                      if (isValidLatLng(u.latitude, u.longitude))
                      Marker(
                        point: u.latLng,
                        width: 16,
                        height: 16,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: UtilityCategory.fromCode(u.category)?.color ??
                                Colors.grey,
                            shape: BoxShape.circle,
                            border: const Border.fromBorderSide(
                              BorderSide(color: Colors.white, width: 2),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              if (p != null) ...[
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: LatLng(p.latitude, p.longitude),
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
                    Marker(
                      point: LatLng(p.latitude, p.longitude),
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
                title:
                    'Pomiar ${_measuringCategory?.label ?? _measuringLabel ?? ''}…',
                onSave: () => _finishMeasure(save: true),
                onCancel: _cancelMeasure,
              ),
            ),
          // Dół ekranu: FAB-y NAD kartą statusu (nie zasłaniają jej). Całość w
          // jednej kolumnie kotwiczonej do dołu; puste miejsce po lewej od
          // FAB-ów przepuszcza dotyk do mapy.
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
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (_isRunning && _averager == null) ...[
                        FloatingActionButton.small(
                          heroTag: 'measureRef',
                          tooltip: 'Zmierz punkt (odniesienie / do projektu)',
                          onPressed: _startReferenceMeasure,
                          child: const Icon(Icons.my_location),
                        ),
                        const SizedBox(height: 10),
                        FloatingActionButton.small(
                          heroTag: 'measure',
                          tooltip: 'Zmierz punkt uzbrojenia',
                          onPressed: _startUtilityMeasure,
                          child: const Icon(Icons.add_location_alt),
                        ),
                        const SizedBox(height: 10),
                      ],
                      FloatingActionButton.extended(
                        heroTag: 'startstop',
                        onPressed: _isRunning ? _stop : _start,
                        icon: Icon(_isRunning ? Icons.stop : Icons.play_arrow),
                        label: Text(_isRunning ? 'Stop' : 'Start'),
                      ),
                    ],
                  ),
                ),
                // Karta statusu — pełna szerokość, nad paskiem nawigacji.
                Padding(
                  padding: EdgeInsets.fromLTRB(
                      12, 0, 12, 12 + MediaQuery.viewPaddingOf(context).bottom),
                  child: _StatusCard(
                    source: _source,
                    position: p,
                    error: _error,
                    isRunning: _isRunning,
                    staleSeconds: _staleSeconds,
                    telemetry:
                        identical(_source, _bleSource) ? _telemetry : null,
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

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.source,
    required this.position,
    required this.error,
    required this.isRunning,
    this.staleSeconds,
    this.telemetry,
  });

  final PositionSource source;
  final RtkPosition? position;
  final String? error;
  final bool isRunning;

  /// Sekundy od ostatniej pozycji, gdy strumień „zamarł" (null = dane świeże).
  /// Ostatni znany fix jest wtedy nieaktualny — nie pokazujemy go jako żywego.
  final int? staleSeconds;
  final DeviceTelemetry? telemetry;

  static const _fixLabels = {
    FixType.none: 'Brak pozycji',
    FixType.gps: 'GPS',
    FixType.dgps: 'DGPS',
    FixType.rtkFloat: 'RTK Float',
    FixType.rtkFixed: 'RTK Fixed',
  };

  static const _fixColors = {
    FixType.none: Colors.grey,
    FixType.gps: Colors.orange,
    FixType.dgps: Colors.amber,
    FixType.rtkFloat: Colors.lightBlue,
    FixType.rtkFixed: Colors.green,
  };

  @override
  Widget build(BuildContext context) {
    final p = position;
    final stale = staleSeconds != null;
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Chip(
                  label: Text(
                    p == null
                        ? 'Brak pozycji'
                        : stale
                            ? 'Brak danych'
                            : _fixLabels[p.fixType]!,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  backgroundColor:
                      p == null || stale ? Colors.grey : _fixColors[p.fixType],
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    source.name + (isRunning ? '' : ' — zatrzymano'),
                    style: Theme.of(context).textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              )
            else if (p == null)
              Text(
                isRunning
                    ? 'Czekam na pozycję ze źródła „${source.name}"…'
                    : 'Naciśnij Start, aby rozpocząć pomiar. Przytrzymaj palec '
                        'na mapie, aby pobrać obrys działki w tym miejscu.',
              )
            else ...[
              Text(
                '${p.latitude.toStringAsFixed(7)}°N  '
                '${p.longitude.toStringAsFixed(7)}°E',
                style: const TextStyle(
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                'Dokładność: ±${p.accuracy.toStringAsFixed(1)} m'
                '${p.altitude != null ? '   wys.: ${p.altitude!.toStringAsFixed(1)} m' : ''}'
                '${p.satellites != null ? '   sat.: ${p.satellites}' : ''}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (stale)
                Text(
                  'Brak nowych pozycji od $staleSeconds s — sprawdź połączenie '
                  'z odbiornikiem (Stop i Start łączy ponownie).',
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
            if (telemetry != null && error == null) ...[
              const SizedBox(height: 6),
              _TelemetryRow(telemetry: telemetry!),
            ],
          ],
        ),
      ),
    );
  }
}

/// Pasek telemetrii odbiornika (bateria, przepływ RTCM, wiek poprawek) z char.
/// „status" `6E400004`. Wiek poprawek koloruje się: zielony < 10 s, pomarańczowy
/// 10–30 s, czerwony > 30 s (powyżej ~30 s RTK spada z Fixed do Float).
class _TelemetryRow extends StatelessWidget {
  const _TelemetryRow({required this.telemetry});

  final DeviceTelemetry telemetry;

  @override
  Widget build(BuildContext context) {
    final t = telemetry;
    final style = Theme.of(context).textTheme.bodySmall;
    final age = t.correctionAgeS;
    final ageColor = age == null
        ? Colors.grey
        : age > 30
            ? Colors.red
            : age > 10
                ? Colors.orange
                : Colors.green;
    return Wrap(
      spacing: 14,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (t.hasBattery)
          _item(Icons.battery_full, '${t.batteryPct ?? '?'}%', style),
        _item(
          Icons.sync,
          t.rtcmFlowing ? 'RTCM ${t.rtcmBps} B/s' : 'RTCM brak',
          style,
          color: t.rtcmFlowing ? Colors.green : Colors.grey,
        ),
        if (age != null)
          _item(Icons.schedule, 'wiek ${age.toStringAsFixed(1)} s', style,
              color: ageColor),
      ],
    );
  }

  Widget _item(IconData icon, String text, TextStyle? style, {Color? color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 3),
        Text(text, style: style?.copyWith(color: color)),
      ],
    );
  }
}
