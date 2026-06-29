import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Globalne ustawienia aplikacji (trwałe). Czytane przez kod pomiarowy/NTRIP
/// przez [AppSettings.instance], zapisywane z ekranu ustawień.
class AppSettings {
  AppSettings({
    this.samples = 20,
    this.requireFixed = false,
    this.keepAwake = true,
    this.ggaSeconds = 10,
    this.usbBaud = 460800,
  });

  /// Liczba epok uśredniania pomiaru punktu.
  int samples;

  /// Wymagaj RTK Fixed do przyjęcia próbki (odrzuca Float/GPS).
  bool requireFixed;

  /// Trzymaj ekran włączony podczas pomiaru.
  bool keepAwake;

  /// Co ile sekund wysyłać GGA do castera NTRIP (sieci VRS).
  int ggaSeconds;

  /// Prędkość portu USB-serial / COM [bit/s] odbiornika RTK. Domyślnie 460800 —
  /// tyle realnie nadaje nasza płytka LC29HEA (zmierzone na COM3; instrukcja
  /// płytki podawała 115200, ale sprzęt gada 460800). Regulowane w ustawieniach.
  int usbBaud;

  /// Typowe prędkości portu do wyboru w ustawieniach.
  static const usbBaudOptions = [
    9600,
    19200,
    38400,
    57600,
    115200,
    230400,
    460800,
    921600,
  ];

  static AppSettings instance = AppSettings();
  static const _key = 'settings.v1';

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return;
    final j = jsonDecode(raw) as Map<String, dynamic>;
    instance = AppSettings(
      samples: (j['samples'] as num?)?.toInt() ?? 20,
      requireFixed: j['requireFixed'] as bool? ?? false,
      keepAwake: j['keepAwake'] as bool? ?? true,
      ggaSeconds: (j['ggaSeconds'] as num?)?.toInt() ?? 10,
      usbBaud: (j['usbBaud'] as num?)?.toInt() ?? 460800,
    );
  }

  /// Zapisuje i ustawia jako bieżące ([instance]).
  Future<void> save() async {
    instance = this;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode({
        'samples': samples,
        'requireFixed': requireFixed,
        'keepAwake': keepAwake,
        'ggaSeconds': ggaSeconds,
        'usbBaud': usbBaud,
      }),
    );
  }
}
