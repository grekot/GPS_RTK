import '../models/rtk_position.dart';

/// Abstrakcja źródła pozycji. Aplikacja zna tylko ten interfejs —
/// dzięki temu GPS telefonu, odbiornik RTK po BLE i odtwarzanie logów NMEA
/// są w pełni wymienne.
abstract class PositionSource {
  /// Nazwa pokazywana użytkownikowi.
  String get name;

  /// Strumień pozycji. Zimny: subskrypcja uruchamia źródło,
  /// anulowanie subskrypcji je zatrzymuje.
  Stream<RtkPosition> positions();
}
