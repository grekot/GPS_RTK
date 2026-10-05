import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../rtk/ntrip_client.dart';
import 'prefs_json.dart';

/// Trwałe ustawienia NTRIP (caster ASG-EUPOS itp.).
class NtripStore {
  static const _key = 'ntrip.v1';

  Future<NtripConfig?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final j = await readJsonPref(prefs, _key);
    return j is Map<String, dynamic> ? NtripConfig.fromJson(j) : null;
  }

  Future<void> save(NtripConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(config.toJson()));
  }
}
