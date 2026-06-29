import 'package:flutter_test/flutter_test.dart';

import 'package:gps_rtk_app/map/base_layers.dart';

void main() {
  test('warstwy mają poprawne źródła (XYZ / WMS)', () {
    expect(
      buildBaseTileLayer(MapBaseLayer.osm).urlTemplate,
      contains('tile.openstreetmap.org'),
    );

    // Ortofoto GUGiK przez WMS (GetMap), nie XYZ — renderowane w EPSG:3857,
    // serwis StandardResolution, warstwa „Raster".
    final orto = buildBaseTileLayer(MapBaseLayer.ortoGugik);
    expect(orto.urlTemplate, isNull, reason: 'ortofoto używa WMS, nie szablonu XYZ');
    expect(orto.wmsOptions, isNotNull);
    expect(orto.wmsOptions!.baseUrl, contains('mapy.geoportal.gov.pl'));
    expect(orto.wmsOptions!.baseUrl, contains('StandardResolution'));
    expect(orto.wmsOptions!.layers, contains('Raster'));

    expect(
      buildBaseTileLayer(MapBaseLayer.esri).urlTemplate,
      contains('server.arcgisonline.com'),
    );
  });

  test('każda warstwa ma niepustą informację o źródle', () {
    for (final l in MapBaseLayer.values) {
      expect(baseLayerAttribution(l), isNotEmpty);
    }
  });

  test('domyślny podkład to ortofoto', () {
    expect(activeBaseLayer.value, MapBaseLayer.ortoGugik);
  });
}
