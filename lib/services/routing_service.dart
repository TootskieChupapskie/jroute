import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class RoutingResult {
  final List<Polyline> polylines;
  final List<LatLng> stitchedPath;
  final List<LatLng> googlePath;
  final bool usedFallback;
  final Map<String, dynamic> debugInfo;

  RoutingResult({
    required this.polylines,
    required this.stitchedPath,
    required this.googlePath,
    this.usedFallback = false,
    this.debugInfo = const {},
  });
}

class RouteNotFoundException implements Exception {
  final String message;
  RouteNotFoundException(this.message);
  
  @override
  String toString() => 'RouteNotFoundException: $message';
}

class RouteSegment {
  final String slug;
  final int partIndex;
  final List<LatLng> points;
  final double distanceToStart;
  final double distanceToEnd;
  final LatLng closestPointToStart;
  final LatLng closestPointToEnd;

  RouteSegment({
    required this.slug,
    required this.partIndex,
    required this.points,
    required this.distanceToStart,
    required this.distanceToEnd,
    required this.closestPointToStart,
    required this.closestPointToEnd,
  });
}

class RoutingService {
  static const _colorPool = <Color>[
    Colors.blue,
    Colors.green,
    Colors.red,
    Colors.purple,
    Colors.teal,
    Colors.orange,
    Colors.indigo,
  ];

  static final Map<String, List<List<LatLng>>> _routeCache = {};
  static List<String>? _routeIndexCache;

  static Future<List<String>> fetchRouteIndex() async {
    debugPrint('═══════════════════════════════════════════');
    debugPrint('📂 FETCHING ROUTE INDEX');
    debugPrint('═══════════════════════════════════════════');
    
    if (_routeIndexCache != null) {
      debugPrint('✅ Cache hit - returning ${_routeIndexCache!.length} cached routes');
      return _routeIndexCache!;
    }
    
    final supabaseUrl = dotenv.env['SUPABASE_URL'] ?? '';
    final bucket = dotenv.env['SUPABASE_BUCKET'] ?? 'Jroute';
    
    debugPrint('🔧 Config:');
    debugPrint('   SUPABASE_URL: ${supabaseUrl.isEmpty ? "❌ EMPTY" : "✅ $supabaseUrl"}');
    debugPrint('   SUPABASE_BUCKET: $bucket');
    
    if (supabaseUrl.isEmpty) {
      debugPrint('❌ SUPABASE_URL is empty - returning empty list');
      return [];
    }
    
    try {
      final url = Uri.parse('$supabaseUrl/storage/v1/object/public/$bucket/routes/index.json');
      debugPrint('🌐 Fetching: $url');
      
      final res = await http.get(url);
      debugPrint('📡 Response status: ${res.statusCode}');
      
      if (res.statusCode != 200) {
        debugPrint('❌ Failed with status ${res.statusCode}');
        debugPrint('   Response body: ${res.body}');
        return [];
      }
      
      debugPrint('✅ Success! Parsing JSON...');
      final data = json.decode(res.body) as List<dynamic>;
      _routeIndexCache = data.map((e) => e.toString()).toList();
      
      debugPrint('✅ Loaded ${_routeIndexCache!.length} routes');
      
      return _routeIndexCache!;
    } catch (e, st) {
      debugPrint('❌ fetchRouteIndex EXCEPTION: $e');
      debugPrint('   Stack trace: $st');
      return [];
    }
  }

