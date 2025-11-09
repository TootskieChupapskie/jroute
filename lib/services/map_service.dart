import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geolocator/geolocator.dart'; // added for location

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

    // base storage url (set in .env)
    final base =
        dotenv.env['SUPABASE_STORAGE_URL'] ?? 'https://your-supabase-url/storage/v1/object/public/routes';

    // helper to try fetching a file and parsing geojson
    Future<MapLayers?> tryFetch(String fileName) async {
      final url = '$base/$fileName.geojson';
      try {
        final res = await http.get(Uri.parse(url));
        if (res.statusCode != 200 || res.body.trim().isEmpty) return null;
        final Map<String, dynamic> data = json.decode(res.body) as Map<String, dynamic>;
        final features = (data['features'] as List<dynamic>?) ?? [];
        final List<Polyline> polylines = [];
        final List<Polygon> polygons = [];
        final List<Marker> markers = [];

        for (final f in features) {
          final geom = f['geometry'] as Map<String, dynamic>?;
          final props = f['properties'] as Map<String, dynamic>? ?? {};
          if (geom == null) continue;
          final type = (geom['type'] as String?) ?? '';
          final coords = geom['coordinates'];

          if (type == 'LineString' && coords is List) {
            final points = coords
                .map<LatLng>((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
                .toList();
            polylines.add(Polyline(
              polylineId: PolylineId(fileName + '_' + polylines.length.toString()),
              points: points,
              color: Colors.blue,
              width: 4,
            ));
          } else if (type == 'MultiLineString' && coords is List) {
            int idx = 0;
            for (final line in coords) {
              final points = (line as List)
                  .map<LatLng>((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
                  .toList();
              polylines.add(Polyline(
                polylineId: PolylineId(fileName + '_ml_$idx'),
                points: points,
                color: Colors.blue,
                width: 4,
              ));
              idx++;
            }
          } else if ((type == 'Polygon' || type == 'MultiPolygon') && coords != null) {
            // handle simple polygon (take first ring)
            if (coords is List && coords.isNotEmpty) {
              final ring = (type == 'Polygon') ? coords[0] : (coords[0][0] ?? coords[0]);
              final points = (ring as List)
                  .map<LatLng>((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
                  .toList();
              polygons.add(Polygon(
                polygonId: PolygonId(fileName + '_' + polygons.length.toString()),
                points: points,
                fillColor: Colors.blue.withOpacity(0.12),
                strokeColor: Colors.blue,
                strokeWidth: 2,
              ));
            }
          } else if (type == 'Point' && coords is List) {
            markers.add(Marker(
              markerId: MarkerId(fileName + '_' + markers.length.toString()),
              position: LatLng((coords[1] as num).toDouble(), (coords[0] as num).toDouble()),
              infoWindow: InfoWindow(title: props['name']?.toString() ?? fileName),
            ));
          }
        }

        return MapLayers(polylines: polylines, polygons: polygons, markers: markers);
      } catch (_) {
        return null;
      }
    }

    // build candidate filenames (sanitized and variants)
    String sanitize(String s) => s
        .replaceAll(RegExp(r'[_/]+'), ' ')
        .replaceAll(RegExp(r'\s*[-–—_]+\s*'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final cleaned = sanitize(routeName);

    final variants = <String>{
      cleaned, // e.g. "El Rio"
      cleaned.toLowerCase(), // "el rio"
      cleaned.replaceAll(' ', '_'), // "El_Rio"
      cleaned.replaceAll(' ', '-'), // "El-Rio"
      cleaned.replaceAll(' ', ''), // "ElRio"
      cleaned.toUpperCase(), // "EL RIO"
      'approx_$cleaned',
    }.toList();

    // first try the straightforward variants
    for (final v in variants) {
      final candidate = v.replaceAll(' ', '%20');
      final result = await tryFetch(candidate);
      if (result != null) return result;
    }

    // last attempt: "not prioritizing efficiency" — try each word individually (may be slow)
    final words = cleaned.split(' ');
    for (final w in words) {
      if (w.trim().isEmpty) continue;
      final result = await tryFetch(w);
      if (result != null) return result;
    }

    // final fallback: return hardcoded layers (non-null)
    return MapService.hardcodedLayers(conductor: false);
  }

  // Returns the device current LatLng or null if unavailable
  static Future<LatLng?> getCurrentLatLng() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return null;
      }
      if (permission == LocationPermission.deniedForever) return null;

      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      return LatLng(pos.latitude, pos.longitude);
    } catch (e) {
      debugPrint('MapService.getCurrentLatLng error: $e');
      return null;
    }
  }

  // Returns a CameraPosition centered on the user's current location if available,
  // otherwise returns a fallback CameraPosition (Davao).
  static Future<CameraPosition> cameraForCurrentLocation({double zoom = 15}) async {
    final LatLng? loc = await getCurrentLatLng();
    if (loc != null) return CameraPosition(target: loc, zoom: zoom);

    // fallback to Davao
    return const CameraPosition(target: LatLng(7.1907, 125.4553), zoom: 12);
  }

  // Optional: helper to provide hard-coded layers if needed elsewhere
  static MapLayers hardcodedLayers({bool conductor = true}) {
    if (conductor) {
      final polyline = Polyline(
        polylineId: const PolylineId('cond_poly_1'),
        points: const [
          LatLng(7.1907, 125.4553),
          LatLng(7.1950, 125.4600),
          LatLng(7.2050, 125.4650),
        ],
        color: Colors.blueAccent,
        width: 5,
      );

      final polygon = Polygon(
        polygonId: const PolygonId('cond_polygon_1'),
        points: const [
          LatLng(7.1930, 125.4520),
          LatLng(7.1980, 125.4620),
          LatLng(7.1870, 125.4670),
        ],
        fillColor: Colors.blue.withOpacity(0.16),
        strokeColor: Colors.blueAccent,
        strokeWidth: 2,
      );

      final marker = Marker(
        markerId: const MarkerId('cond_m_1'),
        position: const LatLng(7.1907, 125.4553),
        infoWindow: const InfoWindow(title: 'Driver'),
      );

      return MapLayers(
        polylines: [polyline],
        polygons: [polygon],
        markers: [marker],
      );
    } else {
      final polyline = Polyline(
        polylineId: const PolylineId('hard_poly_1'),
        points: const [
          LatLng(7.1907, 125.4553),
          LatLng(7.2000, 125.4600),
          LatLng(7.2100, 125.4700),
        ],
        color: Colors.orange,
        width: 5,
      );

      final polygon = Polygon(
        polygonId: const PolygonId('hard_polygo_1'),
        points: const [
          LatLng(7.1950, 125.4500),
          LatLng(7.1970, 125.4650),
          LatLng(7.1850, 125.4680),
        ],
        fillColor: Colors.orange.withOpacity(0.18),
        strokeColor: Colors.orange,
        strokeWidth: 2,
      );

      final marker1 = Marker(
        markerId: const MarkerId('hard_m_1'),
        position: const LatLng(7.1907, 125.4553),
        infoWindow: const InfoWindow(title: 'Start'),
      );
      final marker2 = Marker(
        markerId: const MarkerId('hard_m_2'),
        position: const LatLng(7.2100, 125.4700),
        infoWindow: const InfoWindow(title: 'End'),
      );

      return MapLayers(
        polylines: [polyline],
        polygons: [polygon],
        markers: [marker1, marker2],
      );
    }
  }
}
