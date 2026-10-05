import 'dart:async';
import 'dart:convert' show ascii;
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:usb_serial/usb_serial.dart';

import '../models/rtk_position.dart';
import '../rtk/nmea_line_assembler.dart';
import '../rtk/nmea_parser.dart';
import '../rtk/ntrip_client.dart';
import '../services/app_settings.dart';
import 'position_source.dart';

/// Producenci mostków USB-UART spotykanych na płytkach GNSS (VID).
/// Ten sam zestaw jest w `android/app/src/main/res/xml/device_filter.xml`.
const Map<int, String> knownUsbSerialVendors = {
  0x10C4: 'Silicon Labs CP210x',
  0x1A86: 'WCH CH34x',
  0x0403: 'FTDI',
  0x067B: 'Prolific PL2303',
  0x1546: 'u-blox',
};

/// Wybiera urządzenie odbiornika z listy USB. Kolejność: to samo VID:PID co
/// ostatnio (ponowne wpięcie kabla), potem znany mostek USB-UART, na końcu
/// pierwsze dowolne (np. moduł z natywnym USB CDC). Null = pusta lista.
UsbDevice? pickReceiverDevice(
  List<UsbDevice> devices, {
  int? preferredVid,
  int? preferredPid,
}) {
  if (devices.isEmpty) return null;
  if (preferredVid != null) {
    for (final d in devices) {
      if (d.vid == preferredVid && d.pid == preferredPid) return d;
    }
  }
  for (final d in devices) {
    if (knownUsbSerialVendors.containsKey(d.vid)) return d;
  }
  return devices.first;
}

/// Reakcja źródła na systemowe zdarzenie USB.
enum UsbEventAction { ignore, closePort, reopen }

/// Decyzja dla zdarzenia [event] (podpięcie/odpięcie) przy bieżącym stanie.
/// [portOpen] — czy port odbiornika jest otwarty; [openDeviceId] — id jego
/// urządzenia (może być nieznane).
UsbEventAction usbEventAction(
  String? event,
  int? eventDeviceId, {
  required bool portOpen,
  int? openDeviceId,
}) {
  if (event == UsbEvent.ACTION_USB_DETACHED) {
    if (!portOpen) return UsbEventAction.ignore;
    // Brak id po którejś stronie — ostrożnie zamknij (lepiej niż wisieć na
    // martwym porcie); inne urządzenie (np. pendrive) — ignoruj.
    if (eventDeviceId == null || openDeviceId == null) {
      return UsbEventAction.closePort;
    }
    return eventDeviceId == openDeviceId
        ? UsbEventAction.closePort
        : UsbEventAction.ignore;
  }
  if (event == UsbEvent.ACTION_USB_ATTACHED) {
    return portOpen ? UsbEventAction.ignore : UsbEventAction.reopen;
  }
  return UsbEventAction.ignore;
}

/// Odbiornik RTK (np. LC29HEA) podłączony kablem **USB-C / OTG** na Androidzie —
/// most USB-serial. Parsowanie NMEA ([NmeaParser]) i klient [NtripClient] są
/// współdzielone z pozostałymi transportami.
///
/// Przepływ: bajty z portu → linie NMEA → [RtkPosition]; RTCM z castera NTRIP
/// → zapis do portu; GGA odsyłane do castera (sieci VRS).
///
/// **Kabel w terenie:** chwilowe odpięcie złącza OTG nie kończy sesji. Port
/// jest zamykany, a po ponownym wpięciu otwierany sam (zdarzenia
/// [UsbSerial.usbEventStream]). Klient NTRIP działa dalej przez
/// [ntripGraceAfterDetach], żeby po wpięciu poprawki popłynęły od razu; dłuższy
/// brak odbiornika zatrzymuje NTRIP.
///
/// **Tylko Android.** Na iOS/desktopie [positions] od razu zgłasza błąd.
class UsbReceiverSource extends SharedPositionSource implements NtripFlowInfo {
  UsbReceiverSource({this.ntripGraceAfterDetach = const Duration(minutes: 2)});

  @override
  String get name => 'Odbiornik RTK (USB)';

  /// Jak długo po odpięciu kabla trzymać połączenie NTRIP.
  final Duration ntripGraceAfterDetach;

