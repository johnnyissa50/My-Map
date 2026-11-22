// FAT Map - Flutter (Android now, iOS later from the same code).
//
// The map itself is MapLibre Native (C++/GPU). All 100k FAT points are given
// to it as GeoJSON files; the native engine clusters and draws them, so pan /
// pinch / zoom never touch Dart code.

import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'data.dart';
import 'style.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

const kGrey = Color(0xFF4A4A4A);
const kRed = Color(0xFFD50000);
const kBlue = Color(0xFF1A73E8);

// Same zoom values as the web version (MapLibre GL JS and Native share the scale).
const double kDenseZoom = 9; // clustering stops from this zoom
const double kLabelZoom = 17; // name labels appear from this zoom
const double kMaxZoom = 19;
const List<String> kSets = ['all', 'zero'];

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FAT Map',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: kBlue, useMaterial3: true),
      home: const MapScreen(),
    );
  }
}

class _Info {
  final FatPoint? fat;
  final double lat, lng;
  const _Info({this.fat, required this.lat, required this.lng});
  String get coords => '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}';
  String get title => fat?.name ?? coords;
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _style = buildStyle();
  final _startup = Stopwatch()..start();
  final _q = TextEditingController();
  final _focus = FocusNode();

  MapLibreMapController? _c;
  late final Future<FatData> _dataF;
  FatData? _data;

  bool _layersAdded = false;
  bool _ready = false;
  bool _filterOn = false;
  bool _usageOn = false;
  bool _locOk = false;
  bool _locating = false;
  Basemap _base = Basemap.google;
  String? _status = 'Reading data…';
  bool _statusError = false;
  _Info? _info;
  List<FatPoint> _suggestions = const [];

  String get _activeSet => _filterOn ? 'zero' : 'all';

  @override
  void initState() {
    super.initState();
    _dataF = loadFatData();
    _dataF.then((d) {
      if (!mounted) return;
      setState(() {
        _data = d;
        if (!_ready) _status = 'Preparing map… ${_fmt(d.points.length)} points';
      });
    }, onError: (Object e) {
      if (!mounted) return;
      setState(() {
        _status = 'Could not read data.csv: $e';
        _statusError = true;
      });
    });
    _ensureLocation(ask: true);
  }