  static Future<List<List<LatLng>>> loadRouteLines(String slug) async {
    debugPrint('📥 Loading route: $slug');
    
    if (_routeCache.containsKey(slug)) {
      debugPrint('   ✅ Cache hit');
      return _routeCache[slug]!;
    }

    final supabaseUrl = dotenv.env['SUPABASE_URL'] ?? '';
    final bucket = dotenv.env['SUPABASE_BUCKET'] ?? 'Jroute';
    
    if (supabaseUrl.isEmpty) {
      debugPrint('   ❌ Missing SUPABASE_URL');
      return [];
    }

    try {
      final filePath = 'routes/$slug.geojson';
      final url = Uri.parse('$supabaseUrl/storage/v1/object/public/$bucket/$filePath');

      final res = await http.get(url);
      
      if (res.statusCode != 200) {
        debugPrint('   ❌ Failed (${res.statusCode})');
        return [];
      }

      final data = json.decode(res.body);
      
      if (data is! Map<String, dynamic>) {
        debugPrint('   ❌ Invalid JSON structure');
        return [];
      }

      final features = (data['features'] as List<dynamic>?) ?? [];
      final parts = <List<LatLng>>[];
      
      for (final f in features) {
        final geometry = (f as Map<String, dynamic>)['geometry'] as Map<String, dynamic>?;
        if (geometry == null) continue;

        final type = (geometry['type'] as String?) ?? '';
        final coords = geometry['coordinates'];
        if (coords == null) continue;

        List<List<dynamic>> lineGroups = [];

        if (type == 'LineString') {
          lineGroups = [coords as List<dynamic>];
        } else if (type == 'MultiLineString') {
          lineGroups = (coords as List<dynamic>).cast<List<dynamic>>();
        }

        for (final line in lineGroups) {
          final pts = line.map((p) {
            final a = p as List<dynamic>;
            return LatLng((a[1] as num).toDouble(), (a[0] as num).toDouble());
          }).toList();

          if (pts.isNotEmpty) parts.add(pts);
        }
      }

      debugPrint('   ✅ Loaded ${parts.length} parts');
      _routeCache[slug] = parts;
      return parts;
    } catch (e) {
      debugPrint('   ❌ Exception: $e');
      return [];
    }
  }

  static Future<List<LatLng>> fetchGoogleDirections(LatLng start, LatLng dest) async {
    debugPrint('🗺️  Fetching Google Directions');
    debugPrint('   From: ${start.latitude}, ${start.longitude}');
    debugPrint('   To: ${dest.latitude}, ${dest.longitude}');
    
    final apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';
    if (apiKey.isEmpty) {
      throw RouteNotFoundException('Google Maps API key not configured');
    }

    final origin = '${start.latitude},${start.longitude}';
    final destination = '${dest.latitude},${dest.longitude}';
    
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/directions/json'
      '?origin=$origin'
      '&destination=$destination'
      '&mode=driving'
      '&key=$apiKey'
    );

