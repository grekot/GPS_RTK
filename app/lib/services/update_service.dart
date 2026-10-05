import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
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
    this.apkSha256,
  });

  final String currentVersion; // wersja zainstalowana (pubspec)
  final String latestVersion; // tag najnowszego release (np. „v1.1.0")
  final String notes; // treść release (changelog)
  final String releaseUrl; // strona release (fallback do otwarcia)
  final String? apkUrl; // bezpośredni link do .apk z assetów (jeśli jest)
  final String? apkSha256; // skrót z API GitHub (pole `digest`), hex
  final bool updateAvailable;
}

/// Pobieranie przerwane przyciskiem „Anuluj".
class UpdateCancelled implements Exception {
  const UpdateCancelled();
  @override
  String toString() => 'Anulowano pobieranie.';
}

/// Uchwyt anulowania trwającego pobierania ([UpdateService.downloadApk]).
class UpdateCancelToken {
  final _completer = Completer<void>();
  bool get isCancelled => _completer.isCompleted;
  Future<void> get whenCancelled => _completer.future;
  void cancel() {
    if (!_completer.isCompleted) _completer.complete();
  }
}

/// Czy z [url] wolno pobrać aktualizację: tylko HTTPS z GitHuba (strona
/// release i jego serwery plików). Chroni przed podsunięciem obcego linku,
/// gdyby odpowiedź API została zmanipulowana.
bool isTrustedDownloadUrl(String? url) {
  final u = url == null ? null : Uri.tryParse(url);
  if (u == null || u.scheme != 'https') return false;
  final h = u.host.toLowerCase();
  return h == 'github.com' ||
      h.endsWith('.github.com') ||
      h.endsWith('.githubusercontent.com');
}

/// Sprawdza najnowszy release w repo GitHub i porównuje z wersją apki.
/// Publiczne repo — bez tokena (limit 60 zapytań/h wystarcza).
class UpdateService {
  UpdateService({
    this.owner = 'grekot',
    this.repo = 'GPS_RTK',
    http.Client? client,
    Future<Directory> Function()? tempDir,
    this.requestTimeout = const Duration(seconds: 20),
    this.stallTimeout = const Duration(seconds: 30),
    this.maxApkBytes = 400 * 1024 * 1024,
  })  : _client = client ?? http.Client(),
        _tempDir = tempDir ?? getTemporaryDirectory;

  final String owner;
  final String repo;
  final http.Client _client;
  final Future<Directory> Function() _tempDir;

  /// Limit na odpowiedź serwera (sprawdzenie, nagłówki pobierania).
  final Duration requestTimeout;

  /// Ile może trwać przerwa w napływie danych, zanim uznamy łącze za martwe.
  final Duration stallTimeout;

  /// Górna granica rozmiaru pliku (ochrona przed zapchaniem pamięci).
  final int maxApkBytes;

