import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

/// Warstwy podkładowe mapy dostępne w aplikacji.
enum MapBaseLayer {
  osm('Mapa (OSM)', Icons.map_outlined),
  ortoGugik('Ortofoto GUGiK', Icons.satellite_alt_outlined),
  esri('Zdjęcia satelitarne (Esri)', Icons.public);

  const MapBaseLayer(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// Współdzielony wybór warstwy — dzięki temu po przejściu z mapy głównej
/// do ekranu tyczenia podkład pozostaje ten sam.
final ValueNotifier<MapBaseLayer> activeBaseLayer =
    ValueNotifier(MapBaseLayer.ortoGugik);

/// Czy nakładka uzbrojenia terenu (KIUT) jest włączona (niezależnie od podkładu).
final ValueNotifier<bool> utilitiesOverlayEnabled = ValueNotifier(false);

/// Czy nakładka budynków (EGiB, KIEG) jest włączona.
final ValueNotifier<bool> buildingsOverlayEnabled = ValueNotifier(false);

const _userAgent = 'pl.gpsrtk.gps_rtk_app';

/// Nakładka uzbrojenia terenu — WMS KIUT (GUGiK) w EPSG:3857, przezroczyste PNG.
/// Warstwy: wodociąg, kanalizacja, gaz, energetyka. Podgląd istniejących sieci;
/// kafelki są cache'owane (działają offline po obejrzeniu).
TileLayer buildUtilitiesOverlay() {
  return TileLayer(
    wmsOptions: WMSTileLayerOptions(
      baseUrl: 'https://integracja.gugik.gov.pl/cgi-bin/'
          'KrajowaIntegracjaUzbrojeniaTerenu?',
      layers: const [
        'przewod_wodociagowy',
        'przewod_kanalizacyjny',
        'przewod_gazowy',
        'przewod_elektroenergetyczny',
      ],
      format: 'image/png',
      version: '1.1.1',
      transparent: true,
    ),
    userAgentPackageName: _userAgent,
    maxNativeZoom: 21,
  );
}

/// Warstwa mapy wstawiana do `FlutterMap` — renderuje nakładkę KIUT, gdy włączona.
class UtilitiesOverlay extends StatelessWidget {
  const UtilitiesOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: utilitiesOverlayEnabled,
      builder: (context, on, _) =>
          on ? buildUtilitiesOverlay() : const SizedBox.shrink(),
    );
  }
}

/// Nakładka budynków — WMS KIEG (GUGiK) w EPSG:3857, przezroczyste PNG.
TileLayer buildBuildingsOverlay() {
  return TileLayer(
    wmsOptions: WMSTileLayerOptions(
      baseUrl: 'https://integracja.gugik.gov.pl/cgi-bin/'
          'KrajowaIntegracjaEwidencjiGruntow?',
      layers: const ['budynki'],
      format: 'image/png',
      version: '1.1.1',
      transparent: true,
    ),
    userAgentPackageName: _userAgent,
    maxNativeZoom: 21,
  );
}

/// Warstwa mapy renderująca nakładkę budynków (KIEG), gdy włączona.
class BuildingsOverlay extends StatelessWidget {
  const BuildingsOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: buildingsOverlayEnabled,
      builder: (context, on, _) =>
          on ? buildBuildingsOverlay() : const SizedBox.shrink(),
    );
  }
}

/// Buduje warstwę kafelków dla wybranego podkładu.
TileLayer buildBaseTileLayer(MapBaseLayer layer) {
  switch (layer) {
    case MapBaseLayer.osm:
      return TileLayer(
        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        userAgentPackageName: _userAgent,
        maxNativeZoom: 19,
      );
    case MapBaseLayer.ortoGugik:
      // Ortofotomapa GUGiK przez WMS (GetMap) w EPSG:3857. WMS renderuje obraz
      // na żądanie w rozdzielczości kafelka, więc jest ostry przy dużym
      // przybliżeniu. (WMTS StandardResolution miał dane tylko do ~z18 i powyżej
      // rozmazywał; HighResolution istnieje wyłącznie w siatce EPSG:2180 —
      // wymagałby osobnego CRS, patrz uwaga niżej.)
      return TileLayer(
        wmsOptions: WMSTileLayerOptions(
          baseUrl: 'https://mapy.geoportal.gov.pl/wss/service/PZGIK/ORTO/WMS/'
              'StandardResolution?',
          layers: const ['Raster'],
          format: 'image/jpeg',
          version: '1.1.1',
          transparent: false,
        ),
        userAgentPackageName: _userAgent,
        maxNativeZoom: 21,
      );
    case MapBaseLayer.esri:
      return TileLayer(
        urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/'
            'World_Imagery/MapServer/tile/{z}/{y}/{x}',
        userAgentPackageName: _userAgent,
        maxNativeZoom: 19,
      );
  }
}

/// Wymagana informacja o źródle danych dla danego podkładu.
String baseLayerAttribution(MapBaseLayer layer) {
  switch (layer) {
    case MapBaseLayer.osm:
      return '© OpenStreetMap';
    case MapBaseLayer.ortoGugik:
      return 'Źródło: GUGiK';
    case MapBaseLayer.esri:
      return 'Esri, Maxar, Earthstar Geographics';
  }
}

/// Pływający przycisk wyboru warstwy (nakładany na mapę, prawy górny róg).
class BaseLayerControl extends StatelessWidget {
  const BaseLayerControl({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 3,
      borderRadius: BorderRadius.circular(8),
      color: scheme.surface,
      child: ValueListenableBuilder<MapBaseLayer>(
        valueListenable: activeBaseLayer,
        builder: (context, current, _) => ValueListenableBuilder<bool>(
          valueListenable: utilitiesOverlayEnabled,
          builder: (context, util, _) => PopupMenuButton<String>(
            tooltip: 'Warstwy mapy',
            icon: Icon(current.icon),
            onSelected: (v) {
              if (v == 'overlay:kiut') {
                utilitiesOverlayEnabled.value = !utilitiesOverlayEnabled.value;
              } else if (v == 'overlay:budynki') {
                buildingsOverlayEnabled.value =
                    !buildingsOverlayEnabled.value;
              } else {
                activeBaseLayer.value =
                    MapBaseLayer.values.byName(v.substring('base:'.length));
              }
            },
            itemBuilder: (context) => [
              for (final l in MapBaseLayer.values)
                PopupMenuItem(
                  value: 'base:${l.name}',
                  child: Row(
                    children: [
                      Icon(
                        l == current
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Icon(l.icon, size: 18),
                      const SizedBox(width: 8),
                      Text(l.label),
                    ],
                  ),
                ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'overlay:kiut',
                child: Row(
                  children: [
                    Icon(
                      util ? Icons.check_box : Icons.check_box_outline_blank,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.account_tree_outlined, size: 18),
                    const SizedBox(width: 8),
                    const Text('Uzbrojenie (KIUT)'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'overlay:budynki',
                child: Row(
                  children: [
                    Icon(
                      buildingsOverlayEnabled.value
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.home_work_outlined, size: 18),
                    const SizedBox(width: 8),
                    const Text('Budynki (KIEG)'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Etykieta ze źródłem danych aktualnego podkładu (nakładana na mapę).
class BaseLayerAttributionLabel extends StatelessWidget {
  const BaseLayerAttributionLabel({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<MapBaseLayer>(
      valueListenable: activeBaseLayer,
      builder: (context, current, _) => DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Text(
            baseLayerAttribution(current),
            style: const TextStyle(color: Colors.white, fontSize: 11),
          ),
        ),
      ),
    );
  }
}
