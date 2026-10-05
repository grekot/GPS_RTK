import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

/// Robienie/wybór zdjęcia do punktu i zapis w trwałym katalogu aplikacji.
class PhotoService {
  static final _picker = ImagePicker();

  /// Katalog zdjęć punktów w pamięci aplikacji.
  static Future<Directory> photosDir() async {
    final support = await getApplicationSupportDirectory();
    return Directory('${support.path}/photos');
  }

  /// Czy [path] wskazuje plik wewnątrz katalogu zdjęć [dirPath]. Odrzuca
  /// segmenty `..` (wyjście z katalogu). Używane przy imporcie kopii: obca
  /// ścieżka zdjęcia trafiłaby potem do „Udostępnij" jako załącznik — np.
  /// plik ustawień z hasłem NTRIP.
  static bool isInPhotosDir(String path, String dirPath) {
    String norm(String s) => s.replaceAll(r'\', '/');
    final p = norm(path), d = norm(dirPath).replaceFirst(RegExp(r'/+$'), '');
    if (p.split('/').contains('..')) return false;
    return p.startsWith('$d/') && p.length > d.length + 1;
  }

  /// Wykonuje zdjęcie aparatem (lub wybiera z galerii) i kopiuje do pamięci
  /// aplikacji. Zwraca docelową ścieżkę lub null, gdy anulowano/niedostępne.
  static Future<String?> capture(
    String pointId, {
    ImageSource source = ImageSource.camera,
  }) async {
    final XFile? shot;
    try {
      shot = await _picker.pickImage(
        source: source,
        maxWidth: 2048,
        imageQuality: 80,
      );
    } on Exception {
      return null; // np. brak aparatu na desktopie
    }
    if (shot == null) return null;

    final dir = await photosDir();
    await dir.create(recursive: true);
    final dest = '${dir.path}/$pointId.jpg';
    await File(shot.path).copy(dest);
    return dest;
  }
}
