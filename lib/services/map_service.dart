import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class MapLayers {
  final List<Polyline> polylines;
  final List<Polygon> polygons;
  final List<Marker> markers;

  const MapLayers({
    this.polylines = const <Polyline>[],
    this.polygons = const <Polygon>[],
    this.markers = const <Marker>[],
  });
}

class MapService {
  // Fetches GeoJSON from Supabase public storage and returns parsed MapLayers
  static Future<MapLayers> getLayersForRoute(String routeName) async {
    if (routeName.trim().isEmpty) return const MapLayers();
    // sanitize route name, keep letters, numbers, spaces and hyphens
    final sanitized = routeName
        .toLowerCase()
        .replaceAll(RegExp(r"[^a-z0-9\s-]"), '')
        .trim();

    // generate candidate slugs in order of preference: hyphen, underscore, concatenated
    final candidates = <String>[
      sanitized.replaceAll(RegExp(r"\s+"), '-'),
      sanitized.replaceAll(RegExp(r"\s+"), '_'),
      sanitized.replaceAll(RegExp(r"\s+"), ''),
    ];

    final supabaseUrl = dotenv.env['SUPABASE_URL'] ?? '';
    final bucket = dotenv.env['SUPABASE_BUCKET'] ?? 'Jroute';
    if (supabaseUrl.isEmpty) {
      debugPrint('SUPABASE_URL not found in .env');
      return const MapLayers();
    }

  Map<String, dynamic>? data;
    try {
      for (final slug in candidates) {
        final filePath = 'routes/$slug.geojson';
        final url = Uri.parse('$supabaseUrl/storage/v1/object/public/$bucket/$filePath');
        final res = await http.get(url);
        if (res.statusCode == 200) {
          data = json.decode(res.body) as Map<String, dynamic>;
          break;
        }
      }

      if (data == null) {
        debugPrint('GeoJSON not found for any candidate in routes for "$routeName"');
        return const MapLayers();
      }

  final features = (data['features'] as List<dynamic>?) ?? [];

      final List<Polyline> polylines = [];
      final List<Polygon> polygons = [];
      final List<Marker> markers = [];

      int polylineCnt = 0;
      int polygonCnt = 0;
      int markerCnt = 0;

      for (final f in features) {
        final feature = f as Map<String, dynamic>;
        final geometry = feature['geometry'] as Map<String, dynamic>?;
        if (geometry == null) continue;
        final type = (geometry['type'] as String?) ?? '';
        final coords = geometry['coordinates'];

        if (type == 'LineString') {
          final List<dynamic> points = coords as List<dynamic>;
          final List<LatLng> latlng = points.map((p) {
            final x = p as List<dynamic>;
            return LatLng((x[1] as num).toDouble(), (x[0] as num).toDouble());
          }).toList();
          final id = PolylineId('poly_$polylineCnt');
          polylineCnt++;
          final poly = Polyline(
            polylineId: id,
            points: latlng,
            color: Colors.orange,
            width: 4,
          );
          polylines.add(poly);
        } else if (type == 'MultiLineString') {
          final List<dynamic> lines = coords as List<dynamic>;
          for (final line in lines) {
            final List<dynamic> points = line as List<dynamic>;
            final List<LatLng> latlng = points.map((p) {
              final x = p as List<dynamic>;
              return LatLng((x[1] as num).toDouble(), (x[0] as num).toDouble());
            }).toList();
            final id = PolylineId('poly_$polylineCnt');
            polylineCnt++;
            final poly = Polyline(polylineId: id, points: latlng, color: Colors.orange, width: 4);
            polylines.add(poly);
          }
        } else if (type == 'Polygon') {
          final List<dynamic> rings = coords as List<dynamic>;
          if (rings.isEmpty) continue;
          final outer = rings[0] as List<dynamic>;
          final List<LatLng> latlng = outer.map((p) {
            final x = p as List<dynamic>;
            return LatLng((x[1] as num).toDouble(), (x[0] as num).toDouble());
          }).toList();
          final id = PolygonId('polygo_$polygonCnt');
          polygonCnt++;
          final poly = Polygon(polygonId: id, points: latlng, fillColor: Colors.orange.withOpacity(0.2), strokeColor: Colors.orange, strokeWidth: 2);
          polygons.add(poly);
        } else if (type == 'MultiPolygon') {
          final List<dynamic> polys = coords as List<dynamic>;
          for (final polyCoords in polys) {
            final outer = (polyCoords as List<dynamic>)[0] as List<dynamic>;
            final List<LatLng> latlng = outer.map((p) {
              final x = p as List<dynamic>;
              return LatLng((x[1] as num).toDouble(), (x[0] as num).toDouble());
            }).toList();
            final id = PolygonId('polygo_$polygonCnt');
            polygonCnt++;
            final poly = Polygon(polygonId: id, points: latlng, fillColor: Colors.orange.withOpacity(0.2), strokeColor: Colors.orange, strokeWidth: 2);
            polygons.add(poly);
          }
        } else if (type == 'Point') {
          final p = coords as List<dynamic>;
          final latlng = LatLng((p[1] as num).toDouble(), (p[0] as num).toDouble());
          final id = MarkerId('m_$markerCnt');
          markerCnt++;
          final marker = Marker(markerId: id, position: latlng);
          markers.add(marker);
        }
      }

      return MapLayers(polylines: polylines, polygons: polygons, markers: markers);
    } catch (e) {
      debugPrint('Error fetching geojson: $e');
      return const MapLayers();
    }
  }
}
