import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// Wynik sprawdzenia aktualizacji w GitHub Releases.
class UpdateInfo {
  const UpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.notes,
    required this.releaseUrl,
    required this.updateAvailable,
    this.apkUrl,
  });

  final String currentVersion; // wersja zainstalowana (pubspec)
  final String latestVersion; // tag najnowszego release (np. „v1.1.0")
  final String notes; // treść release (changelog)
  final String releaseUrl; // strona release (fallback do otwarcia)
  final String? apkUrl; // bezpośredni link do .apk z assetów (jeśli jest)
  final bool updateAvailable;
}

/// Sprawdza najnowszy release w repo GitHub i porównuje z wersją apki.
/// Publiczne repo — bez tokena (limit 60 zapytań/h wystarcza).
class UpdateService {
  UpdateService({this.owner = 'grekot', this.repo = 'GPS_RTK', http.Client? client})
      : _client = client ?? http.Client();

  final String owner;
  final String repo;
  final http.Client _client;

  Future<UpdateInfo> check() async {
    final info = await PackageInfo.fromPlatform();
    final current = info.version;
    final resp = await _client.get(
      Uri.parse('https://api.github.com/repos/$owner/$repo/releases/latest'),
      headers: {'Accept': 'application/vnd.github+json'},
    );
    if (resp.statusCode == 404) {
      throw StateError('Brak opublikowanych release w $owner/$repo.');
    }
    if (resp.statusCode != 200) {
      throw StateError('GitHub odpowiedział HTTP ${resp.statusCode}.');
    }
    final j = jsonDecode(resp.body) as Map<String, dynamic>;
    final parsed = parseRelease(j);
    return UpdateInfo(
      currentVersion: current,
      latestVersion: parsed.tag,
      notes: parsed.notes,
      releaseUrl: parsed.releaseUrl.isEmpty
          ? 'https://github.com/$owner/$repo/releases'
          : parsed.releaseUrl,
      apkUrl: parsed.apkUrl,
      updateAvailable: isNewer(parsed.tag, current),
    );
  }

  /// Pobiera APK spod [url] do pliku w katalogu tymczasowym aplikacji i raportuje
  /// postęp przez [onProgress] (0..1). Zwraca ścieżkę pobranego pliku. `http` sam
  /// podąża za przekierowaniami GitHuba (browser_download_url → release-assets…),
  /// więc nie trzeba ich obsługiwać ręcznie (jak na bardzo starym Androidzie).
  /// Rzuca [StateError] przy nie-200 i wyjątki sieciowe/IO przy błędach.
  Future<String> downloadApk(String url, {void Function(double)? onProgress}) async {
    final req = http.Request('GET', Uri.parse(url))
      ..followRedirects = true
      ..headers['Accept'] = 'application/octet-stream'
      ..headers['User-Agent'] = 'gps_rtk_app';
    final resp = await _client.send(req);
    if (resp.statusCode != 200) {
      throw StateError('Pobieranie nie powiodło się (HTTP ${resp.statusCode}).');
    }
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/gps_rtk_update.apk');
    final total = resp.contentLength ?? 0;
    var received = 0;
    final sink = file.openWrite();
    try {
      await for (final chunk in resp.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
      }
    } finally {
      await sink.close();
    }
    return file.path;
  }

  /// Wyłuskuje z JSON-a release: tag, notatki, link strony i link do .apk
  /// (pierwszy asset kończący się na „.apk"). Czyste — testowalne bez sieci.
  static ({String tag, String notes, String releaseUrl, String? apkUrl})
      parseRelease(Map<String, dynamic> j) {
    String? apkUrl;
    for (final a in (j['assets'] as List? ?? const [])) {
      final m = a as Map<String, dynamic>;
      if ((m['name'] as String? ?? '').toLowerCase().endsWith('.apk')) {
        apkUrl = m['browser_download_url'] as String?;
        break;
      }
    }
    return (
      tag: (j['tag_name'] as String? ?? '').trim(),
      notes: (j['body'] as String? ?? '').trim(),
      releaseUrl: (j['html_url'] as String? ?? '').trim(),
      apkUrl: apkUrl,
    );
  }

  /// Czy [latest] (np. „v1.2.0" / „1.2.0") jest nowsza niż [current] („1.1.0").
  /// Porównanie numeryczne po segmentach; brakujące segmenty traktujemy jak 0;
  /// sufiks build (+N / -beta) jest pomijany. Pusty tag → nie ma aktualizacji.
  static bool isNewer(String latest, String current) {
    if (latest.trim().isEmpty) return false;
    List<int> parse(String s) {
      final core = s
          .trim()
          .replaceFirst(RegExp(r'^[vV]'), '')
          .split(RegExp(r'[+\-\s]'))
          .first;
      return core.split('.').map((x) => int.tryParse(x.trim()) ?? 0).toList();
    }

    final a = parse(latest), b = parse(current);
    final n = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < n; i++) {
      final ai = i < a.length ? a[i] : 0;
      final bi = i < b.length ? b[i] : 0;
      if (ai != bi) return ai > bi;
    }
    return false;
  }
}