  /// Konfiguracja NTRIP (ustawiana z ekranu ustawień). Null = bez poprawek.
  NtripConfig? ntripConfig;

  final _status = StreamController<String>.broadcast();
  Stream<String> get statusMessages => _status.stream;

  final _parser = NmeaParser();
  final _lines = NmeaLineAssembler();
  UsbPort? _port;
  int? _openDeviceId;
  int? _lastVid;
  int? _lastPid;
  bool _opening = false;
  NtripClient? _ntrip;
  Timer? _ggaTimer;
  Timer? _ntripGraceTimer;
  RtkPosition? _last;
  StreamSubscription<Uint8List>? _portSub;
  StreamSubscription<UsbEvent>? _usbEventsSub;
  StreamController<RtkPosition>? _ctrl;
  int _sessionEpoch = -1;
  DateTime? _lastRtcmAt;

  @override
  bool get ntripActive => _ntrip != null;

  @override
  DateTime? get lastRtcmAt => _lastRtcmAt;

  @override
  Future<void> connect(StreamController<RtkPosition> ctrl, int epoch) async {
    if (!Platform.isAndroid) {
      ctrl.addError(StateError(
          'Połączenie USB jest dostępne tylko na Androidzie — użyj BLE.'));
      return;
    }
    _ctrl = ctrl;
    _sessionEpoch = epoch;
    _usbEventsSub ??= UsbSerial.usbEventStream?.listen(_onUsbEvent);
    await _openPort(ctrl, epoch, firstAttempt: true);
  }

  /// Otwiera port odbiornika. Przy pierwszej próbie (Start) błąd idzie do
  /// strumienia — użytkownik widzi, że brak kabla. Przy ponownym wpięciu
  /// tylko komunikat statusu, sesja trwa dalej.
  Future<void> _openPort(StreamController<RtkPosition> ctrl, int epoch,
      {required bool firstAttempt}) async {
    if (_opening || _port != null) return;
    _opening = true;
    void fail(Object e) {
      if (firstAttempt) {
        if (!ctrl.isClosed) ctrl.addError(e);
      } else {
        _status.add('USB: $e');
      }
    }

    try {
      _status.add('Szukam odbiornika na USB…');
      final devices = await UsbSerial.listDevices();
      if (!epochActive(epoch)) return;
      final device = pickReceiverDevice(devices,
          preferredVid: _lastVid, preferredPid: _lastPid);
      if (device == null) {
        fail(StateError('Nie znaleziono urządzenia USB. Podłącz moduł kablem '
            'OTG (przełączniki płytki w tryb USB-C).'));
        return;
      }
      final port = await device.create();
      if (port == null) {
        fail(StateError('Nie udało się utworzyć portu USB.'));
        return;
      }
      // open() wywołuje systemowy dialog uprawnienia USB (obsługuje
      // usb_serial). Z filtrem urządzeń w manifeście Android pamięta zgodę.
      final opened = await port.open();
      if (!epochActive(epoch)) {
        // Słuchacze odpadli w trakcie łączenia — nie zostawiaj otwartego portu.
        if (opened) await port.close();
        return;
      }
      if (!opened) {
        fail(StateError('Brak dostępu do portu USB (odmówiono uprawnienia?).'));
        return;
      }
      _port = port;
      _openDeviceId = device.deviceId;
      _lastVid = device.vid;
      _lastPid = device.pid;
      _lines.clear();
      await port.setDTR(true);
      await port.setRTS(true);
      await port.setPortParameters(
        AppSettings.instance.usbBaud,
        UsbPort.DATABITS_8,
        UsbPort.STOPBITS_1,
        UsbPort.PARITY_NONE,
      );
      _portSub = port.inputStream?.listen(
        (bytes) => _onNmeaBytes(bytes, ctrl),
        // Błąd/koniec strumienia = port padł (np. kabel). Nie kończymy sesji —
        // zamykamy port i czekamy na ponowne podpięcie.
        onError: (Object _) => _onPortLost(),
        onDone: _onPortLost,
      );
      final label = device.productName ?? device.manufacturerName ?? 'USB';
      _status.add('Połączono z odbiornikiem ($label, '
          '${AppSettings.instance.usbBaud} bps)');
      // Ogranicz zdania NMEA do potrzebnych + włącz PQTMEPE (sesyjnie).
      try {
        await port.write(
            Uint8List.fromList(ascii.encode(receiverSetupCommands.join())));
      } catch (_) {}
      _ntripGraceTimer?.cancel();
      _ntripGraceTimer = null;
      _maybeStartNtrip();
    } catch (e) {
      fail(e);
    } finally {
      _opening = false;
    }
  }

