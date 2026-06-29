import 'package:geolocator/geolocator.dart';

import '../models/rtk_position.dart';
import 'position_source.dart';

/// Pozycja z wbudowanego odbiornika GNSS telefonu (dokładność rzędu metrów).
/// Tryb deweloperski / awaryjny — docelowym źródłem jest odbiornik RTK.
class PhoneGnssSource implements PositionSource {
  @override
  String get name => 'GPS telefonu';

  @override
  Stream<RtkPosition> positions() async* {
    await _ensurePermission();
    yield* Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
      ),
    ).map(
      (p) => RtkPosition(
        latitude: p.latitude,
        longitude: p.longitude,
        altitude: p.altitude,
        accuracy: p.accuracy,
        fixType: FixType.gps,
        heading: p.heading > 0 ? p.heading : null,
        timestamp: p.timestamp,
      ),
    );
  }

  Future<void> _ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw StateError('Lokalizacja w telefonie jest wyłączona.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw StateError('Brak zgody na dostęp do lokalizacji.');
    }
  }
}
