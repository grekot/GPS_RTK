import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/measured_point.dart';
import '../utils/dxf.dart';

/// Eksport zmierzonych punktów do plików CSV + GeoJSON + DXF i otwarcie
/// systemowego arkusza „Udostępnij" (zapis na dysk, wysyłka mailem, chmura).
class ExportService {
  /// Zapisuje CSV, GeoJSON i DXF do katalogu tymczasowego i udostępnia pliki.
  /// Zwraca liczbę wyeksportowanych punktów.
  static Future<int> sharePoints(
    List<MeasuredPoint> points, {
    String namePrefix = 'pomiary',
    String stamp = '',
  }) async {
    final dir = await getTemporaryDirectory();
    final base = stamp.isEmpty ? namePrefix : '${namePrefix}_$stamp';

    final csv = File('${dir.path}/$base.csv');
    await csv.writeAsString(measuredPointsToCsv(points));

    final geojson = File('${dir.path}/$base.geojson');
    await geojson.writeAsString(measuredPointsToGeoJson(points));

    final dxf = File('${dir.path}/$base.dxf');
    await dxf.writeAsString(measuredPointsToDxf(points));

    // Dołącz istniejące zdjęcia punktów.
    final photos = [
      for (final p in points)
        if (p.photoPath != null && File(p.photoPath!).existsSync())
          XFile(p.photoPath!),
    ];

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(csv.path), XFile(geojson.path), XFile(dxf.path), ...photos],
        subject: 'Pomiary GPS RTK',
        text: 'Eksport ${points.length} punktów (CSV + GeoJSON + DXF'
            '${photos.isNotEmpty ? ' + ${photos.length} zdjęć' : ''}).',
      ),
    );
    return points.length;
  }

  /// Zapisuje kilka plików tekstowych (nazwa→treść) i udostępnia je razem.
  static Future<void> shareTextFiles(
    Map<String, String> files, {
    String? subject,
  }) async {
    final dir = await getTemporaryDirectory();
    final xfiles = <XFile>[];
    for (final e in files.entries) {
      final f = File('${dir.path}/${e.key}');
      await f.writeAsString(e.value);
      xfiles.add(XFile(f.path));
    }
    await SharePlus.instance.share(
      ShareParams(files: xfiles, subject: subject),
    );
  }

  /// Zapisuje bajty PDF do pliku tymczasowego i otwiera „Udostępnij".
  static Future<void> sharePdf(Uint8List bytes, String filename) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        subject: 'Instrukcja GPS RTK',
      ),
    );
  }

  /// Zapisuje tekst do pliku tymczasowego i otwiera „Udostępnij" (np. projekt
  /// GeoJSON).
  static Future<void> shareTextFile(
    String content,
    String filename, {
    String? subject,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsString(content);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], subject: subject),
    );
  }
}
