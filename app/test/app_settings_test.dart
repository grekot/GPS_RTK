import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gps_rtk_app/services/app_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('domyślny baud = 460800 (zmierzony na płytce) i jest na liście opcji', () {
    expect(AppSettings().usbBaud, 460800);
    expect(AppSettings.usbBaudOptions, contains(115200));
    expect(AppSettings.usbBaudOptions, contains(460800));
  });

  test('round-trip save/load zachowuje usbBaud i pozostałe pola', () async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings(
      samples: 30,
      requireFixed: true,
      keepAwake: false,
      ggaSeconds: 5,
      usbBaud: 460800,
      compassMirror: true,
    ).save();
    await AppSettings.load();
    final s = AppSettings.instance;
    expect(s.samples, 30);
    expect(s.requireFixed, isTrue);
    expect(s.keepAwake, isFalse);
    expect(s.ggaSeconds, 5);
    expect(s.usbBaud, 460800);
    expect(s.compassMirror, isTrue);
  });

  test('compassMirror: domyślnie wyłączony (stare zapisy bez pola)', () async {
    SharedPreferences.setMockInitialValues({
      'settings.v1': '{"samples":25,"requireFixed":false,'
          '"keepAwake":true,"ggaSeconds":10,"usbBaud":460800}',
    });
    await AppSettings.load();
    expect(AppSettings.instance.compassMirror, isFalse);
  });

  test('brak zapisanych ustawień → wartości domyślne', () async {
    SharedPreferences.setMockInitialValues({});
    AppSettings.instance = AppSettings(usbBaud: 999); // celowo nietypowy
    await AppSettings.load(); // brak klucza → instance bez zmian
    expect(AppSettings.instance.usbBaud, 999);
  });

  test('stare ustawienia bez pola usbBaud → fallback 460800', () async {
    // Zapis sprzed dodania usbBaud (klucz pominięty) — po aktualizacji apki
    // baud ma być 460800, nie 115200.
    SharedPreferences.setMockInitialValues({
      'settings.v1': '{"samples":25,"requireFixed":false,'
          '"keepAwake":true,"ggaSeconds":10}',
    });
    await AppSettings.load();
    expect(AppSettings.instance.usbBaud, 460800);
    expect(AppSettings.instance.samples, 25); // reszta wczytana normalnie
  });
}
