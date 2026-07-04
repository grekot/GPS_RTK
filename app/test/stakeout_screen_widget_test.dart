import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gps_rtk_app/models/rtk_position.dart';
import 'package:gps_rtk_app/screens/stakeout_screen.dart';
import 'package:gps_rtk_app/services/app_settings.dart';
import 'package:gps_rtk_app/sources/position_source.dart';
import 'package:gps_rtk_app/utils/geo.dart';

/// Sztuczne źródło: emituje jedną, z góry zadaną pozycję (zimny strumień).
class _FixedSource implements PositionSource {
  _FixedSource(this.pos);
  final RtkPosition pos;

  @override
  String get name => 'test';

  @override
  Stream<RtkPosition> positions() => Stream.value(pos);
}

/// Sztuczne źródło sterowane z testu — pozycje wpuszcza się przez [ctrl].
class _StreamSource implements PositionSource {
  final ctrl = StreamController<RtkPosition>.broadcast();

  @override
  String get name => 'test';

  @override
  Stream<RtkPosition> positions() => ctrl.stream;
}

RtkPosition _rtkFixed(LatLng at) => RtkPosition(
      latitude: at.latitude,
      longitude: at.longitude,
      accuracy: 0.02,
      fixType: FixType.rtkFixed,
      timestamp: DateTime.utc(2026, 7, 4),
    );

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.load();
  });

  // Prowadzenie „na ostatnich metrach": stoję 1 m na POŁUDNIE od celu,
  // patrzę na WSCHÓD (heading 90°) → cel jest po mojej LEWEJ ręce.
  // Panel musi pokazać odchyłkę w układzie ciała („w lewo"), a nie tylko
  // statyczne N/E — to była przyczyna dezorientacji w terenie.
  testWidgets('tyczenie z bliska: wskazówka „w lewo" względem patrzenia',
      (tester) async {
    const target = LatLng(50.0, 20.0);
    final current = destinationLatLng(target, -1.0, 0); // 1 m na południe
    final src = _FixedSource(RtkPosition(
      latitude: current.latitude,
      longitude: current.longitude,
      accuracy: 0.02,
      fixType: FixType.rtkFixed,
      timestamp: DateTime.utc(2026, 6, 30),
      heading: 90, // patrzę na wschód
    ));

    await tester.pumpWidget(MaterialApp(
      home: StakeoutScreen(
        targets: const [target],
        title: 'Test',
        projectId: 'p1',
        source: src,
      ),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // Wiersz odchyłki w układzie ciała: cel po lewej (≈1 m), przód ≈ 0.
    expect(find.textContaining('← w lewo'), findsOneWidget);
    expect(find.textContaining('↑ przód'), findsOneWidget);
    // Statyczne N/E nadal widoczne jako druga linia (północ ~1 m).
    expect(find.textContaining('N '), findsWidgets);
  });

  // Watchdog świeżości: gdy strumień pozycji „zamarł" (np. padło połączenie
  // USB), panel nie może dalej pokazywać zielonego „RTK Fixed" — w terenie
  // oznaczało to tyczenie po zamrożonej, nieaktualnej pozycji.
  testWidgets('watchdog: zamrożony strumień → ostrzeżenie zamiast fixa',
      (tester) async {
    const target = LatLng(50.0, 20.0);
    final src = _StreamSource();

    await tester.pumpWidget(MaterialApp(
      home: StakeoutScreen(
        targets: const [target],
        title: 'Test',
        projectId: 'p1',
        source: src,
      ),
    ));
    src.ctrl.add(_rtkFixed(destinationLatLng(target, -1.0, 0)));
    await tester.pump();

    // Świeże dane: normalny status, bez ostrzeżenia.
    expect(find.textContaining('RTK Fixed'), findsOneWidget);
    expect(find.textContaining('Brak nowych pozycji'), findsNothing);

    // 6 s ciszy → ostrzeżenie o zamrożonej pozycji, status fixa znika.
    await tester.pump(const Duration(seconds: 6));
    expect(find.textContaining('Brak nowych pozycji od'), findsOneWidget);
    expect(find.textContaining('RTK Fixed'), findsNothing);

    // Nowa pozycja kasuje ostrzeżenie. Dwa pumpy: pierwszy dostarcza zdarzenie
    // strumienia (mikrotask → setState), drugi rysuje zaplanowaną klatkę.
    src.ctrl.add(_rtkFixed(destinationLatLng(target, -2.0, 0)));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Brak nowych pozycji'), findsNothing);
    expect(find.textContaining('RTK Fixed'), findsOneWidget);

    await src.ctrl.close();
  });
}