  @override
  void dispose() {
    _q.dispose();
    _focus.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Map setup
  // ---------------------------------------------------------------------------
  Future<void> _onStyleLoaded() async {
    final c = _c;
    if (c == null || _layersAdded) return;
    _layersAdded = true;
    try {
      final d = await _dataF;
      if (!mounted) return;
      setState(() => _status = 'Drawing ${_fmt(d.points.length)} points…');
      await _addLayers(c, d);
      _ready = true;
      if (!mounted) return;
      final secs = (_startup.elapsedMilliseconds / 1000).toStringAsFixed(1);
      setState(() => _status = null);
      _toast('${_fmt(d.points.length)} points ready in ${secs}s '
          '(${_fmt(d.zeroCount)} with 0 ONTs, data ${d.parseMs} ms)');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = 'Could not draw the points: $e';
        _statusError = true;
      });
    }
  }

  Future<void> _addLayers(MapLibreMapController c, FatData d) async {
    for (final s in kSets) {
      final src = 'fat-$s';
      final vis = s == _activeSet ? 'visible' : 'none';
      await c.addSource(
        src,
        GeojsonSourceProperties(
          data: s == 'all' ? d.allUrl : d.zeroUrl, // file:// URL, read natively
          cluster: true,
          clusterMaxZoom: 8, // = kDenseZoom - 1
          clusterRadius: 60,
          maxzoom: 16,
          buffer: 32,
        ),
      );
      await c.addCircleLayer(
        src,
        'cl-$s',
        CircleLayerProperties(
          circleRadius: 12,
          circleColor: '#808080',
          circleStrokeWidth: 3,
          circleStrokeColor: '#ffffff',
          visibility: vis,
        ),
        filter: ['has', 'point_count'],
        enableInteraction: false,
      );
      // Two point layers (partner colors / usage colors): "Usage" is a
      // visibility switch, nothing is recomputed.
      for (final usage in [false, true]) {
        await c.addCircleLayer(
          src,
          '${usage ? 'pu' : 'pt'}-$s',
          CircleLayerProperties(
            circleRadius: 7,
            circleColor: ['get', usage ? 'uc' : 'c'],
            circleStrokeWidth: 2,
            circleStrokeColor: '#ffffff',
            visibility: (usage == _usageOn) ? vis : 'none',
          ),
          filter: ['!', ['has', 'point_count']],
          enableInteraction: false,
        );
      }
      await c.addSymbolLayer(
        src,
        'lb-$s',
        SymbolLayerProperties(
          textField: ['get', 'n'],
          textFont: ['literal', ['Noto Sans Medium']],
          textSize: 11,
          textAnchor: 'left',
          textOffset: ['literal', [1.1, 0.0]],
          textMaxWidth: 100,
          textAllowOverlap: true,
          textIgnorePlacement: true,
          textColor: '#000000',
          textHaloColor: '#ffffff',
          textHaloWidth: 1.6,
          visibility: vis,
        ),
        minzoom: kLabelZoom,
        filter: ['!', ['has', 'point_count']],
        enableInteraction: false,
      );
    }
    // Yellow ring around the selected FAT / searched coordinate.
    await c.addGeoJsonSource('sel', _fc(null));
    await c.addCircleLayer(
      'sel',
      'sel-ring',
      const CircleLayerProperties(
        circleRadius: 12,
        circleColor: 'rgba(0,0,0,0)',
        circleStrokeWidth: 4,
        circleStrokeColor: '#FFD400',
      ),
      enableInteraction: false,
    );
  }

  Map<String, dynamic> _fc(_Info? i) => {
        'type': 'FeatureCollection',
        'features': i == null
            ? []
            : [
                {
                  'type': 'Feature',
                  'properties': <String, dynamic>{},
                  'geometry': {
                    'type': 'Point',
                    'coordinates': [i.lng, i.lat]
                  },
                }
              ],
      };

  Future<void> _applyVisibility() async {
    final c = _c;
    if (c == null || !_ready) return;
    final futures = <Future<void>>[];
    for (final s in kSets) {
      final on = s == _activeSet;
      futures.add(c.setLayerVisibility('cl-$s', on));
      futures.add(c.setLayerVisibility('pt-$s', on && !_usageOn));
      futures.add(c.setLayerVisibility('pu-$s', on && _usageOn));
      futures.add(c.setLayerVisibility('lb-$s', on));
    }
    await Future.wait(futures);
  }

  Future<void> _setBasemap(Basemap b) async {
    final c = _c;
    if (c == null) return;
    setState(() => _base = b);
    await Future.wait([
      for (final x in Basemap.values) c.setLayerVisibility(basemapLayerId(x), x == b),
    ]);
  }

  // ---------------------------------------------------------------------------
  // Taps
  // ---------------------------------------------------------------------------
  // Android reports tap points in physical pixels, iOS in logical points.
  double get _px => Platform.isAndroid ? MediaQuery.of(context).devicePixelRatio : 1.0;

  /// Nearest rendered FAT (or cluster) within [radius] logical px of the tap.
  Future<Map<dynamic, dynamic>?> _nearest(math.Point<double> pt, LatLng ll, double radius,
      {required bool clusters}) async {
    final c = _c;
    if (c == null || !_ready) return null;
    final r = radius * _px;
    final s = _activeSet;
    final layers = [if (clusters) 'cl-$s', 'pt-$s', 'pu-$s'];
    final feats = await c.queryRenderedFeaturesInRect(
        Rect.fromLTRB(pt.x - r, pt.y - r, pt.x + r, pt.y + r), layers, null);
    Map<dynamic, dynamic>? best;
    double bestD = double.infinity;
    final k = math.cos(ll.latitude * math.pi / 180);
    for (final f in feats) {
      if (f is! Map) continue;
      final geom = f['geometry'];
      final coords = geom is Map ? geom['coordinates'] : null;
      if (coords is! List || coords.length < 2) continue;
      final dx = ((coords[0] as num).toDouble() - ll.longitude) * k;
      final dy = (coords[1] as num).toDouble() - ll.latitude;
      final dd = dx * dx + dy * dy;
      if (dd < bestD) {
        bestD = dd;
        best = f;
      }
    }
    return best;
  }

  Future<void> _onMapClick(math.Point<double> pt, LatLng ll) async {
    _hideKeyboard();
    final f = await _nearest(pt, ll, 16, clusters: true);
    if (f == null) {
      _closeInfo();
      return;
    }
    final props = (f['properties'] as Map?) ?? const {};
    if (props['cluster'] == true || props.containsKey('point_count')) {
      final coords = f['geometry']['coordinates'] as List;
      final z = await _currentZoom();
      await _c?.animateCamera(
        CameraUpdate.newLatLngZoom(
            LatLng((coords[1] as num).toDouble(), (coords[0] as num).toDouble()),
            math.min(z + 2, kMaxZoom)),
        duration: const Duration(milliseconds: 400),
      );
      return;
    }
    final p = _data?.byName[props['n']];
    if (p != null) _select(_Info(fat: p, lat: p.lat, lng: p.lng), zoom: null);
  }

  Future<void> _onMapLongClick(math.Point<double> pt, LatLng ll) async {
    if (await _nearest(pt, ll, 25, clusters: true) != null) return;
    HapticFeedback.mediumImpact();
    _select(_Info(lat: ll.latitude, lng: ll.longitude), zoom: null);
  }

  /// Zoom from the visible region (avoids streaming camera updates every frame).
  Future<double> _currentZoom() async {
    final b = await _c!.getVisibleRegion();
    var span = b.northeast.longitude - b.southwest.longitude;
    if (span <= 0) span += 360;
    final w = MediaQuery.of(context).size.width;
    return math.log(360 * w / (512 * span)) / math.ln2;
  }

  void _select(_Info info, {double? zoom}) {
    setState(() {
      _info = info;
      _suggestions = const [];
    });
    if (_ready) _c?.setGeoJsonSource('sel', _fc(info));
    if (zoom != null) {
      _c?.animateCamera(CameraUpdate.newLatLngZoom(LatLng(info.lat, info.lng), zoom),
          duration: const Duration(milliseconds: 600));
    }
  }

  void _closeInfo() {
    if (_info == null) return;
    setState(() => _info = null);
    if (_ready) _c?.setGeoJsonSource('sel', _fc(null));
  }

  // ---------------------------------------------------------------------------
  // Search
  // ---------------------------------------------------------------------------
  static final _coordRe = RegExp(r'^\s*(\d+\.\d+)\s*[,\s]\s*(\d+\.\d+)\s*$');

  void _onSearch(String text) {
    final q = text.trim().toUpperCase();
    final m = _coordRe.firstMatch(q);
    if (m != null) {
      final a = double.parse(m.group(1)!), b = double.parse(m.group(2)!);
      _hideKeyboard();
      _select(_Info(lat: math.min(a, b), lng: math.max(a, b)), zoom: 16);
      return;
    }
    final d = _data;
    if (d == null || q.isEmpty) {
      setState(() => _suggestions = const []);
      return;
    }
    final matches = d.prefixSearch(q);
    if (q.length == 19 && matches.isNotEmpty && matches.first.search == q) {
      _goToFat(matches.first);
      return;
    }
    setState(() => _suggestions = matches);
  }

  void _onSubmit(String text) {
    final q = text.trim().toUpperCase();
    final d = _data;
    if (d == null || q.isEmpty) return;
    final matches = d.prefixSearch(q, limit: 2);
    if (matches.isNotEmpty && (matches.first.search == q || matches.length == 1)) {
      _goToFat(matches.first);
    }
  }

  void _goToFat(FatPoint p) {
    _q.text = p.name;
    _q.selection = TextSelection.collapsed(offset: p.name.length);
    _hideKeyboard();
    _select(_Info(fat: p, lat: p.lat, lng: p.lng), zoom: 18);
  }

  void _hideKeyboard() {
    if (_focus.hasFocus) _focus.unfocus();
    if (_suggestions.isNotEmpty) setState(() => _suggestions = const []);
  }

  // ---------------------------------------------------------------------------
  // Location
  // ---------------------------------------------------------------------------
  Future<bool> _ensureLocation({required bool ask}) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (ask) _toast('Turn on Location (GPS) on the phone');
        return false;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied && ask) perm = await Geolocator.requestPermission();
      final ok = perm == LocationPermission.always || perm == LocationPermission.whileInUse;
      if (ok && !_locOk && mounted) setState(() => _locOk = true);
      if (!ok && ask && perm == LocationPermission.deniedForever) {
        _toast('Location permission is blocked - enable it in app settings');
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  Future<void> _locate() async {
    if (_locating) return;
    if (!await _ensureLocation(ask: true)) return;
    setState(() => _locating = true);
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        _moveTo(last.latitude, last.longitude, 16);
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (last == null ||
          Geolocator.distanceBetween(last.latitude, last.longitude, pos.latitude, pos.longitude) > 30) {
        _moveTo(pos.latitude, pos.longitude, 16);
      }
    } catch (_) {
      _toast('Could not get your location');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _moveTo(double lat, double lng, double zoom) {
    _c?.animateCamera(CameraUpdate.newLatLngZoom(LatLng(lat, lng), zoom),
        duration: const Duration(milliseconds: 600));
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------
  void _toast(String msg) {
    if (!mounted) return;
    final m = ScaffoldMessenger.of(context);
    m.hideCurrentSnackBar();
    m.showSnackBar(SnackBar(
      content: Text(msg, textAlign: TextAlign.center),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(40, 0, 40, 64),
      duration: const Duration(seconds: 4),
    ));
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    _toast('Copied ✓');
  }

  Future<void> _openInMaps(double lat, double lng) async {
    final ok = await launchUrl(Uri.parse('https://www.google.com/maps?q=$lat,$lng'),
        mode: LaunchMode.externalApplication);
    if (!ok) _toast('Could not open Google Maps');
  }

  static String _fmt(int n) {
    final s = n.toString();
    final b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final red = _filterOn || _usageOn;
    final barColor = red ? kRed : kGrey;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: barColor,
        resizeToAvoidBottomInset: false,
        body: Column(
          children: [
            Container(
              color: barColor,
              child: SafeArea(
                bottom: false,
                child: SizedBox(
                  height: 64,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        Expanded(child: _searchField()),
                        const SizedBox(width: 10),
                        _layerButton(barColor),
                        const SizedBox(width: 10),
                        _squareButton(
                          onTap: _locate,
                          active: _locating,
                          color: barColor,
                          child: Icon(Icons.my_location,
                              size: 22, color: _locating ? Colors.white : (red ? kRed : kBlue)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Container(
                decoration: red
                    ? const BoxDecoration(
                        border: Border(
                          left: BorderSide(color: Color(0xFFE00000), width: 4),
                          right: BorderSide(color: Color(0xFFE00000), width: 4),
                          bottom: BorderSide(color: Color(0xFFE00000), width: 4),
                        ),
                      )
                    : null,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: MapLibreMap(
                        styleString: _style,
                        initialCameraPosition:
                            const CameraPosition(target: LatLng(36.85, 42.97), zoom: 9),
                        minMaxZoomPreference: const MinMaxZoomPreference(null, kMaxZoom),
                        rotateGesturesEnabled: false,
                        tiltGesturesEnabled: false,
                        compassEnabled: false,
                        myLocationEnabled: _locOk,
                        onMapCreated: (c) => _c = c,
                        onStyleLoadedCallback: _onStyleLoaded,
                        onMapClick: _onMapClick,
                        onMapLongClick: _onMapLongClick,
                      ),
                    ),
                    if (_suggestions.isNotEmpty)
                      Positioned(top: 0, left: 12, right: 112, child: _suggestionList()),
                    if (_status != null)
                      Positioned(top: 12, left: 12, right: 12, child: Center(child: _statusCard())),
                    if (_info != null)
                      Positioned(left: 8, right: 8, bottom: 60, child: _infoCard(_info!)),
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: SafeArea(
                        top: false,
                        child: Row(
                          children: [
                            _toggleButton('Usage', _usageOn, () {
                              setState(() => _usageOn = !_usageOn);
                              _applyVisibility();
                            }),
                            const SizedBox(width: 8),
                            _toggleButton('Filter 0 User', _filterOn, () {
                              setState(() => _filterOn = !_filterOn);
                              _closeInfo();
                              _applyVisibility();
                            }),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _searchField() {
    return TextField(
      controller: _q,
      focusNode: _focus,
      textCapitalization: TextCapitalization.characters,
      autocorrect: false,
      enableSuggestions: false,
      textInputAction: TextInputAction.search,
      style: const TextStyle(fontSize: 15, color: Colors.black),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'''[A-Za-z0-9\-.,°'" ]''')),
      ],
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.white,
        hintText: '722-R01-FDT01-FAT01',
        hintStyle: const TextStyle(color: Color(0xFF999999)),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: _q,
          builder: (_, v, __) => v.text.isEmpty
              ? const SizedBox.shrink()
              : IconButton(
                  icon: const Icon(Icons.cancel_outlined, color: Color(0xFF666666)),
                  onPressed: () {
                    _q.clear();
                    setState(() => _suggestions = const []);
                    _focus.requestFocus();
                  },
                ),
        ),
      ),
      onChanged: _onSearch,
      onSubmitted: _onSubmit,
    );
  }

  Widget _suggestionList() {
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 220),
        child: ListView.separated(
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          itemCount: _suggestions.length,
          separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFEEEEEE)),
          itemBuilder: (_, i) {
            final p = _suggestions[i];
            return InkWell(
              onTap: () => _goToFat(p),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                child: Text(p.name, style: const TextStyle(fontSize: 14, color: Color(0xFF222222))),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _squareButton(
      {required VoidCallback onTap, required Widget child, bool active = false, required Color color}) {
    return Material(
      color: active ? (color == kRed ? kRed : kBlue) : Colors.white,
      borderRadius: BorderRadius.circular(8),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: SizedBox(width: 40, height: 40, child: Center(child: child)),
      ),
    );
  }

  Widget _layerButton(Color barColor) {
    return PopupMenuButton<Basemap>(
      tooltip: 'Change map background',
      onSelected: _setBasemap,
      offset: const Offset(0, 48),
      itemBuilder: (_) => [
        for (final b in Basemap.values)
          PopupMenuItem(
            value: b,
            child: Text(basemaps[b]!.label,
                style: TextStyle(
                  fontWeight: b == _base ? FontWeight.w700 : FontWeight.w400,
                  color: b == _base ? kBlue : const Color(0xFF222222),
                )),
          ),
      ],
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        elevation: 2,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(Icons.layers, size: 22, color: barColor == kRed ? kRed : kBlue),
        ),
      ),
    );
  }

  Widget _toggleButton(String label, bool on, VoidCallback onTap) {
    return Opacity(
      opacity: on ? 1 : 0.6,
      child: Material(
        color: on ? const Color(0xFFFF0000) : const Color(0xFF9E9E9E),
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: on ? Colors.white : Colors.transparent, width: 2),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: SizedBox(
            height: 40,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: Text(label,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _statusCard() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 330),
      child: Material(
        color: const Color(0xF5FFFFFF),
        elevation: 6,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!_statusError)
                const SizedBox(
                    width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2.2)),
              if (!_statusError) const SizedBox(width: 10),
              Flexible(
                child: Text(_status ?? '',
                    style: TextStyle(
                        fontSize: 13,
                        color: _statusError ? const Color(0xFFCC0000) : const Color(0xFF222222))),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoCard(_Info info) {
    final p = info.fat;
    Widget kv(String k, String v) => Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text.rich(TextSpan(children: [
            TextSpan(text: '$k : ', style: const TextStyle(color: Color(0xFF666666))),
            TextSpan(text: v),
          ])),
        );
    return Material(
      color: Colors.white,
      elevation: 8,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 4, 4),
        child: DefaultTextStyle(
          style: const TextStyle(fontSize: 14, color: Color(0xFF222222), height: 1.4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: SelectableText(info.title,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                  IconButton(
                    tooltip: p != null ? 'Copy' : 'Copy Location Coordinates',
                    icon: const Icon(Icons.copy, size: 20, color: Color(0xFF0078A8)),
                    onPressed: () => _copy(info.title),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: _closeInfo,
                  ),
                ],
              ),
              if (p != null) ...[
                kv('Partner', p.partner),
                kv('Area', p.area),
                kv('Installed ONTs', p.ont),
              ],
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                      padding: EdgeInsets.zero, foregroundColor: const Color(0xFF0078A8)),
                  onPressed: () => _openInMaps(info.lat, info.lng),
                  icon: const Icon(Icons.map_outlined, size: 18),
                  label: const Text('Open in Google Maps'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
