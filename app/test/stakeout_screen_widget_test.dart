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

/// Sztuczne źródło sterowane z testu — pozycje wpuszcza się przez [ctrl];
/// implementuje też [NtripFlowInfo] (wiek poprawek RTCM ustawiany z testu).
class _StreamSource implements PositionSource, NtripFlowInfo {
  final ctrl = StreamController<RtkPosition>.broadcast();

  @override
  bool ntripActive = false;

  @override
  DateTime? lastRtcmAt;

  @override
  String get name => 'test';

  @override
  Stream<RtkPosition> positions() => ctrl.stream;
}

RtkPosition _rtkFixed(LatLng at, {double accuracy = 0.02}) => RtkPosition(
      latitude: at.latitude,
      longitude: at.longitude,
      accuracy: accuracy,
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

  // Wskaźnik wieku poprawek RTCM: świeże — zielona informacja bez alarmu;
  // stare (>30 s) — ostrzeżenie, że odbiornik trzyma „Fixed" na przewidywanych
  // poprawkach i pozycja może dryfować.
  testWidgets('wiek poprawek: stare RTCM → ostrzeżenie o dryfie',
      (tester) async {
    const target = LatLng(50.0, 20.0);
    final src = _StreamSource()
      ..ntripActive = true
      ..lastRtcmAt = DateTime.now();

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
    await tester.pump();

    // Świeże poprawki: wiersz jest, alarmu nie ma.
    expect(find.textContaining('Poprawki:'), findsOneWidget);
    expect(find.textContaining('może dryfować'), findsNothing);

    // Poprawki się zestarzały (45 s) — kolejna pozycja odświeża panel.
    src.lastRtcmAt = DateTime.now().subtract(const Duration(seconds: 45));
    src.ctrl.add(_rtkFixed(destinationLatLng(target, -1.5, 0)));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('może dryfować'), findsOneWidget);

    await src.ctrl.close();
  });

  // Pełnoekranowa tarcza do precyzyjnego tyczenia: wejście ikoną w panelu,
  // wyjście przyciskiem zamknięcia — te same dane, bez drugiej subskrypcji.
  testWidgets('pełnoekranowa tarcza: otwarcie i zamknięcie', (tester) async {
    const target = LatLng(50.0, 20.0);
    final src = _FixedSource(_rtkFixed(destinationLatLng(target, -1.0, 0)));

    await tester.pumpWidget(MaterialApp(
      home: StakeoutScreen(
        targets: const [target],
        title: 'Test',
        projectId: 'p1',
        source: src,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('tyczenie precyzyjne'), findsNothing);

    await tester.tap(find.byTooltip('Tarcza na pełnym ekranie'));
    await tester.pumpAndSettle();
    expect(find.textContaining('tyczenie precyzyjne'), findsOneWidget);
    // Panel w pełnym ekranie nadal pokazuje odczyty; zwykły panel wciąż jest
    // w drzewie POD nakładką, więc „RTK Fixed" występuje 2× (overlay + panel).
    expect(find.textContaining('RTK Fixed'), findsNWidgets(2));

    await tester.tap(find.byIcon(Icons.fullscreen_exit));
    await tester.pumpAndSettle();
    expect(find.textContaining('tyczenie precyzyjne'), findsNothing);
  });

  // Kurs z RUCHU: bez kompasu i bez kursu z odbiornika strzałka marszu ma
  // prowadzić według kierunku liczonego z kolejnych pozycji RTK — feedback
  // z terenu: kompas przy poziomym montażu kłamał i strzałka pokazywała
  // w inną stronę niż trzeba iść.
  testWidgets('kurs z ruchu: marsz na wschód, cel na północy → „w lewo"',
      (tester) async {
    AppSettings.instance = AppSettings();
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
    // Start 10 m na południe od celu; bez ruchu wskazówka tylko „światowa".
    final p1 = destinationLatLng(target, -10.0, 0);
    src.ctrl.add(_rtkFixed(p1));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('kierunek N'), findsOneWidget);

    // Krok 1 m NA WSCHÓD → kurs z ruchu 90°; cel na północy = po LEWEJ.
    src.ctrl.add(_rtkFixed(destinationLatLng(p1, 0, 1.0)));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('w lewo'), findsOneWidget);

    await src.ctrl.close();
  });

  // Tryb „Północ u góry": przełącznik na pełnym ekranie ustawia stały układ
  // tarczy (zapamiętywany w ustawieniach), a panel przestaje pokazywać
  // wskazówki w układzie ciała (kompas celowo ignorowany).
  testWidgets('pełny ekran: przełącznik „Północ u góry" działa i zapisuje się',
      (tester) async {
    AppSettings.instance = AppSettings(); // czysty stan (statyczny singleton)
    const target = LatLng(50.0, 20.0);
    final src = _FixedSource(RtkPosition(
      latitude: destinationLatLng(target, -1.0, 0).latitude,
      longitude: destinationLatLng(target, -1.0, 0).longitude,
      accuracy: 0.02,
      fixType: FixType.rtkFixed,
      timestamp: DateTime.utc(2026, 7, 4),
      heading: 90, // kurs z GPS — w trybie kompasu daje wskazówki „w lewo"
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
    await tester.tap(find.byTooltip('Tarcza na pełnym ekranie'));
    await tester.pumpAndSettle();

    // Tryb kompasu (domyślny): panel pokazuje odchyłkę w układzie ciała.
    expect(find.textContaining('← w lewo'), findsWidgets);

    await tester.tap(find.text('Północ u góry'));
    await tester.pumpAndSettle();
    expect(AppSettings.instance.dialNorthUp, isTrue);
    // Układ świata: znikają wskazówki ciała, jest dopisek trybu.
    expect(find.textContaining('← w lewo'), findsNothing);
    expect(find.textContaining('północ u góry'), findsWidgets);
    // Duża komenda przesunięcia w N/E jest na ekranie.
    expect(find.textContaining('Przesuń: N'), findsOneWidget);
  });

  // Fałszywy fix: odbiornik raportuje „RTK Fixed", ale jego własna estymata
  // błędu (PQTMEPE) jest duża — panel musi to wykrzyczeć, bo pozycja bywa
  // przesunięta o dm-m mimo zielonego fixa.
  testWidgets('Fixed z dużym szacowanym błędem → „Fix podejrzany"',
      (tester) async {
    const target = LatLng(50.0, 20.0);
    final src = _FixedSource(RtkPosition(
      latitude: destinationLatLng(target, -1.0, 0).latitude,
      longitude: destinationLatLng(target, -1.0, 0).longitude,
      accuracy: 0.5, // EPE 0,5 m przy „Fixed" = podejrzane
      fixType: FixType.rtkFixed,
      timestamp: DateTime.utc(2026, 7, 4),
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

    expect(find.textContaining('Fix podejrzany'), findsOneWidget);
  });
}
