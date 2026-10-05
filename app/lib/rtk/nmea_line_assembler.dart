/// Składa strumień bajtów z odbiornika (USB/COM/BLE) w pełne linie NMEA.
///
/// Bajty przychodzą w dowolnych porcjach — linia może być rozcięta między
/// dwoma odczytami, a jedna porcja może nieść kilka linii. Składacz trzyma
/// niedokończony ogon do następnej porcji.
///
/// **Limit bufora** ([maxPending]): przy złym baudzie (śmieci bez `\n`) ogon
/// rósłby bez końca. Po przekroczeniu limitu ogon jest porzucany — prawdziwa
/// linia NMEA ma maks. 82 znaki (zdania PQTM nieco więcej), więc 4 KB bez
/// końca linii to na pewno śmieci.
class NmeaLineAssembler {
  NmeaLineAssembler({this.maxPending = 4096});

  final int maxPending;
  String _pending = '';

  /// Ile znaków czeka na koniec linii (do testów/diagnostyki).
  int get pendingLength => _pending.length;

  /// Dokłada porcję bajtów i zwraca kompletne linie (bez `\r\n`).
  List<String> add(List<int> bytes) {
    var rest = _pending + String.fromCharCodes(bytes);
    final lines = <String>[];
    int nl;
    while ((nl = rest.indexOf('\n')) != -1) {
      final line = rest.substring(0, nl).trim();
      if (line.isNotEmpty) lines.add(line);
      rest = rest.substring(nl + 1);
    }
    _pending = rest.length > maxPending ? '' : rest;
    return lines;
  }

  void clear() => _pending = '';
}
