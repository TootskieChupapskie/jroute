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

class ConductorMapRender {
  /// Fetches GeoJSON from Supabase public storage and returns parsed MapLayers
  /// Route name will be converted to lowercase with spaces replaced by hyphens
  static Future<MapLayers> getLayersForRoute(String routeName) async {
    if (routeName.trim().isEmpty) return const MapLayers();

    // Convert route name to lowercase and replace spaces with hyphens
    final slug = routeName
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'[^a-z0-9\-]'), ''); // Remove any special characters except hyphens

    final supabaseUrl = dotenv.env['SUPABASE_URL'] ?? '';
    final bucket = dotenv.env['SUPABASE_BUCKET'] ?? 'Jroute';

    if (supabaseUrl.isEmpty) {
      debugPrint('SUPABASE_URL not found in .env');
      return const MapLayers();
    }

    try {
      final filePath = 'routes/$slug.geojson';
      final url = Uri.parse('$supabaseUrl/storage/v1/object/public/$bucket/$filePath');
      
      debugPrint('Fetching GeoJSON from: $url');
      
      final response = await http.get(url);

      if (response.statusCode != 200) {
        debugPrint('Failed to fetch GeoJSON: ${response.statusCode}');
        debugPrint('URL attempted: $url');
        return const MapLayers();
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final features = (data['features'] as List<dynamic>?) ?? [];

      final List<Polyline> polylines = [];
      final List<Polygon> polygons = [];
      final List<Marker> markers = [];

      int polylineCount = 0;
      int polygonCount = 0;
      int markerCount = 0;

      for (final f in features) {
        final feature = f as Map<String, dynamic>;
        final geometry = feature['geometry'] as Map<String, dynamic>?;
        if (geometry == null) continue;

        final type = (geometry['type'] as String?) ?? '';
        final coords = geometry['coordinates'];

        switch (type) {
          case 'LineString':
            _addLineString(coords, polylines, polylineCount);
            polylineCount++;
            break;

          case 'MultiLineString':
            final lines = coords as List<dynamic>;
            for (final line in lines) {
              _addLineString(line, polylines, polylineCount);
              polylineCount++;
            }
            break;

          case 'Polygon':
            _addPolygon(coords, polygons, polygonCount);
            polygonCount++;
            break;

          case 'MultiPolygon':
            final polys = coords as List<dynamic>;
            for (final polyCoords in polys) {
              _addPolygon(polyCoords, polygons, polygonCount);
              polygonCount++;
            }
            break;

          case 'Point':
            _addPoint(coords, markers, markerCount);
            markerCount++;
            break;

          default:
            debugPrint('Unknown geometry type: $type');
        }
      }

      debugPrint('Loaded ${polylines.length} polylines, ${polygons.length} polygons, ${markers.length} markers');

      return MapLayers(
        polylines: polylines,
        polygons: polygons,
        markers: markers,
      );
    } catch (e) {
      debugPrint('Error fetching GeoJSON for route "$routeName" (slug: $slug): $e');
      return const MapLayers();
    }
  }

  /// Helper to add a LineString to polylines
  static void _addLineString(
    dynamic coords,
    List<Polyline> polylines,
    int count,
  ) {
    final points = coords as List<dynamic>;
    final latLngList = points.map((p) {
      final point = p as List<dynamic>;
      return LatLng(
        (point[1] as num).toDouble(), // latitude
        (point[0] as num).toDouble(), // longitude
      );
    }).toList();

    final polyline = Polyline(
      polylineId: PolylineId('polyline_$count'),
      points: latLngList,
      color: Colors.orange,
      width: 5,
    );

    polylines.add(polyline);
  }

  /// Helper to add a Polygon to polygons
  static void _addPolygon(
    dynamic coords,
    List<Polygon> polygons,
    int count,
  ) {
    final rings = coords as List<dynamic>;
    if (rings.isEmpty) return;

    final outer = rings[0] as List<dynamic>;
    final latLngList = outer.map((p) {
      final point = p as List<dynamic>;
      return LatLng(
        (point[1] as num).toDouble(),
        (point[0] as num).toDouble(),
      );
    }).toList();

    final polygon = Polygon(
      polygonId: PolygonId('polygon_$count'),
      points: latLngList,
      fillColor: Colors.orange.withOpacity(0.2),
      strokeColor: Colors.orange,
      strokeWidth: 2,
    );

    polygons.add(polygon);
  }

  /// Helper to add a Point marker
  static void _addPoint(
    dynamic coords,
    List<Marker> markers,
    int count,
  ) {
    final point = coords as List<dynamic>;
    final latLng = LatLng(
      (point[1] as num).toDouble(),
      (point[0] as num).toDouble(),
    );

    final marker = Marker(
      markerId: MarkerId('marker_$count'),
      position: latLng,
      infoWindow: InfoWindow(title: 'Point $count'),
    );

    markers.add(marker);
  }
}