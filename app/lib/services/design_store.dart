import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/design.dart';

/// Trwałość nazwanych projektów geometrii (lista [Design] w SharedPreferences).
class DesignStore {
  static const _key = 'designs.v1';

  Future<List<Design>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return [
      for (final d in list) Design.fromJson(d as Map<String, dynamic>),
    ];
  }

  Future<void> saveAll(List<Design> designs) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode([for (final d in designs) d.toJson()]),
    );
  }

  /// Wstawia lub aktualizuje pojedynczy projekt (po id) i zapisuje całość.
  Future<List<Design>> saveOne(Design design) async {
    final all = await load();
    final i = all.indexWhere((d) => d.id == design.id);
    if (i >= 0) {
      all[i] = design;
    } else {
      all.add(design);
    }
    await saveAll(all);
    return all;
  }

  Future<List<Design>> delete(String id) async {
    final all = await load();
    all.removeWhere((d) => d.id == id);
    await saveAll(all);
    return all;
  }
}
