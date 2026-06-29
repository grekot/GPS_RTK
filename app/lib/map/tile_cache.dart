import 'dart:async';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:path_provider/path_provider.dart';

import 'base_layers.dart';
import 'tile_math.dart';

/// Trwały dyskowy cache kafelków mapy. flutter_map ma wbudowany cache, ale
/// domyślnie w katalogu, który system może czyścić — przepinamy go na trwały
/// katalog aplikacji, dzięki czemu obejrzane (i pobrane) kafelki są dostępne
/// offline także po restarcie.
class MapCache {
  MapCache._();

  static const _userAgent = 'pl.gpsrtk.gps_rtk_app';
  static const int maxBytes = 500 * 1024 * 1024; // 500 MB
  static String? _baseDir;

  /// Wołane raz w `main()` przed `runApp`.
  static Future<void> init() async {
    final support = await getApplicationSupportDirectory();
    _baseDir = '${support.path}/map_cache';
    BuiltInMapCachingProvider.getOrCreateInstance(
      cacheDirectory: _baseDir,
      maxCacheSize: maxBytes,
    );
  }

  /// Rozmiar cache w bajtach (suma plików w katalogu `fm_cache`).
  static Future<int> sizeBytes() async {
    final base = _baseDir;
    if (base == null) return 0;
    final dir = Directory('$base/fm_cache');
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final e in dir.list(recursive: true, followLinks: false)) {
      if (e is File) total += await e.length();
    }
    return total;
  }

  /// Czyści cache (usuwa pliki) i odtwarza instancję na tym samym katalogu.
  static Future<void> clear() async {
    await BuiltInMapCachingProvider.getOrCreateInstance()
        .destroy(deleteCache: true);
    await init();
  }

  /// Proaktywnie pobiera kafelki pokrywające prostokąt (s/w/n/e) dla wybranej
  /// warstwy i zakresu zoomów, zapisując je do cache (działają potem offline).
  /// Zwraca liczbę pobranych kafelków. `onProgress(done, total)` raportuje postęp.
  static Future<int> prefetchArea({
    required MapBaseLayer layer,
    required double south,
    required double west,
    required double north,
    required double east,
    int minZoom = 15,
    int maxZoom = 19,
    int cap = 2500,
    void Function(int done, int total)? onProgress,
  }) async {
    final options = buildBaseTileLayer(layer);
    final all = tilesForBounds(south, west, north, east, minZoom, maxZoom);
    final tiles = all.length > cap ? all.sublist(0, cap) : all;

    final provider = NetworkTileProvider(headers: {'User-Agent': _userAgent});
    final never = Completer<void>().future; // nie anuluj ładowania
    var done = 0;
    const batch = 6;
    try {
      for (var i = 0; i < tiles.length; i += batch) {
        final slice = tiles.sublist(i, (i + batch).clamp(0, tiles.length));
        await Future.wait(slice.map((t) async {
          final img = provider.getImageWithCancelLoadingSupport(
            TileCoordinates(t.x, t.y, t.z),
            options,
            never,
          );
          await _resolve(img);
        }));
        done += slice.length;
        onProgress?.call(done, tiles.length);
      }
    } finally {
      await provider.dispose();
    }
    return tiles.length;
  }

  /// Ładuje ImageProvider do końca (sukces lub błąd) — wymusza pobranie i zapis
  /// do cache. Błędy (np. brak kafelka) są ignorowane.
  static Future<void> _resolve(ImageProvider img) {
    final completer = Completer<void>();
    final stream = img.resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    void done() {
      stream.removeListener(listener);
      if (!completer.isCompleted) completer.complete();
    }

    listener = ImageStreamListener(
      (_, _) => done(),
      onError: (_, _) => done(),
    );
    stream.addListener(listener);
    return completer.future;
  }
}
