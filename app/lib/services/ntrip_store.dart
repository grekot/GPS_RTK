import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../rtk/ntrip_client.dart';

/// Trwałe ustawienia NTRIP (caster ASG-EUPOS itp.).
class NtripStore {
  static const _key = 'ntrip.v1';

  Future<NtripConfig?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    return NtripConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> save(NtripConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(config.toJson()));
  }
}
