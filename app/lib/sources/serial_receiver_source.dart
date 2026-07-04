import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_libserialport/flutter_libserialport.dart';

import '../models/rtk_position.dart';
import '../rtk/nmea_parser.dart';
import '../rtk/ntrip_client.dart';
import '../services/app_settings.dart';
import 'position_source.dart';

/// Odbiornik RTK podłączony kablem jako **port szeregowy / COM** na desktopie
/// (Windows/Linux/macOS) — Windows pokazuje LC29HEA jako `COMx`. To bliźniak
/// [UsbReceiverSource], tyle że transportem jest `flutter_libserialport`
/// (libserialport) zamiast androidowego `usb_serial`. [NmeaParser] i
/// [NtripClient] są transport-agnostyczne i **współdzielone**.
///
/// Przepływ jak w BLE/USB: bajty z portu → linie NMEA → [RtkPosition];
/// RTCM z castera NTRIP → zapis do portu; GGA odsyłane do castera (VRS).
/// Brak telemetrii (`DeviceTelemetry`) — to rozszerzenie BLE; status z NMEA.
class SerialReceiverSource extends SharedPositionSource {
  @override
  String get name => 'Odbiornik RTK (COM)';

  /// Nazwa portu (np. `COM3`). Null = pierwszy dostępny.
  String? portName;

  /// Konfiguracja NTRIP (jak w BLE/USB). Null = bez poprawek.
  NtripConfig? ntripConfig;

  final _status = StreamController<String>.broadcast();
  Stream<String> get statusMessages => _status.stream;

  final _parser = NmeaParser();
  final StringBuffer _lineBuf = StringBuffer();
  SerialPort? _port;
  SerialPortReader? _reader;
  SerialPortConfig? _config;
  NtripClient? _ntrip;
  Timer? _ggaTimer;
  RtkPosition? _last;
  StreamSubscription<Uint8List>? _readerSub;

  /// Dostępne porty z opisem (do wyboru w UI). Bezpieczne — nie otwiera portu.
  static List<({String name, String? description})> portsWithInfo() {
    final out = <({String name, String? description})>[];
    for (final name in SerialPort.availablePorts) {
      final p = SerialPort(name);
      String? d;
      try {
        d = p.description;
      } catch (_) {/* metadane niedostępne */}
      p.dispose();
      out.add((name: name, description: d));
    }
    return out;
  }

  // Cała ścieżka łączenia jest synchroniczna (libserialport) — [epoch] nie
  // zdąży się zmienić w trakcie, więc nie wymaga sprawdzeń jak w BLE/USB.
  @override
  Future<void> connect(StreamController<RtkPosition> ctrl, int epoch) async {
    try {
      final ports = SerialPort.availablePorts;
      if (ports.isEmpty) {
        ctrl.addError(StateError(
            'Brak portów COM. Podłącz odbiornik kablem USB i poczekaj na '
            'sterownik (CP210x/CH340).'));
        return;
      }
      final chosen = portName ?? ports.first;
      if (!ports.contains(chosen)) {
        ctrl.addError(StateError(
            'Port $chosen nie jest dostępny (odłączony?). Dostępne: '
            '${ports.join(', ')}.'));
        return;
      }
      _status.add('Otwieram port $chosen…');
      final port = SerialPort(chosen);
      _port = port;
      if (!port.openReadWrite()) {
        final err = SerialPort.lastError;
        ctrl.addError(StateError(
            'Nie udało się otworzyć $chosen'
            '${err != null ? ': ${err.message}' : ' (zajęty przez inny program?)'}.'));
        return;
      }
      _config = SerialPortConfig()
        ..baudRate = AppSettings.instance.usbBaud
        ..bits = 8
        ..stopBits = 1
        ..parity = SerialPortParity.none
        ..setFlowControl(SerialPortFlowControl.none);
      port.config = _config!;

      final reader = SerialPortReader(port);
      _reader = reader;
      _readerSub = reader.stream.listen(
        (bytes) => _onNmeaBytes(bytes, ctrl),
        onError: (Object e) {
          if (!ctrl.isClosed) ctrl.addError(e);
        },
      );
      _status.add('Połączono ($chosen, ${AppSettings.instance.usbBaud} bps)');
      _maybeStartNtrip();
    } catch (e) {
      if (!ctrl.isClosed) ctrl.addError(e);
    }
  }

  // Buforowanie strumienia w linie NMEA — identyczne jak w BLE/USB.
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

  Future<void> _writeRtcm(List<int> rtcm) async {
    final port = _port;
    if (port == null) return;
    try {
      port.write(Uint8List.fromList(rtcm), timeout: 1000);
    } catch (_) {/* port zniknął — disconnect posprząta */}
  }

  @override
  Future<void> disconnect() async {
    _ggaTimer?.cancel();
    _ggaTimer = null;
    await _ntrip?.stop();
    _ntrip = null;
    await _readerSub?.cancel();
    _readerSub = null;
    try {
      _reader?.close();
    } catch (_) {}
    _reader = null;
    try {
      _port?.close();
    } catch (_) {}
    try {
      _port?.dispose();
    } catch (_) {}
    _port = null;
    try {
      _config?.dispose();
    } catch (_) {}
    _config = null;
    _lineBuf.clear();
  }
}
