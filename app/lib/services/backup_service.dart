import 'dart:convert';

import '../models/building.dart';
import '../models/design.dart';
import '../models/measured_point.dart';
import '../models/parcel.dart';
import 'building_store.dart';
import 'design_store.dart';
import 'measured_point_store.dart';
import 'parcel_store.dart';

/// Kopia / transfer wszystkich danych roboczych między urządzeniami
/// (telefon ↔ Windows): zmierzone punkty, projekty geometrii, działki i budynki
/// — w jednym pliku JSON. Działki/budynki są w kopii celowo: projekty geometrii
/// odnoszą się do nich po `id`, więc bez nich nie policzą się na drugim
/// urządzeniu. Import **scala po `id`** (nadpisuje to samo id, dokłada nowe),
/// więc nie kasuje danych na urządzeniu docelowym. Ten sam bundle jest podstawą
/// synchronizacji przez GitHub.
class BackupService {
  BackupService({
    MeasuredPointStore? measure,
    DesignStore? designs,
    ParcelStore? parcels,
    BuildingStore? buildings,
  })  : _measure = measure ?? MeasuredPointStore(),
        _designs = designs ?? DesignStore(),
        _parcels = parcels ?? ParcelStore(),
        _buildings = buildings ?? BuildingStore();

  final MeasuredPointStore _measure;
  final DesignStore _designs;
  final ParcelStore _parcels;
  final BuildingStore _buildings;

  static const formatVersion = 1;

  /// Serializuje całość danych z magazynów do czytelnego JSON.
  Future<String> exportJson() async {
    return const JsonEncoder.withIndent('  ').convert(toBundle(
      points: await _measure.loadAll(),
      designs: await _designs.load(),
      parcels: await _parcels.load(),
      buildings: await _buildings.load(),
    ));
  }

  /// Czysta funkcja budująca mapę kopii (testowalna bez magazynów).
  static Map<String, dynamic> toBundle({
    required List<MeasuredPoint> points,
    required List<Design> designs,
    required List<Parcel> parcels,
    required List<Building> buildings,
  }) =>
      {
        'app': 'gps_rtk',
        'version': formatVersion,
        'points': [for (final p in points) p.toJson()],
        'designs': [for (final d in designs) d.toJson()],
        'parcels': [for (final p in parcels) p.toJson()],
        'buildings': [for (final b in buildings) b.toJson()],
      };

  /// Parsuje kopię na listy obiektów (czysta, testowalna). Rzuca
  /// [FormatException], gdy to nie jest plik kopii GPS RTK.
  static ({
    List<MeasuredPoint> points,
    List<Design> designs,
    List<Parcel> parcels,
    List<Building> buildings,
  }) parseBundle(String raw) {
    final j = jsonDecode(raw);
    if (j is! Map<String, dynamic> || j['app'] != 'gps_rtk') {
      throw const FormatException('To nie jest plik kopii GPS RTK.');
    }
    List<T> list<T>(String key, T Function(Map<String, dynamic>) f) => [
          for (final x in (j[key] as List? ?? const []))
            f(x as Map<String, dynamic>),
        ];
    return (
      points: list('points', MeasuredPoint.fromJson),
      designs: list('designs', Design.fromJson),
      parcels: list('parcels', Parcel.fromJson),
      buildings: list('buildings', Building.fromJson),
    );
  }

  /// Wczytuje kopię i **scala** z danymi na urządzeniu (po `id`). Zwraca liczby
  /// wczytanych rekordów per kategoria.
  Future<({int points, int designs, int parcels, int buildings})> importJson(
      String raw) async {
    final b = parseBundle(raw);
    for (final p in b.points) {
      await _measure.update(p); // update = nadpisz po id / dodaj
    }
    for (final d in b.designs) {
      await _designs.saveOne(d);
    }
    final parcels = await _parcels.load();
    _mergeById(parcels, b.parcels, (x) => x.id);
    await _parcels.save(parcels);
    final buildings = await _buildings.load();
    _mergeById(buildings, b.buildings, (x) => x.id);
    await _buildings.save(buildings);
    return (
      points: b.points.length,
      designs: b.designs.length,
      parcels: b.parcels.length,
      buildings: b.buildings.length,
    );
  }

  static void _mergeById<T>(
      List<T> into, List<T> incoming, String Function(T) id) {
    for (final item in incoming) {
      final i = into.indexWhere((x) => id(x) == id(item));
      if (i >= 0) {
        into[i] = item;
      } else {
        into.add(item);
      }
    }
  }
}