    try {
      final res = await http.get(url);
      
      if (res.statusCode != 200) {
        throw RouteNotFoundException('Directions API request failed');
      }

      final data = json.decode(res.body) as Map<String, dynamic>;
      final status = data['status'] as String?;
      
      if (status != 'OK') {
        throw RouteNotFoundException('Directions API error: $status');
      }

      final routes = data['routes'] as List<dynamic>?;
      if (routes == null || routes.isEmpty) {
        throw RouteNotFoundException('No routes found by Google');
      }

      final route = routes[0] as Map<String, dynamic>;
      final overviewPolyline = route['overview_polyline'] as Map<String, dynamic>?;
      final encodedPoints = overviewPolyline?['points'] as String?;
      
      if (encodedPoints == null || encodedPoints.isEmpty) {
        throw RouteNotFoundException('No polyline in Google response');
      }

      final decoded = _decodePolyline(encodedPoints);
      debugPrint('   ✅ Decoded ${decoded.length} points');
      
      return decoded;
    } catch (e) {
      if (e is RouteNotFoundException) rethrow;
      throw RouteNotFoundException('Failed to fetch Google directions: $e');
    }
  }

  static List<LatLng> _decodePolyline(String encoded) {
    final points = <LatLng>[];
    int index = 0;
    int lat = 0;
    int lng = 0;

    while (index < encoded.length) {
      int b;
      int shift = 0;
      int result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      points.add(LatLng(lat / 1e5, lng / 1e5));
    }

    return points;
  }

  static double distanceMeters(LatLng a, LatLng b) {
    const R = 6371000;
    final lat1 = a.latitude * (math.pi / 180.0);
    final lat2 = b.latitude * (math.pi / 180.0);
    final dLat = lat2 - lat1;
    final dLon = (b.longitude - a.longitude) * (math.pi / 180.0);
    final hav = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) * math.cos(lat2) * math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(hav), math.sqrt(1 - hav));
    return R * c;
  }

  static Map<String, dynamic> closestPointOnSegment(LatLng p, LatLng a, LatLng b) {
    final ax = a.longitude;
    final ay = a.latitude;
    final bx = b.longitude;
    final by = b.latitude;
    final px = p.longitude;
    final py = p.latitude;

    final dx = bx - ax;
    final dy = by - ay;
    final len2 = dx * dx + dy * dy;
    if (len2 == 0) {
      return {'point': a, 't': 0.0};
    }
    final t = ((px - ax) * dx + (py - ay) * dy) / len2;
    final tt = t.clamp(0.0, 1.0);
    final projx = ax + dx * tt;
    final projy = ay + dy * tt;
    final point = LatLng(projy, projx);
    return {'point': point, 't': tt};
  }

  static Map<String, dynamic> findClosestPointOnRoute(LatLng point, List<LatLng> route) {
    double minDist = double.infinity;
    LatLng? closestPoint;
    int? segmentIndex;

    for (int i = 0; i < route.length - 1; i++) {
      final result = closestPointOnSegment(point, route[i], route[i + 1]);
      final projPoint = result['point'] as LatLng;
      final dist = distanceMeters(point, projPoint);

      if (dist < minDist) {
        minDist = dist;
        closestPoint = projPoint;
        segmentIndex = i;
      }
    }

    return {
      'point': closestPoint ?? route.first,
      'distance': minDist,
      'segmentIndex': segmentIndex ?? 0,
    };
  }

  static bool routesIntersect(List<LatLng> route1, List<LatLng> route2, {double thresholdMeters = 100.0}) {
    for (int i = 0; i < route1.length - 1; i++) {
      for (int j = 0; j < route2.length - 1; j++) {
        final r1p1 = route1[i];
        final r1p2 = route1[i + 1];
        final r2p1 = route2[j];
        final r2p2 = route2[j + 1];

        // Check if segments are close enough
        final proj1 = closestPointOnSegment(r1p1, r2p1, r2p2);
        final proj2 = closestPointOnSegment(r2p1, r1p1, r1p2);
        
        final dist1 = distanceMeters(r1p1, proj1['point'] as LatLng);
        final dist2 = distanceMeters(r2p1, proj2['point'] as LatLng);

        if (dist1 <= thresholdMeters || dist2 <= thresholdMeters) {
          return true;
        }
      }
    }
    return false;
  }

  static double calculateRouteGap(List<LatLng> route1, List<LatLng> route2) {
    double minGap = double.infinity;

    // Check distance between endpoints
    final r1End = route1.last;
    final r2Start = route2.first;
    final r1Start = route1.first;
    final r2End = route2.last;

    minGap = math.min(minGap, distanceMeters(r1End, r2Start));
    minGap = math.min(minGap, distanceMeters(r1Start, r2End));
    minGap = math.min(minGap, distanceMeters(r1End, r2End));
    minGap = math.min(minGap, distanceMeters(r1Start, r2Start));

    return minGap;
  }

  static Future<List<RouteSegment>> findAllRouteSegments(LatLng start, LatLng dest) async {
    debugPrint('');
    debugPrint('═══════════════════════════════════════════');
    debugPrint('🔍 FINDING ROUTE SEGMENTS');
    debugPrint('═══════════════════════════════════════════');
    
    final slugs = await fetchRouteIndex();
    final segments = <RouteSegment>[];

    for (final slug in slugs) {
      final parts = await loadRouteLines(slug);
      
      for (int partIndex = 0; partIndex < parts.length; partIndex++) {
        final part = parts[partIndex];
        
        final startResult = findClosestPointOnRoute(start, part);
        final endResult = findClosestPointOnRoute(dest, part);
        
        segments.add(RouteSegment(
          slug: slug,
          partIndex: partIndex,
          points: part,
          distanceToStart: startResult['distance'] as double,
          distanceToEnd: endResult['distance'] as double,
          closestPointToStart: startResult['point'] as LatLng,
          closestPointToEnd: endResult['point'] as LatLng,
        ));
      }
    }

    return segments;
  }

  static Future<RoutingResult> buildRoute(LatLng start, LatLng dest, {List<String>? slugs}) async {
    debugPrint('');
    debugPrint('╔═══════════════════════════════════════════╗');
    debugPrint('║     🚀 BUILD ROUTE STARTED               ║');
    debugPrint('╚═══════════════════════════════════════════╝');
    debugPrint('Start: ${start.latitude}, ${start.longitude}');
    debugPrint('Dest: ${dest.latitude}, ${dest.longitude}');
    
    final debugInfo = <String, dynamic>{
      'start': {'lat': start.latitude, 'lng': start.longitude},
      'dest': {'lat': dest.latitude, 'lng': dest.longitude},
      'timestamp': DateTime.now().toIso8601String(),
    };
    
    try {
      final googlePath = await fetchGoogleDirections(start, dest);
      debugInfo['googlePathLength'] = googlePath.length;
      
      if (googlePath.isEmpty) {
        throw RouteNotFoundException('Google returned empty route');
      }

      // Find all route segments and their distances
      final segments = await findAllRouteSegments(start, dest);
      
      if (segments.isEmpty) {
        debugPrint('❌ No routes available');
        throw RouteNotFoundException('No routes in index');
      }

      // Sort by closest to start
      segments.sort((a, b) => a.distanceToStart.compareTo(b.distanceToStart));
      
      debugPrint('');
      debugPrint('📊 Route Analysis:');
      for (int i = 0; i < math.min(5, segments.length); i++) {
        final s = segments[i];
        debugPrint('   [$i] ${s.slug}-${s.partIndex}');
        debugPrint('       Start: ${(s.distanceToStart / 1000).toStringAsFixed(2)}km');
        debugPrint('       End: ${(s.distanceToEnd / 1000).toStringAsFixed(2)}km');
      }

      const maxStartDistance = 1000.0; // 1km
      const maxEndDistance = 1000.0; // 1km
      const maxGap = 3000.0; // 3km
      const intersectionThreshold = 100.0; // 100m

      // CASE 1: Single route close to both start and end
      debugPrint('');
      debugPrint('🔍 Case 1: Looking for single route...');
      for (final segment in segments) {
        if (segment.distanceToStart <= maxStartDistance && 
            segment.distanceToEnd <= maxEndDistance) {
          debugPrint('✅ Found single route: ${segment.slug}-${segment.partIndex}');
          debugInfo['case'] = 'single_route';
          debugInfo['routes'] = [segment.slug];
          
          return _buildSingleRouteResult(segment, googlePath, debugInfo);
        }
      }

      // CASE 2: Two routes - one close to start, one close to end
      debugPrint('🔍 Case 2: Looking for connecting routes...');
      final startCandidates = segments
          .where((s) => s.distanceToStart <= maxStartDistance)
          .toList();
      final endCandidates = segments
          .where((s) => s.distanceToEnd <= maxEndDistance)
          .toList();

      debugPrint('   Start candidates: ${startCandidates.length}');
      debugPrint('   End candidates: ${endCandidates.length}');

      for (final startRoute in startCandidates) {
        for (final endRoute in endCandidates) {
          if (startRoute.slug == endRoute.slug && 
              startRoute.partIndex == endRoute.partIndex) {
            continue; // Same route, already checked in case 1
          }

          // Check if routes intersect
          final intersects = routesIntersect(
            startRoute.points, 
            endRoute.points, 
            thresholdMeters: intersectionThreshold
          );

          if (intersects) {
            debugPrint('✅ Found intersecting routes:');
            debugPrint('   ${startRoute.slug} → ${endRoute.slug}');
            debugInfo['case'] = 'intersecting_routes';
            debugInfo['routes'] = [startRoute.slug, endRoute.slug];
            
            return _buildTwoRouteResult(
              startRoute, endRoute, googlePath, debugInfo, intersects: true
            );
          }

          // Check gap between routes
          final gap = calculateRouteGap(startRoute.points, endRoute.points);
          if (gap <= maxGap) {
            debugPrint('✅ Found close routes (gap: ${(gap / 1000).toStringAsFixed(2)}km):');
            debugPrint('   ${startRoute.slug} → ${endRoute.slug}');
            debugInfo['case'] = 'close_routes_with_walk';
            debugInfo['routes'] = [startRoute.slug, endRoute.slug];
            debugInfo['walkingDistance'] = gap;
            
            return _buildTwoRouteResult(
              startRoute, endRoute, googlePath, debugInfo, gap: gap
            );
          }
        }
      }

      // CASE 3: Find connecting route
      debugPrint('🔍 Case 3: Looking for three-route connection...');
      if (startCandidates.isNotEmpty && endCandidates.isNotEmpty) {
        final startRoute = startCandidates.first;
        final endRoute = endCandidates.first;

        // Look for a route that connects the two
        for (final connector in segments) {
          if (connector.slug == startRoute.slug || connector.slug == endRoute.slug) {
            continue;
          }

          final connectsStart = routesIntersect(
            startRoute.points, 
            connector.points, 
            thresholdMeters: intersectionThreshold
          );
          final connectsEnd = routesIntersect(
            connector.points, 
            endRoute.points, 
            thresholdMeters: intersectionThreshold
          );

          if (connectsStart && connectsEnd) {
            debugPrint('✅ Found connecting route:');
            debugPrint('   ${startRoute.slug} → ${connector.slug} → ${endRoute.slug}');
            debugInfo['case'] = 'three_route_connection';
            debugInfo['routes'] = [startRoute.slug, connector.slug, endRoute.slug];
            
            return _buildThreeRouteResult(
              startRoute, connector, endRoute, googlePath, debugInfo
            );
          }
        }
      }

      // FALLBACK: Use Google route
      debugPrint('');
      debugPrint('⚠️  No suitable route combination found');
      debugPrint('   Falling back to Google route');
      debugInfo['case'] = 'fallback';
      
      return RoutingResult(
        polylines: [
          Polyline(
            polylineId: const PolylineId('google_fallback'),
            points: googlePath,
            color: Colors.grey,
            width: 5,
          )
        ],
        stitchedPath: googlePath,
        googlePath: googlePath,
        usedFallback: true,
        debugInfo: debugInfo,
      );

    } catch (e, st) {
      debugPrint('');
      debugPrint('❌ BUILD ROUTE FAILED: $e');
      debugPrint('   Stack: $st');
      
      if (e is RouteNotFoundException) rethrow;
      throw RouteNotFoundException('Routing failed: $e');
    }
  }

  static RoutingResult _buildSingleRouteResult(
    RouteSegment segment,
    List<LatLng> googlePath,
    Map<String, dynamic> debugInfo,
  ) {
    final polyline = Polyline(
      polylineId: PolylineId('${segment.slug}-${segment.partIndex}'),
      points: segment.points,
      color: _colorPool[0],
      width: 5,
    );

    return RoutingResult(
      polylines: [polyline],
      stitchedPath: segment.points,
      googlePath: googlePath,
      debugInfo: debugInfo,
    );
  }

  static RoutingResult _buildTwoRouteResult(
    RouteSegment route1,
    RouteSegment route2,
    List<LatLng> googlePath,
    Map<String, dynamic> debugInfo, {
    bool intersects = false,
    double? gap,
  }) {
    final polylines = [
      Polyline(
        polylineId: PolylineId('${route1.slug}-${route1.partIndex}'),
        points: route1.points,
        color: _colorPool[0],
        width: 5,
      ),
      Polyline(
        polylineId: PolylineId('${route2.slug}-${route2.partIndex}'),
        points: route2.points,
        color: _colorPool[1],
        width: 5,
      ),
    ];

    final stitchedPath = [...route1.points, ...route2.points];

    return RoutingResult(
      polylines: polylines,
      stitchedPath: stitchedPath,
      googlePath: googlePath,
      debugInfo: debugInfo,
    );
  }

  static RoutingResult _buildThreeRouteResult(
    RouteSegment route1,
    RouteSegment connector,
    RouteSegment route2,
    List<LatLng> googlePath,
    Map<String, dynamic> debugInfo,
  ) {
    final polylines = [
      Polyline(
        polylineId: PolylineId('${route1.slug}-${route1.partIndex}'),
        points: route1.points,
        color: _colorPool[0],
        width: 5,
      ),
      Polyline(
        polylineId: PolylineId('${connector.slug}-${connector.partIndex}'),
        points: connector.points,
        color: _colorPool[1],
        width: 5,
      ),
      Polyline(
        polylineId: PolylineId('${route2.slug}-${route2.partIndex}'),
        points: route2.points,
        color: _colorPool[2],
        width: 5,
      ),
    ];

    final stitchedPath = [...route1.points, ...connector.points, ...route2.points];

    return RoutingResult(
      polylines: polylines,
      stitchedPath: stitchedPath,
      googlePath: googlePath,
      debugInfo: debugInfo,
    );
  }

  static void clearCache() {
    debugPrint('🗑️  Clearing route cache');
    _routeCache.clear();
    _routeIndexCache = null;
  }
}