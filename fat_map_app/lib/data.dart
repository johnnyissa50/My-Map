// Loads assets/data.csv, builds the FAT point list (for search + details) and
// writes two GeoJSON files (all points / points with 0 installed ONTs).
//
// The GeoJSON is handed to the native map engine as a FILE URL, so the
// 100k points never travel through Flutter's platform channel: the native
// engine reads, indexes and clusters them itself (in C++, off the UI thread).
// Everything heavy here runs in a background isolate.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:csv/csv.dart';

class FatPoint {
  final String name;
  final String search; // upper-case name
  final double lat;
  final double lng;
  final String partner;
  final String area;
  final String ont;
  final bool zero;
  final String color; // partner color
  final String usageColor; // color by installed ONTs

  const FatPoint({
    required this.name,
    required this.search,
    required this.lat,
    required this.lng,
    required this.partner,
    required this.area,
    required this.ont,
    required this.zero,
    required this.color,
    required this.usageColor,
  });
}

class FatData {
  final List<FatPoint> points;
  final List<FatPoint> sorted; // sorted by `search`, for fast prefix search
  final Map<String, FatPoint> byName;
  final String allUrl; // file:// URL of the GeoJSON with every point
  final String zeroUrl; // file:// URL of the GeoJSON with 0-ONT points
  final int zeroCount;
  final int parseMs;

  FatData(this.points, this.sorted, this.allUrl, this.zeroUrl, this.zeroCount, this.parseMs)
      : byName = {for (final p in points) p.name: p};

  /// Up to [limit] points whose code starts with [prefix] (binary search).
  List<FatPoint> prefixSearch(String prefix, {int limit = 25}) {
    if (prefix.isEmpty) return const [];
    int lo = 0, hi = sorted.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (sorted[mid].search.compareTo(prefix) < 0) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    final out = <FatPoint>[];
    for (int i = lo; i < sorted.length && out.length < limit; i++) {
      if (!sorted[i].search.startsWith(prefix)) break;
      out.add(sorted[i]);
    }
    return out;
  }
}

// ---- Colors (same as the web version) --------------------------------------
const String defaultPointColor = '#808080';
const Map<String, String> partnerColors = {
  'Fiber Speed (Duhok)': '#FF0000',
  'Waarpak': '#0080FF',
  '3BG': '#00B400',
  'Delta (Zakho)': '#FF8000',
  'Delta (Duhok)': '#FF8000',
  'Strong Link Duhok': '#FF6699',
  'PrimeLink Duhok': '#48B6E8',
  'BigLine': '#00B400',
};
const List<String> _usageColors = [
  '#00FF00', '#55DD55', '#99BB99', '#808080', '#808080', '#808080', '#808080',
  '#808080', '#808080', '#808080', '#808080', '#808080', '#808080', '#808080',
  '#AA8080', '#D55555', '#FF0000',
];
final RegExp _digits = RegExp(r'^\d+$');
String usageColorFor(String ont) {
  if (!_digits.hasMatch(ont)) return '#00FF00';
  final n = int.parse(ont);
  return n <= 16 ? _usageColors[n] : '#00FF00';
}

// ---- Public entry point ------------------------------------------------------
Future<FatData> loadFatData() async {
  final bd = await rootBundle.load('assets/data.csv');
  final bytes = bd.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes);
  final dir = (await getApplicationSupportDirectory()).path;
  final r = await compute(_process, _Job(bytes, dir));
  return FatData(r.points, r.sorted, r.allUrl, r.zeroUrl, r.zeroCount, r.ms);
}

class _Job {
  final Uint8List bytes;
  final String dir;
  _Job(this.bytes, this.dir);
}

class _Result {
  final List<FatPoint> points;
  final List<FatPoint> sorted;
  final String allUrl, zeroUrl;
  final int zeroCount, ms;
  _Result(this.points, this.sorted, this.allUrl, this.zeroUrl, this.zeroCount, this.ms);
}