  Future<UpdateInfo> check() async {
    final info = await PackageInfo.fromPlatform();
    final current = info.version;
    final resp = await _client.get(
      Uri.parse('https://api.github.com/repos/$owner/$repo/releases/latest'),
      headers: {'Accept': 'application/vnd.github+json'},
    ).timeout(requestTimeout);
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
      apkSha256: parsed.apkSha256,
      updateAvailable: isNewer(parsed.tag, current),
    );
  }

  /// Pobiera APK spod [url] do katalogu tymczasowego aplikacji i raportuje
  /// postęp przez [onProgress] (0..1). Zwraca ścieżkę pliku. `http` sam
  /// podąża za przekierowaniami GitHuba (browser_download_url → serwer plików).
  ///
  /// Zabezpieczenia: tylko zaufany HTTPS ([isTrustedDownloadUrl]), limit czasu
  /// na odpowiedź i na przerwę w danych, limit rozmiaru, anulowanie przez
  /// [cancel]. Gdy znany jest [expectedSha256], plik o innym skrócie jest
  /// usuwany i zgłaszany jako błąd — instalator nie dostanie podmienionego APK.
  Future<String> downloadApk(
    String url, {
    void Function(double)? onProgress,
    String? expectedSha256,
    UpdateCancelToken? cancel,
  }) async {
    if (!isTrustedDownloadUrl(url)) {
      throw StateError('Odrzucono link pobierania spoza GitHub: $url');
    }
    final req = http.Request('GET', Uri.parse(url))
      ..followRedirects = true
      ..headers['Accept'] = 'application/octet-stream'
      ..headers['User-Agent'] = 'gps_rtk_app';
    final cancelled = cancel?.whenCancelled
        .then<http.StreamedResponse>((_) => throw const UpdateCancelled());
    cancelled?.ignore(); // błąd „anulowano" po udanym starcie nikogo nie obchodzi
    final send = _client.send(req).timeout(requestTimeout);
    final resp = await (cancelled == null
        ? send
        : Future.any<http.StreamedResponse>([send, cancelled]));
    if (resp.statusCode != 200) {
      throw StateError('Pobieranie nie powiodło się (HTTP ${resp.statusCode}).');
    }
    final total = resp.contentLength ?? 0;
    if (total > maxApkBytes) {
      throw StateError('Plik aktualizacji jest podejrzanie duży ($total B).');
    }
    final dir = await _tempDir();
    final file = File('${dir.path}/gps_rtk_update.apk');
    final sink = file.openWrite();
    final digestOut = _DigestSink();
    final hasher = sha256.startChunkedConversion(digestOut);
    var received = 0;
    final done = Completer<void>();
    late final StreamSubscription<List<int>> sub;
    sub = resp.stream.timeout(stallTimeout).listen(
      (chunk) {
        received += chunk.length;
        if (received > maxApkBytes) {
          sub.cancel();
          if (!done.isCompleted) {
            done.completeError(
                StateError('Plik aktualizacji przekracza limit rozmiaru.'));
          }
          return;
        }
        sink.add(chunk);
        hasher.add(chunk);
        if (total > 0) onProgress?.call(received / total);
      },
      onError: (Object e) {
        sub.cancel();
        if (!done.isCompleted) {
          done.completeError(e is TimeoutException
              ? StateError('Łącze przestało przesyłać dane.')
              : e);
        }
      },
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
      cancelOnError: true,
    );
    unawaited(cancel?.whenCancelled.then((_) {
      sub.cancel();
      if (!done.isCompleted) done.completeError(const UpdateCancelled());
    }));
    try {
      await done.future;
    } catch (_) {
      await sink.close();
      await _deleteQuietly(file);
      rethrow;
    }
    await sink.close();
    hasher.close();
    final actual = digestOut.value?.toString();
    if (expectedSha256 != null &&
        actual != expectedSha256.toLowerCase()) {
      await _deleteQuietly(file);
      throw StateError('Suma kontrolna pobranego APK się nie zgadza — '
          'plik odrzucony. Spróbuj ponownie.');
    }
    return file.path;
  }

  static Future<void> _deleteQuietly(File f) async {
    try {
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  /// Wyłuskuje z JSON-a release: tag, notatki, link strony, link do .apk
  /// (pierwszy asset kończący się na „.apk", tylko zaufany HTTPS) i jego
  /// SHA-256 z pola `digest` (`sha256:HEX`). Czyste — testowalne bez sieci.
  static ({
    String tag,
    String notes,
    String releaseUrl,
    String? apkUrl,
    String? apkSha256,
  }) parseRelease(Map<String, dynamic> j) {
    String? apkUrl;
    String? sha;
    for (final a in (j['assets'] as List? ?? const [])) {
      final m = a as Map<String, dynamic>;
      if ((m['name'] as String? ?? '').toLowerCase().endsWith('.apk')) {
        final url = m['browser_download_url'] as String?;
        if (!isTrustedDownloadUrl(url)) continue;
        apkUrl = url;
        final d = (m['digest'] as String? ?? '').trim().toLowerCase();
        if (RegExp(r'^sha256:[0-9a-f]{64}$').hasMatch(d)) {
          sha = d.substring('sha256:'.length);
        }
        break;
      }
    }
    return (
      tag: (j['tag_name'] as String? ?? '').trim(),
      notes: (j['body'] as String? ?? '').trim(),
      releaseUrl: (j['html_url'] as String? ?? '').trim(),
      apkUrl: apkUrl,
      apkSha256: sha,
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

/// Odbiorca wyniku haszowania strumieniowego (bez trzymania pliku w pamięci).
class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
