import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../models/building.dart';
import '../models/parcel.dart';

class UldkException implements Exception {
  final String message;
  UldkException(this.message);

  @override
  String toString() => message;
}

/// Klient usługi ULDK (Usługa Lokalizacji Działek Katastralnych, GUGiK).
/// Dokumentacja: https://uldk.gugik.gov.pl/opis.html
class UldkService {
  static const _base = 'https://uldk.gugik.gov.pl/';
  static const _resultFields = 'geom_wkt,id,numer,region,gmina,powiat';

  final http.Client _client;

  UldkService([http.Client? client]) : _client = client ?? http.Client();

  /// Wyszukuje działki po pełnym identyfikatorze TERYT
  /// (np. "120205_2.0001.222/1") lub po "obręb numer" (np. "Gnojnik 222/1").
  /// Może zwrócić więcej niż jedną działkę (obręby o tej samej nazwie).
  Future<List<Parcel>> findByIdOrNumber(String query) async {
    final body =
        await _get({'request': 'GetParcelByIdOrNr', 'id': query.trim()});
    return parseResponse(body);
  }

  /// Zwraca działkę, na której leży wskazany punkt (WGS84).
  /// Uwaga: ten endpoint przyjmuje współrzędne w parametrze `xy`, nie `id`.
  Future<Parcel> findByPoint(double longitude, double latitude) async {
    final body = await _get(
      {'request': 'GetParcelByXY', 'xy': '$longitude,$latitude,4326'},
    );
    final parcels = parseResponse(body);
    return parcels.first;
  }

  /// Zwraca obrys budynku, na którym leży wskazany punkt (WGS84).
  Future<Building> findBuildingByXY(double longitude, double latitude) async {
    final body = await _get(
      {'request': 'GetBuildingByXY', 'xy': '$longitude,$latitude,4326'},
      result: 'geom_wkt,id',
    );
    return parseBuilding(body);
  }

  Future<String> _get(
    Map<String, String> params, {
    String result = _resultFields,
  }) async {
    final uri = Uri.parse(_base).replace(queryParameters: {
      ...params,
      'result': result,
      'srid': '4326',
    });
    final http.Response response;
    try {
      response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      throw UldkException('Brak połączenia z usługą ULDK ($e).');
    }
    if (response.statusCode != 200) {
      throw UldkException('Usługa ULDK zwróciła błąd HTTP ${response.statusCode}.');
    }
    return response.body;
  }

  /// Parsuje tekstową odpowiedź ULDK. Pierwsza linia to status — wartość
  /// ujemna z komunikatem oznacza błąd (np. "-1 brak wyników"), nieujemna
  /// sukces (GetParcelByIdOrNr zwraca liczbę rekordów, GetParcelByXY "0").
  /// Kolejne linie to rekordy rozdzielane "|" w kolejności pól
  /// z [_resultFields].
  static List<Parcel> parseResponse(String body) =>
      [for (final r in records(body)) _parseRecord(r)];

  /// Parsuje odpowiedź z budynkiem (pola: geom_wkt, id).
  static Building parseBuilding(String body) {
    final fields = records(body).first.split('|');
    return Building(
      points: parseWktPolygon(fields[0]),
      id: fields.length > 1 ? fields[1] : '',
      fetchedAt: DateTime.now(),
    );
  }

  /// Wydziela rekordy z odpowiedzi ULDK. Pierwsza linia to status — wartość
  /// ujemna z komunikatem oznacza błąd (np. "-1 brak wyników"), nieujemna
  /// sukces (liczba rekordów lub "0"). Rzuca [UldkException] przy braku wyników.
  static List<String> records(String body) {
    final lines = body
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) {
      throw UldkException('Pusta odpowiedź usługi ULDK.');
    }
    final statusLine = lines.first;
    final status = int.tryParse(statusLine.split(RegExp(r'\s+')).first);
    List<String> recs;
    if (status == null) {
      recs = lines; // odpowiedź bez linii statusu
    } else if (status < 0) {
      final reason = statusLine.replaceFirst(RegExp(r'^-?\d+\s*'), '');
      throw UldkException(
        reason.isEmpty
            ? 'Nie znaleziono obiektu.'
            : 'Nie znaleziono ($reason).',
      );
    } else {
      recs = lines.sublist(1);
    }
    if (recs.isEmpty) {
      throw UldkException('Nie znaleziono obiektu.');
    }
    return recs;
  }

  static Parcel _parseRecord(String record) {
    final fields = record.split('|');
    if (fields.length < 6) {
      throw UldkException('Nieoczekiwany format odpowiedzi ULDK: "$record".');
    }
    return Parcel(
      points: parseWktPolygon(fields[0]),
      id: fields[1],
      number: fields[2],
      region: fields[3],
      commune: fields[4],
      county: fields[5],
      fetchedAt: DateTime.now(),
    );
  }

  /// Wyciąga zewnętrzny pierścień z geometrii WKT POLYGON
  /// (np. "SRID=4326;POLYGON((20.61 49.89,20.62 49.89,...))").
  static List<LatLng> parseWktPolygon(String wkt) {
    final match = RegExp(r'POLYGON\s*\(\(([^)]+)').firstMatch(wkt);
    if (match == null) {
      throw UldkException('Nieobsługiwany typ geometrii działki.');
    }
    return match.group(1)!.split(',').map((pair) {
      final xy = pair.trim().split(RegExp(r'\s+'));
      return LatLng(double.parse(xy[1]), double.parse(xy[0]));
    }).toList();
  }
}
