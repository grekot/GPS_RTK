import 'dart:async';
import 'dart:convert' show ascii;
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:usb_serial/usb_serial.dart';

import '../models/rtk_position.dart';
import '../rtk/nmea_parser.dart';
import '../rtk/ntrip_client.dart';
import '../services/app_settings.dart';
import 'position_source.dart';

/// Odbiornik RTK (np. LC29HEA) podłączony kablem **USB-C / OTG** na Androidzie —
/// most USB-serial. To klon [BleReceiverSource] z inną warstwą transportu:
/// zamiast BLE NUS używamy portu szeregowego USB. Parsowanie NMEA
/// ([NmeaParser]) i klient [NtripClient] są transport-agnostyczne i
/// **współdzielone** z wariantem BLE — tu nie powtarzamy ich logiki.
///
/// Przepływ identyczny jak w BLE: bajty z portu → linie NMEA → [RtkPosition];
/// RTCM z castera NTRIP → zapis do portu; GGA odsyłane do castera (sieci VRS).
///
/// Brak telemetrii (`DeviceTelemetry`) — to było rozszerzenie BLE (char.
/// `6E400004`). Status fixa/satelitów i tak pochodzi z NMEA.
///
/// **Tylko Android.** Na iOS/desktopie [positions] od razu zgłasza błąd —
/// `usb_serial` ma natywną część wyłącznie dla Androida.
class UsbReceiverSource extends SharedPositionSource implements NtripFlowInfo {
  @override
  String get name => 'Odbiornik RTK (USB)';

  /// Konfiguracja NTRIP (ustawiana z ekranu ustawień). Null = bez poprawek.
  NtripConfig? ntripConfig;

  final _status = StreamController<String>.broadcast();
  Stream<String> get statusMessages => _status.stream;

  final _parser = NmeaParser();
  final StringBuffer _lineBuf = StringBuffer();
  UsbPort? _port;
  NtripClient? _ntrip;
  Timer? _ggaTimer;
  RtkPosition? _last;
  StreamSubscription<Uint8List>? _portSub;
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
    try {
      _status.add('Szukam odbiornika na USB…');
      final devices = await UsbSerial.listDevices();
      if (!epochActive(epoch)) return;
      if (devices.isEmpty) {
        ctrl.addError(StateError(
            'Nie znaleziono urządzenia USB. Podłącz moduł kablem OTG '
            '(przełączniki płytki w tryb USB-C).'));
        return;
      }
      final device = devices.first;
      final port = await device.create();
      if (port == null) {
        ctrl.addError(StateError('Nie udało się utworzyć portu USB.'));
        return;
      }
      // open() wywołuje systemowy dialog uprawnienia USB (obsługuje usb_serial).
      final opened = await port.open();
      if (!epochActive(epoch)) {
        // Słuchacze odpadli w trakcie łączenia — nie zostawiaj otwartego portu.
        if (opened) await port.close();
        return;
      }
      if (!opened) {
        ctrl.addError(StateError(
            'Brak dostępu do portu USB (odmówiono uprawnienia?).'));
        return;
      }
      _port = port;
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
        onError: (Object e) {
          if (!ctrl.isClosed) ctrl.addError(e);
        },
      );
      final label = device.productName ?? device.manufacturerName ?? 'USB';
      _status.add('Połączono z odbiornikiem ($label, '
          '${AppSettings.instance.usbBaud} bps)');
      // Włącz raport estymaty błędu pozycji (PQTMEPE @1 Hz) — realna
      // dokładność zamiast szacunku z HDOP; niekrytyczne, gdy się nie uda.
      try {
        await port.write(Uint8List.fromList(ascii.encode(enableEpeCommand)));
      } catch (_) {}
      _maybeStartNtrip();
    } catch (e) {
      if (!ctrl.isClosed) ctrl.addError(e);
    }
  }

  // Buforowanie strumienia w linie NMEA — identyczne jak w BleReceiverSource.
  void _onNmeaBytes(List<int> bytes, StreamController<RtkPosition> ctrl) {
    _lineBuf.write(String.fromCharCodes(bytes));
    var rest = _lineBuf.toString();
    int nl;
    while ((nl = rest.indexOf('\n')) != -1) {
      final line = rest.substring(0, nl);
      rest = rest.substring(nl + 1);
      final pos = _parser.addLine(line);
      if (pos != null) {
        _last = pos;
        if (!ctrl.isClosed) ctrl.add(pos);
      }
    }
    _lineBuf
      ..clear()
      ..write(rest);
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
  Future<void> _writeRtcm(List<int> rtcm) async {
    _lastRtcmAt = DateTime.now();
    final port = _port;
    if (port == null) return;
    try {
      await port.write(Uint8List.fromList(rtcm));
    } catch (_) {/* port zniknął — disconnect posprząta */}
  }

  @override
  Future<void> disconnect() async {
    _ggaTimer?.cancel();
    _ggaTimer = null;
    await _ntrip?.stop();
    _ntrip = null;
    _lastRtcmAt = null;
    await _portSub?.cancel();
    _portSub = null;
    try {
      await _port?.close();
    } catch (_) {}
    _port = null;
    _lineBuf.clear();
  }
}
