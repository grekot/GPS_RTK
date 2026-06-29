import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../models/device_telemetry.dart';
import '../models/rtk_position.dart';
import '../rtk/nmea_parser.dart';
import '../rtk/ntrip_client.dart';
import '../services/app_settings.dart';
import 'position_source.dart';

// Nordic UART Service (kontrakt z firmware ESP32).
const _nusService = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
const _nusTx = '6e400003-b5a3-f393-e0a9-e50e24dcca9e'; // notify: NMEA z urządzenia
const _nusRx = '6e400002-b5a3-f393-e0a9-e50e24dcca9e'; // write: RTCM do urządzenia
// Telemetria „status" — rozszerzenie poza NUS (Read+Notify, JSON co 1 s).
// Opcjonalna: most działa bez niej (build SPP / starszy firmware jej nie ma).
const _statusChar = '6e400004-b5a3-f393-e0a9-e50e24dcca9e';

/// Odbiornik RTK (ESP32 + LC29HEA) po BLE — usługa Nordic UART.
/// Po połączeniu czyta NMEA (→ [RtkPosition]) i — jeśli skonfigurowano NTRIP —
/// pobiera RTCM z castera i wpuszcza do modułu (oraz odsyła GGA do VRS).
class BleReceiverSource implements PositionSource {
  @override
  String get name => 'Odbiornik RTK (BLE)';

  /// Konfiguracja NTRIP (ustawiana z ekranu ustawień). Null = bez poprawek.
  NtripConfig? ntripConfig;

  final _status = StreamController<String>.broadcast();
  Stream<String> get statusMessages => _status.stream;

  final _telemetry = StreamController<DeviceTelemetry>.broadcast();

  /// Telemetria urządzenia (bateria, przepływ RTCM, wiek poprawek) z char.
  /// „status" `6E400004`. Pusty, gdy firmware nie wystawia tej charakterystyki.
  Stream<DeviceTelemetry> get telemetry => _telemetry.stream;

  final _parser = NmeaParser();
  final StringBuffer _lineBuf = StringBuffer();
  BluetoothDevice? _device;
  BluetoothCharacteristic? _rx;
  NtripClient? _ntrip;
  Timer? _ggaTimer;
  RtkPosition? _last;
  StreamSubscription<List<int>>? _txSub;
  StreamSubscription<List<int>>? _statusSub;

  @override
  Stream<RtkPosition> positions() {
    late final StreamController<RtkPosition> ctrl;
    ctrl = StreamController<RtkPosition>(
      onListen: () => _connect(ctrl),
      onCancel: _disconnect,
    );
    return ctrl.stream;
  }

  Future<void> _connect(StreamController<RtkPosition> ctrl) async {
    try {
      if (!await FlutterBluePlus.isSupported) {
        ctrl.addError(StateError('Bluetooth niedostępny na tym urządzeniu.'));
        return;
      }
      if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
        try {
          await FlutterBluePlus.turnOn();
        } catch (_) {/* iOS/desktop — użytkownik włącza ręcznie */}
      }

      final svc = Guid(_nusService);
      _status.add('Szukam odbiornika RTK…');
      await FlutterBluePlus.startScan(
        withServices: [svc],
        timeout: const Duration(seconds: 15),
      );
      final result = await FlutterBluePlus.onScanResults
          .expand((r) => r)
          .firstWhere((_) => true)
          .timeout(
            const Duration(seconds: 16),
            onTimeout: () => throw StateError('Nie znaleziono odbiornika RTK.'),
          );
      await FlutterBluePlus.stopScan();

      final device = result.device;
      _device = device;
      _status.add('Łączenie z ${device.platformName}…');
      await device.connect(
        license: License.nonprofit, // użytek osobisty wg licencji FlutterBluePlus
        timeout: const Duration(seconds: 15),
        mtu: 247,
      );

      final services = await device.discoverServices();
      final nus = services.firstWhere((s) => s.uuid == svc,
          orElse: () => throw StateError('Urządzenie nie ma usługi NUS.'));
      final tx =
          nus.characteristics.firstWhere((c) => c.uuid == Guid(_nusTx));
      _rx = nus.characteristics.firstWhere((c) => c.uuid == Guid(_nusRx));

      await tx.setNotifyValue(true);
      _txSub = tx.onValueReceived.listen((bytes) => _onNmeaBytes(bytes, ctrl));
      await _subscribeStatus(services);
      _status.add('Połączono z odbiornikiem');
      _maybeStartNtrip();
    } catch (e) {
      if (!ctrl.isClosed) ctrl.addError(e);
    }
  }

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

  /// Subskrybuje opcjonalną charakterystykę telemetrii „status". Brak char.
  /// (np. build SPP) nie jest błędem — most działa bez niej.
  Future<void> _subscribeStatus(List<BluetoothService> services) async {
    BluetoothCharacteristic? ch;
    for (final s in services) {
      for (final c in s.characteristics) {
        if (c.uuid == Guid(_statusChar)) ch = c;
      }
    }
    if (ch == null) return;
    try {
      await ch.setNotifyValue(true);
      _statusSub = ch.onValueReceived.listen(_onTelemetryBytes);
      // Read wartości początkowej — telemetria od razu, bez czekania na 1. notify.
      _onTelemetryBytes(await ch.read());
    } catch (_) {/* char nieczytelna na tej platformie — zostają same notify */}
  }

  void _onTelemetryBytes(List<int> bytes) {
    if (bytes.isEmpty) return;
    final t = DeviceTelemetry.tryParse(utf8.decode(bytes, allowMalformed: true));
    if (t != null && !_telemetry.isClosed) _telemetry.add(t);
  }

  void _maybeStartNtrip() {
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
    final rx = _rx;
    if (rx == null) return;
    const chunk = 180; // pod MTU 247
    for (var i = 0; i < rtcm.length; i += chunk) {
      final end = i + chunk < rtcm.length ? i + chunk : rtcm.length;
      try {
        await rx.write(rtcm.sublist(i, end), withoutResponse: true);
      } catch (_) {
        break;
      }
    }
  }

  Future<void> _disconnect() async {
    _ggaTimer?.cancel();
    _ggaTimer = null;
    await _ntrip?.stop();
    _ntrip = null;
    await _txSub?.cancel();
    _txSub = null;
    await _statusSub?.cancel();
    _statusSub = null;
    try {
      await _device?.disconnect();
    } catch (_) {}
    _device = null;
    _rx = null;
    _lineBuf.clear();
  }
}
