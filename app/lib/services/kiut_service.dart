import 'package:http/http.dart' as http;

import '../map/tile_math.dart';

/// Klient KIUT (Krajowa Integracja Uzbrojenia Terenu, GUGiK).
/// WMS udostępnia podgląd sieci (warstwy w base_layers); GetFeatureInfo
/// zwraca atrybuty uzbrojenia w wskazanym punkcie. Pełnej geometrii (wektora)
/// nie da się pobrać publicznie — to wyłącznie odczyt.
class KiutService {
  static const _base =
      'https://integracja.gugik.gov.pl/cgi-bin/KrajowaIntegracjaUzbrojeniaTerenu';
  static const _layers = 'przewod_wodociagowy,przewod_kanalizacyjny,'
      'przewod_gazowy,przewod_elektroenergetyczny';

  final http.Client _client;
  KiutService([http.Client? client]) : _client = client ?? http.Client();

  /// URL GetFeatureInfo dla punktu (WGS84). Wydzielone, by przetestować skład.
  static Uri featureInfoUrl(double lon, double lat, {double halfMeters = 4}) {
    final m = lonLatToMercator(lon, lat);
    final bbox = '${m.x - halfMeters},${m.y - halfMeters},'
        '${m.x + halfMeters},${m.y + halfMeters}';
    return Uri.parse(_base).replace(queryParameters: {
      'SERVICE': 'WMS',
      'VERSION': '1.1.1',
      'REQUEST': 'GetFeatureInfo',
      'LAYERS': _layers,
      'QUERY_LAYERS': _layers,
      'SRS': 'EPSG:3857',
      'BBOX': bbox,
      'WIDTH': '5',
      'HEIGHT': '5',
      'X': '2',
      'Y': '2',
      'INFO_FORMAT': 'text/html',
    });
  }

  /// Oczyszczone atrybuty uzbrojenia w punkcie, lub null gdy brak danych.
  Future<String?> identify(double lon, double lat) async {
    final resp = await _client
        .get(featureInfoUrl(lon, lat))
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) return null;
    final text = stripHtml(resp.body);
    return text.isEmpty ? null : text;
  }

  /// Usuwa znaczniki HTML i normalizuje białe znaki (prosty podgląd atrybutów).
  static String stripHtml(String html) {
    final noTags = html.replaceAll(RegExp(r'<[^>]*>'), ' ');
    final unescaped = noTags
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>');
    return unescaped.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
