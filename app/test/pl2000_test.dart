import 'package:flutter_test/flutter_test.dart';

import 'package:gps_rtk_app/utils/pl2000.dart';

void main() {
  test('zoneFor dobiera strefę po długości geograficznej', () {
    expect(Pl2000.zoneFor(20.6156), 7); // lon0 21°, EPSG:2178
    expect(Pl2000.zoneFor(15.0), 5);
    expect(Pl2000.zoneFor(18.0), 6);
    expect(Pl2000.zoneFor(24.0), 8);
  });

  test('transformacja zgodna z referencją ULDK (działka 222/1, EPSG:2178)', () {
    // Punkt 1 z dane/dzialka_222_1.csv: GUGiK ULDK srid=2178 zwrócił
    // easting=7472403.68, northing=5528944.91 dla tych współrzędnych.
    final r = Pl2000.fromLatLon(49.8961851053933, 20.6158876571654);
    expect(r.zone, 7);
    expect(r.easting, closeTo(7472403.68, 0.2));
    expect(r.northing, closeTo(5528944.91, 0.2));
  });

  test('drugi punkt działki też się zgadza', () {
    // Punkt 2: easting=7472441.18, northing=5528994.82.
    final r = Pl2000.fromLatLon(49.8966355793539, 20.6164060487422);
    expect(r.easting, closeTo(7472441.18, 0.2));
    expect(r.northing, closeTo(5528994.82, 0.2));
  });
}
