import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/measured_point.dart';
import '../utils/geo.dart';

/// Trwały magazyn zmierzonych punktów (wspólny dla wszystkich działek).
class MeasuredPointStore {
  static const _key = 'measured_points.v1';

  Future<List<MeasuredPoint>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return [
      for (final item in list)
        MeasuredPoint.fromJson(item as Map<String, dynamic>),
    ]
        // Odfiltruj punkty z przekłamaną współrzędną (np. zapisane podczas
        // wcześniejszej usterki) — chroni mapę i CameraFit przed asercją.
        .where((p) => isValidLatLng(p.latitude, p.longitude))
        .toList();
  }

  Future<List<MeasuredPoint>> loadForParcel(String parcelId) async {
    final all = await loadAll();
    return all.where((p) => p.parcelId == parcelId).toList();
  }

  Future<void> add(MeasuredPoint point) async {
    final all = await loadAll()..add(point);
    await _save(all);
  }

  Future<void> remove(String id) async {
    final all = await loadAll()..removeWhere((p) => p.id == id);
    await _save(all);
  }

  /// Zastępuje punkt o tym samym id (np. po dodaniu notatki/zdjęcia).
  Future<void> update(MeasuredPoint point) async {
    final all = await loadAll();
    final i = all.indexWhere((p) => p.id == point.id);
    if (i >= 0) {
      all[i] = point;
    } else {
      all.add(point);
    }
    await _save(all);
  }

  Future<void> _save(List<MeasuredPoint> points) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode([for (final p in points) p.toJson()]),
    );
  }
}