  void _onUsbEvent(UsbEvent e) {
    final ctrl = _ctrl;
    if (ctrl == null || !epochActive(_sessionEpoch)) return;
    switch (usbEventAction(e.event, e.device?.deviceId,
        portOpen: _port != null, openDeviceId: _openDeviceId)) {
      case UsbEventAction.closePort:
        _onPortLost();
      case UsbEventAction.reopen:
        _status.add('Wykryto podłączenie USB — łączę ponownie…');
        unawaited(_openPort(ctrl, _sessionEpoch, firstAttempt: false));
      case UsbEventAction.ignore:
        break;
    }
  }

  /// Port przestał działać (odpięty kabel). Zamyka go, zostawia sesję i NTRIP
  /// na [ntripGraceAfterDetach].
  void _onPortLost() {
    if (_port == null) return;
    _status.add('Odbiornik USB odłączony — podłącz kabel ponownie.');
    unawaited(_closePort());
    _ntripGraceTimer?.cancel();
    if (_ntrip != null) {
      _ntripGraceTimer = Timer(ntripGraceAfterDetach, () {
        if (_port == null) unawaited(_stopNtrip());
      });
    }
  }

  Future<void> _closePort() async {
    final sub = _portSub;
    final port = _port;
    _portSub = null;
    _port = null;
    _openDeviceId = null;
    _lines.clear();
    await sub?.cancel();
    try {
      await port?.close();
    } catch (_) {}
  }

  void _onNmeaBytes(List<int> bytes, StreamController<RtkPosition> ctrl) {
    for (final line in _lines.add(bytes)) {
      final pos = _parser.addLine(line);
      if (pos != null) {
        _last = pos;
        if (!ctrl.isClosed) ctrl.add(pos);
      }
    }
  }

  void _maybeStartNtrip() {
    if (_ntrip != null) return; // już działa — nie dubluj klienta ani timera GGA
    final cfg = ntripConfig;
    if (cfg == null || !cfg.isComplete) return;
    _ntrip = NtripClient(
      cfg,
      onRtcm: _writeRtcm,
      onStatus: _status.add,
      onReady: _sendGgaNow, // GGA od razu po połączeniu → szybkie ustawienie VRS
    )..start();
    _ggaTimer = Timer.periodic(
        Duration(seconds: AppSettings.instance.ggaSeconds),
        (_) => _sendGgaNow());
  }

  Future<void> _stopNtrip() async {
    _ggaTimer?.cancel();
    _ggaTimer = null;
    await _ntrip?.stop();
    _ntrip = null;
    _lastRtcmAt = null;
  }

  void _sendGgaNow() {
    final p = _last;
    if (p == null) return;
    _ntrip?.sendGga(buildGgaSentence(
      p.latitude,
      p.longitude,
      fixQuality: switch (p.fixType) {
        FixType.rtkFixed => 4,
        FixType.rtkFloat => 5,
        FixType.dgps => 2,
        _ => 1,
      },
      satellites: p.satellites ?? 10,
      altitude: p.altitude ?? 100,
    ));
  }

  // USB uciągnie całość strumienia RTCM bez ograniczenia MTU (inaczej niż BLE).
  // Natywny zapis usb_serial idzie przez kolejkę w osobnym wątku, więc porcje
  // się nie przeplatają.
  Future<void> _writeRtcm(List<int> rtcm) async {
    _lastRtcmAt = DateTime.now();
    final port = _port;
    if (port == null) return; // kabel odpięty — porcja przepada (to poprawki)
    try {
      await port.write(Uint8List.fromList(rtcm));
    } catch (_) {/* port zniknął — zdarzenie odpięcia posprząta */}
  }

  @override
  Future<void> disconnect() async {
    _ntripGraceTimer?.cancel();
    _ntripGraceTimer = null;
    await _usbEventsSub?.cancel();
    _usbEventsSub = null;
    _ctrl = null;
    await _stopNtrip();
    await _closePort();
  }
}
