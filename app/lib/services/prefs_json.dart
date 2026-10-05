import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Odczyt JSON z SharedPreferences odporny na uszkodzony zapis.
///
/// Nieczytelna wartość jest odkładana pod `<klucz>.corrupt` (do ręcznego
/// odzyskania) i usuwana — aplikacja startuje z wartościami domyślnymi
/// zamiast wywracać się przy każdym uruchomieniu, a kolejny zapis nie
/// nadpisuje jedynej kopii danych.
Future<Object?> readJsonPref(SharedPreferences prefs, String key) async {
  final raw = prefs.getString(key);
  if (raw == null) return null;
  try {
    return jsonDecode(raw);
  } on FormatException {
    await prefs.setString('$key.corrupt', raw);
    await prefs.remove(key);
    return null;
  }
}

/// Lista obiektów z [key]; uszkodzone pojedyncze rekordy są pomijane.
Future<List<T>> readJsonListPref<T>(
  SharedPreferences prefs,
  String key,
  T Function(Map<String, dynamic>) fromJson,
) async {
  final decoded = await readJsonPref(prefs, key);
  if (decoded is! List) return [];
  final out = <T>[];
  for (final item in decoded) {
    if (item is! Map<String, dynamic>) continue;
    try {
      out.add(fromJson(item));
    } catch (_) {/* pojedynczy rekord nie do odczytu — pomiń */}
  }
  return out;
}
