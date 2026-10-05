import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gps_rtk_app/screens/settings_screen.dart';
import 'package:gps_rtk_app/services/app_settings.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpSettings(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen())),
            child: const Text('otwórz'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('otwórz'));
    await tester.pumpAndSettle();
  }

  testWidgets('zapis ustawień nie kasuje trybu „Północ u góry" tarczy',
      (tester) async {
    AppSettings.instance = AppSettings(dialNorthUp: true, usbBaud: 115200);
    await pumpSettings(tester);
    expect(find.text('Ustawienia'), findsOneWidget);

    await tester.tap(find.byTooltip('Zapisz'));
    await tester.pumpAndSettle();

    expect(AppSettings.instance.dialNorthUp, isTrue);
    expect(AppSettings.instance.usbBaud, 115200);
    expect(find.text('Ustawienia'), findsNothing); // ekran zamknięty
  });

  testWidgets('zmiana przełącznika na ekranie jest zapisywana',
      (tester) async {
    AppSettings.instance = AppSettings(requireFixed: false, dialNorthUp: true);
    await pumpSettings(tester);

    await tester.tap(find.text('Wymagaj RTK Fixed'));
    await tester.pump();
    await tester.tap(find.byTooltip('Zapisz'));
    await tester.pumpAndSettle();

    expect(AppSettings.instance.requireFixed, isTrue);
    expect(AppSettings.instance.dialNorthUp, isTrue);
  });

  test('copyWith zmienia tylko podane pola', () {
    final s = AppSettings(samples: 30, dialNorthUp: true, compassMirror: true);
    final c = s.copyWith(samples: 5);
    expect(c.samples, 5);
    expect(c.dialNorthUp, isTrue);
    expect(c.compassMirror, isTrue);
  });
}
