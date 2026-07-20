import 'package:flutter_test/flutter_test.dart';

import 'package:gps_rtk_app/models/rtk_position.dart';
import 'package:gps_rtk_app/rtk/nmea_parser.dart';

/// Dolicza poprawną sumę kontrolną do treści zdania (bez `$`).
String _nmea(String body) {
  var x = 0;
  for (final c in body.codeUnits) {
    x ^= c;
  }
  final hex = x.toRadixString(16).toUpperCase().padLeft(2, '0');
  return '\$$body*$hex';
}

void main() {
  test('klasyczna GGA (znana suma *47) parsuje pozycję i fix', () {
    final p = NmeaParser().addLine(
      r'$GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,*47',
    );
    expect(p, isNotNull);
    expect(p!.latitude, closeTo(48.1173, 1e-3));
    expect(p.longitude, closeTo(11.5167, 1e-3));
    expect(p.fixType, FixType.gps);
    expect(p.satellites, 8);
    expect(p.altitude, closeTo(545.4, 1e-3));
  });

  test('zła suma kontrolna → odrzucone', () {
    final p = NmeaParser().addLine(
      r'$GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,*00',
    );
    expect(p, isNull);
  });

  test('współrzędne poza zakresem (uszkodzone zdanie) → null', () {
    // lat 99°53' = 99,88° > 90° (np. sklejone/uszkodzone bajty po USB).
    // Musi zostać odrzucone — inaczej mapa dostaje śmieci (lat 1054°) i
    // flutter_map wywala asercję LatLngBounds.
    final p = NmeaParser().addLine(_nmea(
        'GNGGA,120000.00,9953.000000,N,02000.000000,E,1,08,1.0,250.0,M,40,M,,0000'));
    expect(p, isNull);
  });

  test('fix=4 → RTK Fixed, fix=5 → RTK Float', () {
    final fixed = NmeaParser().addLine(
        _nmea('GNGGA,120000.00,5000.000000,N,02000.000000,E,4,18,0.7,250.0,M,40,M,1.0,0000'));
    expect(fixed!.fixType, FixType.rtkFixed);
    final float = NmeaParser().addLine(
        _nmea('GNGGA,120000.00,5000.000000,N,02000.000000,E,5,18,0.7,250.0,M,40,M,1.0,0000'));
    expect(float!.fixType, FixType.rtkFloat);
  });

  test('GST przed GGA ustawia dokładność (RMS stdLat/stdLon)', () {
    final parser = NmeaParser();
    // stdLat=0.03, stdLon=0.04 → RMS = 0.05 m
    parser.addLine(_nmea('GNGST,120000.00,0.05,0.04,0.03,12,0.03,0.04,0.06'));
    final p = parser.addLine(
        _nmea('GNGGA,120000.00,5000.000000,N,02000.000000,E,4,18,0.7,250.0,M,40,M,1.0,0000'));
    expect(p!.accuracy, closeTo(0.05, 1e-6));
  });

  test('bez GST — dokładność szacowana z fixa (RTK Fixed ~ cm)', () {
    final p = NmeaParser().addLine(
        _nmea('GNGGA,120000.00,5000.000000,N,02000.000000,E,4,18,1.0,250.0,M,40,M,1.0,0000'));
    expect(p!.accuracy, lessThan(0.1)); // centymetry, nie metry
  });

  test('RMC ustawia kurs, GGA go przenosi', () {
    final parser = NmeaParser();
    parser.addLine(_nmea('GNRMC,120000.00,A,5000.0,N,02000.0,E,0.5,87.5,140626,,,A'));
    final p = parser.addLine(
        _nmea('GNGGA,120000.00,5000.000000,N,02000.000000,E,4,18,0.7,250.0,M,40,M,1.0,0000'));
    expect(p!.heading, closeTo(87.5, 1e-6));
  });

  // Zgubione bajty na USB (460800 bps) ucinają linię razem z `*HH`. Taka
  // linia NIE może przejść bez weryfikacji — przekłamane cyfry współrzędnych
  // w zakresie ±90/±180 dawały „odskok" pozycji przy pokazywanym RTK Fixed.
  test('GGA bez sumy kontrolnej (ucięta linia) → odrzucona', () {
    final p = NmeaParser().addLine(
        r'$GNGGA,120000.00,5000.000000,N,02000.000000,E,4,18,0.7,250.0,M,40,M,1.0,0000');
    expect(p, isNull);
  });

  test('GGA z przekłamaną szerokością i uciętą sumą → odrzucona', () {
    // Poprawne zdanie, w którym transmisja przekłamała cyfrę (50→51) i ucięła
    // końcówkę — bez wymogu `*HH` parser by to przyjął jako skok o ~111 km.
    final p = NmeaParser().addLine(
        r'$GNGGA,120000.00,5100.000000,N,02000.000000,E,4,18,0.7,250.0,M,40,M,1.0');
    expect(p, isNull);
  });

  // LC29HEA nie wysyła GST — realną estymatę błędu daje $PQTMEPE (EPE_2D).
  test('PQTMEPE ustawia dokładność dla kolejnej GGA', () {
    final parser = NmeaParser();
    // MsgVer=2, N=0.03, E=0.04, D=0.06, 2D=0.05, 3D=0.08
    parser.addLine(_nmea('PQTMEPE,2,0.03,0.04,0.06,0.05,0.08'));
    final p = parser.addLine(_nmea(
        'GNGGA,120000.00,5000.000000,N,02000.000000,E,4,18,0.7,250.0,M,40,M,1.0,0000'));
    expect(p!.accuracy, closeTo(0.05, 1e-6));
  });

  test('uszkodzone PQTMEPE nie psuje dokładności', () {
    final parser = NmeaParser();
    parser.addLine(_nmea('PQTMEPE,2,x,y,z')); // za krótkie / nie-liczby
    final p = parser.addLine(_nmea(
        'GNGGA,120000.00,5000.000000,N,02000.000000,E,4,18,1.0,250.0,M,40,M,1.0,0000'));
    expect(p!.accuracy, lessThan(0.1)); // fallback: szacunek z fixa+HDOP
  });

  test('buildNmeaCommand dolicza sumę kontrolną i CRLF', () {
    // Klasyczne zdanie o znanej sumie *47.
    expect(
      buildNmeaCommand(
          'GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,'),
      '\$GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,*47\r\n',
    );
    expect(enableEpeCommand, startsWith(r'$PQTMCFGMSGRATE,W,PQTMEPE,1,2*'));
    expect(enableEpeCommand, endsWith('\r\n'));
  });

  test('śmieci i niepełne zdania nie wywracają parsera', () {
    final parser = NmeaParser();
    expect(parser.addLine(''), isNull);
    expect(parser.addLine('losowy tekst'), isNull);
    expect(parser.addLine(r'$GNGGA,niepełne'), isNull);
  });
}
