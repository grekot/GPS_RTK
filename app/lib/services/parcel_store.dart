import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/parcel.dart';

/// Lokalny magazyn wczytanych działek — dostępne offline po pobraniu.
class ParcelStore {
  static const _key = 'parcels.v1';

  Future<List<Parcel>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return [
      for (final item in list) Parcel.fromJson(item as Map<String, dynamic>),
    ];
  }

  Future<void> save(List<Parcel> parcels) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode([for (final p in parcels) p.toJson()]),
    );
  }
}
