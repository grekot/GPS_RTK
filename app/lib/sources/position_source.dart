import 'dart:async';

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

/// Wgląd w przepływ poprawek NTRIP źródła — do wskaźnika wieku RTCM w UI.
/// Liczony po stronie aplikacji (moment odebrania z castera), więc działa dla
/// każdego transportu — telemetria BLE (`DeviceTelemetry`) mierzy to samo po
/// stronie urządzenia i jest dokładniejsza, gdy dostępna.
abstract class NtripFlowInfo {
  /// Czy klient NTRIP tego źródła aktualnie działa.
  bool get ntripActive;

  /// Moment odebrania ostatniej porcji RTCM z castera (null = jeszcze nic).
  DateTime? get lastRtcmAt;
}

/// Wiek ostatnich poprawek RTCM źródła [s]. Null, gdy źródło nie używa NTRIP,
/// klient nie działa albo nic jeszcze nie przyszło (start połączenia).
int? rtcmAgeSecondsOf(PositionSource source) {
  if (source is! NtripFlowInfo) return null;
  // Jawny cast: NtripFlowInfo nie jest podtypem PositionSource, więc `is`
  // nie promuje typu.
  final info = source as NtripFlowInfo;
  if (!info.ntripActive) return null;
  final t = info.lastRtcmAt;
  return t == null ? null : DateTime.now().difference(t).inSeconds;
}

/// Baza źródeł sprzętowych (BLE/USB/COM): **jedno fizyczne połączenie
/// współdzielone przez wszystkich słuchaczy**. Ekran główny i ekrany
/// tyczenia/powierzchni subskrybują ten sam strumień broadcast — [connect]
/// uruchamia się przy pierwszym słuchaczu, [disconnect] dopiero gdy odpadnie
/// ostatni (licznik referencji robi `StreamController.broadcast`).
///
/// Bez tego każdy `positions()` otwierał osobne połączenie do tego samego
/// urządzenia: wejście w ekran tyczenia dublowało port i klienta NTRIP
/// (przeplecione ramki RTCM → utrata fixa), a wyjście z niego zamykało port
/// pod ekranem głównym (zamrożona pozycja przy wciąż pokazywanym fixie).
abstract class SharedPositionSource implements PositionSource {
  StreamController<RtkPosition>? _shared;
  int _epoch = 0;

  @override
  Stream<RtkPosition> positions() {
    var ctrl = _shared;
    if (ctrl == null) {
      late final StreamController<RtkPosition> c;
      c = StreamController<RtkPosition>.broadcast(
        onListen: () => connect(c, ++_epoch),
        onCancel: () {
          _epoch++; // unieważnia connect() będące w trakcie (np. skanowanie)
          unawaited(disconnect());
        },
      );
      _shared = c;
      ctrl = c;
    }
    return ctrl.stream;
  }

  /// Czy sesja [epoch] jest wciąż aktualna. [connect] sprawdza to po dłuższych
  /// `await`, żeby nie dokończyć łączenia, gdy w międzyczasie wszyscy
  /// słuchacze odpadli (szybkie Start→Stop).
  bool epochActive(int epoch) => epoch == _epoch;

  /// Otwiera połączenie — wołane, gdy pojawi się pierwszy słuchacz.
  /// Błędy zgłasza przez `ctrl.addError` (strumień pozostaje otwarty,
  /// kolejny słuchacz próbuje połączyć od nowa).
  Future<void> connect(StreamController<RtkPosition> ctrl, int epoch);

  /// Zamyka połączenie — wołane, gdy odpadnie ostatni słuchacz.
  Future<void> disconnect();
}
