import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

/// Robienie/wybór zdjęcia do punktu i zapis w trwałym katalogu aplikacji.
class PhotoService {
  static final _picker = ImagePicker();

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

    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/photos');
    await dir.create(recursive: true);
    final dest = '${dir.path}/$pointId.jpg';
    await File(shot.path).copy(dest);
    return dest;
  }
}
