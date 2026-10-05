import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/parcel.dart';
import 'prefs_json.dart';

/// Lokalny magazyn wczytanych działek — dostępne offline po pobraniu.
class ParcelStore {
  static const _key = 'parcels.v1';

  Future<List<Parcel>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return readJsonListPref(prefs, _key, Parcel.fromJson);
  }

  Future<void> save(List<Parcel> parcels) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode([for (final p in parcels) p.toJson()]),
    );
  }
}
