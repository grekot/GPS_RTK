// ignore_for_file: avoid_print  — narzędzie diagnostyczne (CLI), print celowy.
// Diagnostyka odbiornika RTK po porcie szeregowym (desktop). Otwiera port,
// czyta NMEA i raportuje: fix + **pasma anteny** (ile satelitów ze SNR>0 jest
// śledzonych na L1 vs L5) — odpowiedź na pytanie „czy antena jest L1+L5".
// Wymaga otwartego nieba (inaczej za mało satelitów, by zobaczyć L5).
//
// Uruchom (domyślnie COM3 @ 460800):
//   flutter run -d windows -t tool/serial_probe.dart
//   flutter run -d windows -t tool/serial_probe.dart --dart-entrypoint-args COM5,115200
import 'dart:async';
import 'dart:io';

import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:gps_rtk_app/models/rtk_position.dart';
import 'package:gps_rtk_app/rtk/nmea_parser.dart';

Future<void> main(List<String> args) async {
  final parts = args.isNotEmpty ? args.first.split(',') : <String>[];
  final portName = parts.isNotEmpty && parts[0].isNotEmpty ? parts[0] : 'COM3';
  final baud = parts.length > 1 ? int.tryParse(parts[1]) ?? 460800 : 460800;

  Timer(const Duration(seconds: 30), () {
    print('⏱ watchdog — kończę.');
    exit(3);
  });

  print('=== Sonda RTK: pasma anteny (L1 / L5) ===');
  try {
    print('Dostępne porty: ${SerialPort.availablePorts}');
  } catch (e) {
    print('Nie mogę odczytać portów (libserialport): $e');
    exit(1);
  }
  print('Port $portName @ $baud bps. Najlepiej pod otwartym niebem.\n');

  final port = SerialPort(portName);
  if (!port.openReadWrite()) {
    print('Nie udało się otworzyć $portName: '
        '${SerialPort.lastError?.message ?? 'zajęty?'}');
    exit(1);
  }
  port.config = SerialPortConfig()
    ..baudRate = baud
    ..bits = 8
    ..stopBits = 1
    ..parity = SerialPortParity.none
    ..setFlowControl(SerialPortFlowControl.none);

  final parser = NmeaParser();
  final buf = StringBuffer();
  var valid = 0;
  RtkPosition? last;
  final l1 = <String>{}, l2 = <String>{}, l5 = <String>{};
  final seen = <String>{}; // „talker:sigId" — do podglądu

  final reader = SerialPortReader(port);
  final sub = reader.stream.listen((bytes) {
    buf.write(String.fromCharCodes(bytes));
    var rest = buf.toString();
    int nl;
    while ((nl = rest.indexOf('\n')) != -1) {
      final line = rest.substring(0, nl).trim();
      rest = rest.substring(nl + 1);
      if (!line.startsWith(r'$') || !line.contains('*')) continue;
      valid++;
      final pos = parser.addLine(line);
      if (pos != null) last = pos;
      if (line.length > 6 && line.substring(3, 6) == 'GSV') {
        _accumGsv(line, l1, l2, l5, seen);
      }
    }
    buf
      ..clear()
      ..write(rest);
  }, onError: (Object e) => print('błąd strumienia: $e'));

  // Krótka kontrola, czy w ogóle leci NMEA.
  await Future<void>.delayed(const Duration(seconds: 3));
  if (valid == 0) {
    await sub.cancel();
    print('Brak poprawnego NMEA. Sprawdź port/baud, kabel danych, tryb USB-C.');
    exit(2);
  }
  print('NMEA leci — zbieram dane o pasmach (10 s)…');
  await Future<void>.delayed(const Duration(seconds: 10));
  await sub.cancel();

  final p = last;
  print('\n--- WYNIK ---');
  if (p != null) {
    print('Fix: ${fixLabel(p.fixType)}   sat=${p.satellites ?? '?'}   '
        'dokł=${p.accuracy.toStringAsFixed(2)} m');
  }
  print('Śledzone satelity ze SNR>0 wg pasma:');
  print('  L1 (~1575 MHz): ${l1.length}');
  print('  L2 (~1227 MHz): ${l2.length}');
  print('  L5 (~1176 MHz): ${l5.length}');
  final ids = seen.toList()..sort();
  print('Wykryte ID sygnałów (talker:id): $ids');
  print('');
  if (l5.isNotEmpty) {
    print('✓ ANTENA PRZEPUSZCZA L5 → to antena DUAL-BAND (L1+L5).');
  } else if (l1.isNotEmpty) {
    print('✗ Widać L1, ale ZERO L5 → antena prawdopodobnie TYLKO L1.');
    print('  (Upewnij się, że testujesz pod otwartym niebem — bez satelitów');
    print('   L5 w zasięgu wynik może być fałszywie negatywny.)');
  } else {
    print('? Za mało danych GSV (mało satelitów). Testuj pod gołym niebem.');
  }
  exit(0);
}

/// Pasmo dla (talker, signalId) wg NMEA 0183 v4.11. L5 ≈ 1176 MHz
/// (GPS L5 / Galileo E5a / QZSS L5 / BeiDou B2a). GLONASS nie ma L5.
String? _band(String talker, int s) {
  switch (talker) {
    case 'GP': // GPS
    case 'GQ': // QZSS (jak GPS)
      if (s == 1 || s == 2 || s == 3) return 'L1';
      if (s == 4 || s == 5 || s == 6) return 'L2';
      if (s == 7 || s == 8) return 'L5';
      return null;
    case 'GL': // GLONASS — brak L5
      if (s == 1 || s == 2) return 'L1';
      if (s == 3 || s == 4) return 'L2';
      return null;
    case 'GA': // Galileo: E5a=1 (L5), E5b=2, E1=7 (L1)
      if (s == 1) return 'L5';
      if (s == 7) return 'L1';
      return 'other';
    case 'GB': // BeiDou (orientacyjnie): B1=1/2/8, B2a≈5
      if (s == 1 || s == 2 || s == 8) return 'L1';
      if (s == 5) return 'L5';
      return 'other';
  }
  return null;
}

/// Zlicza satelity ze SNR>0 z jednego zdania GSV do koszyków pasm.
void _accumGsv(String line, Set<String> l1, Set<String> l2, Set<String> l5,
    Set<String> seen) {
  try {
    final f = line.split(',');
    if (f.length < 8) return;
    final talker = line.substring(1, 3); // GP/GL/GA/GB/GQ
    // signalId = ostatnie pole (przed *CS), zapis szesnastkowy.
    final hasSig = ((f.length - 4) % 4) == 1;
    if (!hasSig) return; // stary NMEA bez signalId — nie sklasyfikujemy pasma
    final sigId = int.tryParse(f.last.split('*').first.trim(), radix: 16);
    if (sigId == null) return;
    seen.add('$talker:$sigId');
    final band = _band(talker, sigId);
    if (band == null || band == 'other') return;
    // Grupy po 4 pola (sat,elew,azym,SNR); ostatnie pole to signalId.
    for (var i = 4; i + 3 <= f.length - 2; i += 4) {
      final satNum = f[i].trim();
      final snr = double.tryParse(f[i + 3].split('*').first.trim());
      if (satNum.isEmpty || snr == null || snr <= 0) continue;
      final key = '$talker$satNum';
      if (band == 'L1') l1.add(key);
      if (band == 'L2') l2.add(key);
      if (band == 'L5') l5.add(key);
    }
  } catch (_) {/* uszkodzone zdanie — pomiń */}
}