// ---- Runs in a background isolate -------------------------------------------
_Result _process(_Job job) {
  final sw = Stopwatch()..start();

  // Cache key: size + FNV-1a hash of the CSV. GeoJSON files are rewritten
  // only when data.csv changes.
  int h = 0x811c9dc5;
  for (final b in job.bytes) {
    h ^= b;
    h = (h * 0x01000193) & 0xffffffff;
  }
  final key = '${job.bytes.length}_${h.toRadixString(16)}';

  var text = utf8.decode(job.bytes, allowMalformed: true);
  if (text.isNotEmpty && text.codeUnitAt(0) == 0xFEFF) text = text.substring(1);
  text = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

  final rows = CsvToListConverter(eol: '\n', shouldParseNumbers: false)
      .convert(text);
  if (rows.isEmpty) throw Exception('data.csv is empty');

  final header = rows.first.map((e) => e.toString().trim()).toList();
  int col(String name) => header.indexOf(name);
  final iName = col('NAME'), iLat = col('latitude'), iLng = col('longitude');
  final iPartner = col('Partner'), iOnt = col('Installed ONTs'), iArea = col('Area');
  if (iName < 0 || iLat < 0 || iLng < 0) {
    throw Exception('data.csv must have NAME, latitude, longitude columns');
  }
  String cell(List row, int i) => (i >= 0 && i < row.length) ? row[i].toString().trim() : '';

  final points = <FatPoint>[];
  int zeroCount = 0;
  for (int r = 1; r < rows.length; r++) {
    final row = rows[r];
    final name = cell(row, iName);
    final lat = double.tryParse(cell(row, iLat));
    final lng = double.tryParse(cell(row, iLng));
    if (name.isEmpty || lat == null || lng == null) continue;
    final partner = cell(row, iPartner);
    final ont = cell(row, iOnt);
    final area = cell(row, iArea);
    final zero = ont.isNotEmpty && int.tryParse(ont) == 0;
    if (zero) zeroCount++;
    points.add(FatPoint(
      name: name,
      search: name.toUpperCase(),
      lat: lat,
      lng: lng,
      partner: partner.isEmpty ? 'Unknown' : partner,
      area: area.isEmpty ? 'Unknown' : area,
      ont: ont.isEmpty ? 'Unknown' : ont,
      zero: zero,
      color: partnerColors[partner] ?? defaultPointColor,
      usageColor: usageColorFor(ont),
    ));
  }

  final allFile = File('${job.dir}/fat_all_$key.geojson');
  final zeroFile = File('${job.dir}/fat_zero_$key.geojson');
  if (!allFile.existsSync() || !zeroFile.existsSync()) {
    // Remove files of older data versions.
    try {
      for (final f in Directory(job.dir).listSync()) {
        final n = f.uri.pathSegments.last;
        if (n.startsWith('fat_') && n.endsWith('.geojson')) f.deleteSync();
      }
    } catch (_) {}
    _writeGeoJson(allFile, points);
    _writeGeoJson(zeroFile, points.where((p) => p.zero));
  }

  final sorted = List<FatPoint>.of(points)..sort((a, b) => a.search.compareTo(b.search));
  return _Result(points, sorted, Uri.file(allFile.path).toString(),
      Uri.file(zeroFile.path).toString(), zeroCount, sw.elapsedMilliseconds);
}

void _writeGeoJson(File f, Iterable<FatPoint> pts) {
  final b = StringBuffer('{"type":"FeatureCollection","features":[');
  bool first = true;
  for (final p in pts) {
    if (!first) b.write(',');
    first = false;
    b
      ..write('{"type":"Feature","geometry":{"type":"Point","coordinates":[')
      ..write(p.lng)
      ..write(',')
      ..write(p.lat)
      ..write(']},"properties":{"n":')
      ..write(jsonEncode(p.name))
      ..write(',"c":"')
      ..write(p.color)
      ..write('","uc":"')
      ..write(p.usageColor)
      ..write('"}}');
  }
  b.write(']}');
  // Write to a temp file first so a crash never leaves a half-written cache.
  final tmp = File('${f.path}.tmp');
  tmp.writeAsStringSync(b.toString(), flush: true);
  tmp.renameSync(f.path);
}
