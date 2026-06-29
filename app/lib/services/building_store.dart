import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/building.dart';

/// Trwały magazyn wczytanych obrysów budynków (dostępne offline po pobraniu).
class BuildingStore {
  static const _key = 'buildings.v1';

  Future<List<Building>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return [
      for (final item in list) Building.fromJson(item as Map<String, dynamic>),
    ];
  }

  Future<void> save(List<Building> buildings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode([for (final b in buildings) b.toJson()]),
    );
  }
}
