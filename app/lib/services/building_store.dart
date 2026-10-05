import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/building.dart';
import 'prefs_json.dart';

/// Trwały magazyn wczytanych obrysów budynków (dostępne offline po pobraniu).
class BuildingStore {
  static const _key = 'buildings.v1';

  Future<List<Building>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return readJsonListPref(prefs, _key, Building.fromJson);
  }

  Future<void> save(List<Building> buildings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode([for (final b in buildings) b.toJson()]),
    );
  }
}
