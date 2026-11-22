// Basemap providers + the map style (same providers as the web version).
import 'dart:convert';

enum Basemap { google, esri, street }

class BasemapInfo {
  final String label;
  final List<String> tiles;
  final int maxNativeZoom;
  const BasemapInfo(this.label, this.tiles, this.maxNativeZoom);
}

const Map<Basemap, BasemapInfo> basemaps = {
  Basemap.google: BasemapInfo('Google Satellite', [
    'https://mt0.google.com/vt/lyrs=s&x={x}&y={y}&z={z}',
    'https://mt1.google.com/vt/lyrs=s&x={x}&y={y}&z={z}',
    'https://mt2.google.com/vt/lyrs=s&x={x}&y={y}&z={z}',
    'https://mt3.google.com/vt/lyrs=s&x={x}&y={y}&z={z}',
  ], 20),
  Basemap.esri: BasemapInfo('Esri Satellite', [
    'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
  ], 19),
  Basemap.street: BasemapInfo('Street (OpenStreetMap)', [
    'https://a.tile.openstreetmap.org/{z}/{x}/{y}.png',
    'https://b.tile.openstreetmap.org/{z}/{x}/{y}.png',
    'https://c.tile.openstreetmap.org/{z}/{x}/{y}.png',
  ], 19),
};

String basemapLayerId(Basemap b) => 'bm-${b.name}';

/// Style JSON: one raster source + layer per basemap, only the first visible.
String buildStyle() {
  final sources = <String, dynamic>{};
  final layers = <Map<String, dynamic>>[
    {'id': 'bg', 'type': 'background', 'paint': {'background-color': '#1b1b1b'}},
  ];
  for (final b in Basemap.values) {
    final info = basemaps[b]!;
    sources[basemapLayerId(b)] = {
      'type': 'raster',
      'tiles': info.tiles,
      'tileSize': 256,
      'maxzoom': info.maxNativeZoom,
    };
    layers.add({
      'id': basemapLayerId(b),
      'type': 'raster',
      'source': basemapLayerId(b),
      'layout': {'visibility': b == Basemap.google ? 'visible' : 'none'},
      'paint': {'raster-fade-duration': 150},
    });
  }
  return jsonEncode({
    'version': 8,
    // Only needed for the FAT name labels (zoom 17+).
    'glyphs': 'https://protomaps.github.io/basemaps-assets/fonts/{fontstack}/{range}.pbf',
    'sources': sources,
    'layers': layers,
  });
}
