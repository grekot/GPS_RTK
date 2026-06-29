import 'dart:convert';

/// Telemetria urządzenia odbiornika RTK (ESP32) z charakterystyki BLE „status"
/// `6E400004` — JSON wysyłany co 1 s, niezależnie od strumienia NMEA.
///
/// Pozycja, dokładność i kurs pochodzą z surowego NMEA (charakterystyka TX);
/// tutaj są tylko parametry samego urządzenia (bateria, uptime, przepływ RTCM,
/// MTU) oraz pomocniczo fix/sat/HDOP/wiek poprawek (które łatwiej pokazać z
/// gotowej ramki niż wyłuskiwać z GGA). Kontrakt: `firmware/README.md`.
class DeviceTelemetry {
  const DeviceTelemetry({
    required this.receivedAt,
    this.batteryMv,
    this.batteryPct,
    this.uptimeS,
    this.rtcmBps,
    this.bleMtu,
    this.fix,
    this.satellites,
    this.hdop,
    this.correctionAgeS,
  });

  /// Napięcie ogniwa [mV]. Firmware raportuje 0, gdy pomiar baterii wyłączony.
  final int? batteryMv;

  /// Szacowany stan baterii [%].
  final int? batteryPct;

  /// Uptime urządzenia [s].
  final int? uptimeS;

  /// Przepływ RTCM telefon→moduł [B/s] — potwierdza, że poprawki docierają.
  final int? rtcmBps;

  /// Wynegocjowany ATT MTU.
  final int? bleMtu;

  /// Typ fixa z GGA (0/1/2/4/5). Wartość pomocnicza — głównym źródłem jest NMEA.
  final int? fix;

  final int? satellites;
  final double? hdop;

  /// Wiek poprawek RTCM [s]; null, gdy nieznany (firmware raportuje -1).
  final double? correctionAgeS;

  /// Czas odbioru ramki (do wykrywania zamilknięcia telemetrii).
  final DateTime receivedAt;

  /// Czy moduł raportuje realny pomiar baterii (firmware daje 0, gdy wyłączony).
  bool get hasBattery => (batteryMv ?? 0) > 0;

  /// Czy poprawki RTCM aktualnie płyną do modułu.
  bool get rtcmFlowing => (rtcmBps ?? 0) > 0;

  /// Parsuje jedną ramkę JSON telemetrii. Odporne na obramowanie/śmieci wokół
  /// obiektu (bierze fragment od pierwszego `{` do ostatniego `}`). Zwraca null
  /// dla treści, która nie jest obiektem JSON.
  static DeviceTelemetry? tryParse(String raw, {DateTime? receivedAt}) {
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    try {
      final j = jsonDecode(raw.substring(start, end + 1));
      if (j is! Map) return null;
      var age = (j['age'] as num?)?.toDouble();
      if (age != null && age < 0) age = null; // firmware: -1 = brak poprawek
      return DeviceTelemetry(
        batteryMv: (j['bat_mv'] as num?)?.toInt(),
        batteryPct: (j['bat_pct'] as num?)?.toInt(),
        uptimeS: (j['up_s'] as num?)?.toInt(),
        rtcmBps: (j['rtcm_bps'] as num?)?.toInt(),
        bleMtu: (j['ble_mtu'] as num?)?.toInt(),
        fix: (j['fix'] as num?)?.toInt(),
        satellites: (j['sat'] as num?)?.toInt(),
        hdop: (j['hdop'] as num?)?.toDouble(),
        correctionAgeS: age,
        receivedAt: receivedAt ?? DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }
}
