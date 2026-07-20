/// Typ rozwiązania pozycji — odpowiada polu "fix quality" ze zdania NMEA GGA.
enum FixType {
  none, // 0 - brak pozycji
  gps, // 1 - pozycja autonomiczna (tak raportuje GPS telefonu)
  dgps, // 2 - poprawki różnicowe kodowe
  rtkFixed, // 4 - RTK Fixed (cm)
  rtkFloat, // 5 - RTK Float (dm)
}

/// Ranga jakości fixa (większa = lepsza). Uwaga: kolejność wartości w enum nie
/// odpowiada jakości (rtkFloat jest gorszy od rtkFixed), dlatego osobna funkcja.
int fixRank(FixType f) => switch (f) {
      FixType.none => 0,
      FixType.gps => 1,
      FixType.dgps => 2,
      FixType.rtkFloat => 3,
      FixType.rtkFixed => 4,
    };

/// Krótka etykieta typu fixa dla UI i eksportu.
String fixLabel(FixType f) => switch (f) {
      FixType.none => 'brak',
      FixType.gps => 'GPS',
      FixType.dgps => 'DGPS',
      FixType.rtkFloat => 'RTK Float',
      FixType.rtkFixed => 'RTK Fixed',
    };

/// Po ilu sekundach bez nowej pozycji uznajemy dane za nieświeże. UI pokazuje
/// wtedy „brak danych" zamiast ostatniego (już nieaktualnego) statusu fixa —
/// zamrożona pozycja z zieloną plakietką „RTK Fixed" wprowadzała w błąd.
/// Odbiornik nadaje 1–10 Hz, więc 5 s to bezpieczny margines.
const int positionStaleSeconds = 5;

/// Progi wieku ostatnich poprawek RTCM [s] dla wskaźnika w UI: do
/// [rtcmAgeWarnSeconds] zielono (płyną na bieżąco), potem pomarańczowo,
/// powyżej [rtcmAgeBadSeconds] czerwono — odbiornik trzyma wtedy „Fixed" na
/// przewidywanych poprawkach i pozycja może dryfować mimo zielonego fixa.
const int rtcmAgeWarnSeconds = 10;
const int rtcmAgeBadSeconds = 30;

/// Szacowany błąd [m], powyżej którego „RTK Fixed" traktujemy jako podejrzany
/// (fałszywy fix — złe rozwiązanie nieoznaczoności, typowo przy odbiciach).
/// Prawdziwy Fixed ma 2–5 cm; szacunek z HDOP nie przekracza 0,10 m, więc
/// ostrzeżenie odpala tylko realna estymata odbiornika (PQTMEPE/GST).
const double suspectFixedAccuracyMeters = 0.10;

/// Pozycja niezależna od źródła (GPS telefonu / odbiornik RTK po BLE).
class RtkPosition {
  final double latitude;
  final double longitude;
  final double? altitude;

  /// Szacowany błąd poziomy w metrach (1 sigma).
  final double accuracy;
  final FixType fixType;
  final int? satellites;

  /// Kierunek ruchu (kurs nad ziemią) w stopniach 0–360, jeśli znany.
  final double? heading;
  final DateTime timestamp;

  const RtkPosition({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.fixType,
    required this.timestamp,
    this.altitude,
    this.satellites,
    this.heading,
  });
}
