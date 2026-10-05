import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/measured_point.dart';
import '../utils/geo.dart';

/// Trwały magazyn zmierzonych punktów (wspólny dla wszystkich działek).
///
/// Każda zmiana to odczyt → modyfikacja → zapis całej listy. Instancji jest
/// kilka (ekran główny, tyczenie, kopia zapasowa), a działają na tym samym
/// kluczu, więc zmiany idą przez **wspólną kolejkę** ([_lock]) — inaczej dwa
/// równoczesne zapisy (np. pomiar w tyczeniu + import kopii) gubiły punkt.
class MeasuredPointStore {
  static const _key = 'measured_points.v1';

  /// Kopia nieczytelnych danych — żeby kolejny zapis ich nie nadpisał.
  static const corruptKey = '$_key.corrupt';

  static Future<void> _lock = Future.value();

  /// Wykonuje [action] po zakończeniu wszystkich wcześniejszych zmian.
  static Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _lock.then((_) => action());
    _lock = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<List<MeasuredPoint>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      // Uszkodzony zapis: odłóż kopię (do ręcznego odzyskania) i zacznij od
      // pustej listy, zamiast wywracać start aplikacji.
      await prefs.setString(corruptKey, raw);
      await prefs.remove(_key);
      return [];
    }
    if (decoded is! List) return [];
    final out = <MeasuredPoint>[];
    for (final item in decoded) {
      try {
        final p = MeasuredPoint.fromJson(item as Map<String, dynamic>);
        // Odfiltruj punkty z przekłamaną współrzędną (np. zapisane podczas
        // wcześniejszej usterki) — chroni mapę i CameraFit przed asercją.
        if (isValidLatLng(p.latitude, p.longitude)) out.add(p);
      } catch (_) {/* pojedynczy uszkodzony rekord — pomiń */}
    }
    return out;
  }

  Future<List<MeasuredPoint>> loadForParcel(String parcelId) async {
    final all = await loadAll();
    return all.where((p) => p.parcelId == parcelId).toList();
  }

  Future<void> add(MeasuredPoint point) => _serialized(() async {
        final all = await loadAll()..add(point);
        await _save(all);
      });

  Future<void> remove(String id) => _serialized(() async {
        final all = await loadAll()..removeWhere((p) => p.id == id);
        await _save(all);
      });

  /// Zastępuje punkt o tym samym id (np. po dodaniu notatki/zdjęcia).
  Future<void> update(MeasuredPoint point) => updateAll([point]);

  /// Scala wiele punktów po `id` jednym zapisem (import kopii zapasowej).
  Future<void> updateAll(List<MeasuredPoint> points) => _serialized(() async {
        final all = await loadAll();
        for (final point in points) {
          final i = all.indexWhere((p) => p.id == point.id);
          if (i >= 0) {
            all[i] = point;
          } else {
            all.add(point);
          }
        }
        await _save(all);
      });

  Future<void> _save(List<MeasuredPoint> points) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode([for (final p in points) p.toJson()]),
    );
  }
}
