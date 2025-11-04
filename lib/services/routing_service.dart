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
  final List<LatLng> points; // Original full route
  final List<LatLng> trimmedPoints; // Trimmed segment from start to end
  final double distanceToStart;
  final double distanceToEnd;
  final LatLng closestPointToStart;
  final LatLng closestPointToEnd;
  final double segmentLength; // Length of the trimmed segment
  final bool reachesDestination; // Whether this segment gets close enough to destination

  RouteSegment({
    required this.slug,
    required this.partIndex,
    required this.points,
    required this.trimmedPoints,
    required this.distanceToStart,
    required this.distanceToEnd,
    required this.closestPointToStart,
    required this.closestPointToEnd,
    required this.segmentLength,
    required this.reachesDestination,
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

  static Future<List<LatLng>> _fetchWalkingDirections(LatLng start, LatLng dest) async {
    debugPrint('🚶 Fetching Walking Directions');
    debugPrint('   From: ${start.latitude}, ${start.longitude}');
    debugPrint('   To: ${dest.latitude}, ${dest.longitude}');
    
    final apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';
    if (apiKey.isEmpty) {
      debugPrint('   ⚠️  No API key, returning straight line');
      return [start, dest];
    }

    final origin = '${start.latitude},${start.longitude}';
    final destination = '${dest.latitude},${dest.longitude}';
    
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/directions/json'
      '?origin=$origin'
      '&destination=$destination'
      '&mode=walking'
      '&key=$apiKey'
    );

    try {
      final res = await http.get(url);
      
      if (res.statusCode != 200) {
        debugPrint('   ⚠️  API failed, returning straight line');
        return [start, dest];
      }

      final data = json.decode(res.body) as Map<String, dynamic>;
      final status = data['status'] as String?;
      
      if (status != 'OK') {
        debugPrint('   ⚠️  Status: $status, returning straight line');
        return [start, dest];
      }

      final routes = data['routes'] as List<dynamic>?;
      if (routes == null || routes.isEmpty) {
        debugPrint('   ⚠️  No routes, returning straight line');
        return [start, dest];
      }

      final route = routes[0] as Map<String, dynamic>;
      final overviewPolyline = route['overview_polyline'] as Map<String, dynamic>?;
      final encodedPoints = overviewPolyline?['points'] as String?;
      
      if (encodedPoints == null || encodedPoints.isEmpty) {
        debugPrint('   ⚠️  No polyline, returning straight line');
        return [start, dest];
      }

      final decoded = _decodePolyline(encodedPoints);
      debugPrint('   ✅ Walking path: ${decoded.length} points');
      
      return decoded;
    } catch (e) {
      debugPrint('   ⚠️  Exception: $e, returning straight line');
      return [start, dest];
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
    double? segmentT; // Position along the segment (0.0 to 1.0)

    for (int i = 0; i < route.length - 1; i++) {
      final result = closestPointOnSegment(point, route[i], route[i + 1]);
      final projPoint = result['point'] as LatLng;
      final t = result['t'] as double;
      final dist = distanceMeters(point, projPoint);

      if (dist < minDist) {
        minDist = dist;
        closestPoint = projPoint;
        segmentIndex = i;
        segmentT = t;
      }
    }

    return {
      'point': closestPoint ?? route.first,
      'distance': minDist,
      'segmentIndex': segmentIndex ?? 0,
      'segmentT': segmentT ?? 0.0,
    };
  }

  /// Trim route between two points on the route
  /// Returns the segment of the route from startInfo to endInfo
  static List<LatLng> trimRouteBetweenPoints(
    List<LatLng> route,
    Map<String, dynamic> startInfo,
    Map<String, dynamic> endInfo,
  ) {
    final startIdx = startInfo['segmentIndex'] as int;
    final endIdx = endInfo['segmentIndex'] as int;
    final startPoint = startInfo['point'] as LatLng;
    final endPoint = endInfo['point'] as LatLng;

    debugPrint('   🔪 Trimming route:');
    debugPrint('      Route length: ${route.length} points');
    debugPrint('      Start index: $startIdx, End index: $endIdx');
    debugPrint('      Direction: ${startIdx > endIdx ? "BACKWARDS" : "FORWARDS"}');

    // Determine if we need to reverse the route
    if (startIdx > endIdx) {
      // Going backwards - we need to reverse the entire extraction
      final trimmed = <LatLng>[];
      
      // Add start point
      trimmed.add(startPoint);
      
      // Add points from startIdx down to endIdx (going backwards)
      for (int i = startIdx; i >= endIdx + 1; i--) {
        if (i < route.length && i > 0) {
          trimmed.add(route[i]);
        }
      }
      
      // Add end point
      if (distanceMeters(trimmed.last, endPoint) > 1.0) {
        trimmed.add(endPoint);
      }
      
      debugPrint('      Trimmed (backwards): ${trimmed.length} points');
      return trimmed;
    }

    // Going forwards
    final trimmed = <LatLng>[];
    
    // Add start point
    trimmed.add(startPoint);
    
    // Add all complete points between start and end segments
    for (int i = startIdx + 1; i <= endIdx; i++) {
      if (i < route.length) {
        trimmed.add(route[i]);
      }
    }
    
    // Add end point if it's different from the last added point
    if (distanceMeters(trimmed.last, endPoint) > 1.0) {
      trimmed.add(endPoint);
    }

    debugPrint('      Trimmed (forwards): ${trimmed.length} points');
    return trimmed;
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

  /// Find the intersection point between two routes
  /// Returns Map with 'point', 'route1Index', 'route2Index'
  static Map<String, dynamic>? findIntersectionPoint(
    List<LatLng> route1, 
    List<LatLng> route2, 
    {double thresholdMeters = 100.0}
  ) {
    double minDist = double.infinity;
    LatLng? intersectionPoint;
    int? route1Idx;
    int? route2Idx;

    for (int i = 0; i < route1.length - 1; i++) {
      for (int j = 0; j < route2.length - 1; j++) {
        final r1p1 = route1[i];
        final r1p2 = route1[i + 1];
        final r2p1 = route2[j];
        final r2p2 = route2[j + 1];

        // Find closest points between the two segments
        final proj1 = closestPointOnSegment(r1p1, r2p1, r2p2);
        final proj2 = closestPointOnSegment(r2p1, r1p1, r1p2);
        
        final projPoint1 = proj1['point'] as LatLng;
        final projPoint2 = proj2['point'] as LatLng;
        
        final dist1 = distanceMeters(r1p1, projPoint1);
        final dist2 = distanceMeters(r2p1, projPoint2);

        // Use the closest point as potential intersection
        if (dist1 <= thresholdMeters && dist1 < minDist) {
          minDist = dist1;
          intersectionPoint = projPoint1;
          route1Idx = i;
          route2Idx = j;
        }
        
        if (dist2 <= thresholdMeters && dist2 < minDist) {
          minDist = dist2;
          intersectionPoint = projPoint2;
          route1Idx = i;
          route2Idx = j;
        }
      }
    }

    if (intersectionPoint != null && route1Idx != null && route2Idx != null) {
      return {
        'point': intersectionPoint,
        'route1Index': route1Idx,
        'route2Index': route2Idx,
        'distance': minDist,
      };
    }

    return null;
  }

  /// Trim route from start to a specific index
  static List<LatLng> trimRouteToIndex(List<LatLng> route, int endIndex, LatLng endPoint) {
    final trimmed = <LatLng>[];
    
    for (int i = 0; i <= endIndex && i < route.length; i++) {
      trimmed.add(route[i]);
    }
    
    // Add the end point if it's different from last point
    if (trimmed.isNotEmpty && distanceMeters(trimmed.last, endPoint) > 1.0) {
      trimmed.add(endPoint);
    }
    
    return trimmed;
  }

  /// Trim route from a specific index to end
  static List<LatLng> trimRouteFromIndex(List<LatLng> route, int startIndex, LatLng startPoint) {
    final trimmed = <LatLng>[startPoint];
    
    for (int i = startIndex + 1; i < route.length; i++) {
      trimmed.add(route[i]);
    }
    
    return trimmed;
  }

  /// Find connection point between two routes (endpoints)
  static Map<String, dynamic>? findConnectionPoint(List<LatLng> route1, List<LatLng> route2) {
    final r1End = route1.last;
    final r2Start = route2.first;
    
    final gap = distanceMeters(r1End, r2Start);
    
    return {
      'point1': r1End,
      'point2': r2Start,
      'distance': gap,
    };
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
    const maxReachThreshold = 500.0; // 500m to consider "reaching" destination

    for (final slug in slugs) {
      final parts = await loadRouteLines(slug);
      
      for (int partIndex = 0; partIndex < parts.length; partIndex++) {
        final part = parts[partIndex];
        
        final startResult = findClosestPointOnRoute(start, part);
        final endResult = findClosestPointOnRoute(dest, part);
        
        final distToStart = startResult['distance'] as double;
        final distToEnd = endResult['distance'] as double;
        
        // Trim the route to only the relevant segment
        final trimmed = trimRouteBetweenPoints(part, startResult, endResult);
        
        // Calculate length of trimmed segment
        double segmentLength = 0.0;
        for (int i = 0; i < trimmed.length - 1; i++) {
          segmentLength += distanceMeters(trimmed[i], trimmed[i + 1]);
        }
        
        // Check if this route actually reaches the destination
        final reachesDestination = distToEnd <= maxReachThreshold;
        
        segments.add(RouteSegment(
          slug: slug,
          partIndex: partIndex,
          points: part,
          trimmedPoints: trimmed,
          distanceToStart: distToStart,
          distanceToEnd: distToEnd,
          closestPointToStart: startResult['point'] as LatLng,
          closestPointToEnd: endResult['point'] as LatLng,
          segmentLength: segmentLength,
          reachesDestination: reachesDestination,
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

      // Sort by closest to start, but prioritize routes that reach destination
      segments.sort((a, b) {
        // First, prioritize routes that reach the destination
        if (a.reachesDestination && !b.reachesDestination) return -1;
        if (!a.reachesDestination && b.reachesDestination) return 1;
        
        // Then sort by distance to start
        return a.distanceToStart.compareTo(b.distanceToStart);
      });
      
      debugPrint('');
      debugPrint('📊 Route Analysis:');
      for (int i = 0; i < math.min(10, segments.length); i++) {
        final s = segments[i];
        debugPrint('   [$i] ${s.slug}-${s.partIndex}');
        debugPrint('       Start: ${(s.distanceToStart / 1000).toStringAsFixed(2)}km');
        debugPrint('       End: ${(s.distanceToEnd / 1000).toStringAsFixed(2)}km');
        debugPrint('       Length: ${(s.segmentLength / 1000).toStringAsFixed(2)}km');
        debugPrint('       Reaches dest: ${s.reachesDestination ? "✅" : "❌"}');
      }

      const maxStartDistance = 1000.0; // 1km
      const maxWalkingDistance = 500.0; // 500m walking distance to destination
      const intersectionThreshold = 100.0; // 100m

      // CASE 1A: Single route that reaches destination perfectly
      debugPrint('');
      debugPrint('🔍 Case 1A: Looking for single route that reaches destination...');
      for (final segment in segments) {
        if (segment.distanceToStart <= maxStartDistance && 
            segment.reachesDestination) {
          debugPrint('✅ Found single route: ${segment.slug}-${segment.partIndex}');
          debugPrint('   Segment length: ${(segment.segmentLength / 1000).toStringAsFixed(2)}km');
          
          // Even if it "reaches" destination, check if there's a small gap
          if (segment.distanceToEnd > 10.0) { // More than 10m gap
            debugPrint('   Small gap to destination: ${segment.distanceToEnd.toStringAsFixed(0)}m');
            debugPrint('   Adding walking path to exact destination');
            
            final walkingPath = await _fetchWalkingDirections(
              segment.closestPointToEnd,
              dest
            );
            
            debugInfo['case'] = 'single_route_with_walking';
            debugInfo['routes'] = [segment.slug];
            debugInfo['walkingDistance'] = segment.distanceToEnd;
            
            return _buildSingleRouteResult(segment, walkingPath, googlePath, debugInfo);
          }
          
          debugInfo['case'] = 'single_route_complete';
          debugInfo['routes'] = [segment.slug];
          
          return _buildSingleRouteResult(segment, null, googlePath, debugInfo);
        }
      }

      // CASE 1B: Single route that gets close but requires walking to destination
      debugPrint('');
      debugPrint('🔍 Case 1B: Looking for single route with walking distance...');
      for (final segment in segments) {
        if (segment.distanceToStart <= maxStartDistance && 
            segment.distanceToEnd <= maxWalkingDistance) {
          debugPrint('✅ Found single route with walking: ${segment.slug}-${segment.partIndex}');
          debugPrint('   Segment length: ${(segment.segmentLength / 1000).toStringAsFixed(2)}km');
          debugPrint('   Walking distance: ${(segment.distanceToEnd / 1000).toStringAsFixed(2)}km');
          debugInfo['case'] = 'single_route_with_walking';
          debugInfo['routes'] = [segment.slug];
          debugInfo['walkingDistance'] = segment.distanceToEnd;
          
          // Get walking directions from end of route to destination
          final walkingPath = await _fetchWalkingDirections(
            segment.closestPointToEnd, 
            dest
          );
          
          return _buildSingleRouteResult(segment, walkingPath, googlePath, debugInfo);
        }
      }

      // CASE 2: Two routes - one close to start, one that reaches end
      debugPrint('');
      debugPrint('🔍 Case 2: Looking for connecting routes...');
      
      // Sort start candidates by distance to start (nearest first)
      final startCandidates = segments
          .where((s) => s.distanceToStart <= maxStartDistance)
          .toList()
        ..sort((a, b) => a.distanceToStart.compareTo(b.distanceToStart));
      
      // Sort end candidates by distance to end (nearest to destination first)
      final endCandidates = segments
          .where((s) => s.reachesDestination)
          .toList()
        ..sort((a, b) => a.distanceToEnd.compareTo(b.distanceToEnd));

      debugPrint('   Start candidates: ${startCandidates.length}');
      debugPrint('   End candidates: ${endCandidates.length}');

      const maxWalkingGap = 500.0; // 500m walking distance between routes (base distance)

      // APPROACH 1: First, prioritize finding intersecting routes
      for (final startRoute in startCandidates) {
        for (final endRoute in endCandidates) {
          if (startRoute.slug == endRoute.slug && 
              startRoute.partIndex == endRoute.partIndex) {
            continue; // Same route, already checked in case 1
          }

          final intersection = findIntersectionPoint(
            startRoute.trimmedPoints, 
            endRoute.trimmedPoints, 
            thresholdMeters: intersectionThreshold
          );

          if (intersection != null) {
            final intersectPoint = intersection['point'] as LatLng;
            final route1Idx = intersection['route1Index'] as int;
            final route2Idx = intersection['route2Index'] as int;
            
            debugPrint('✅ Found intersecting routes:');
            debugPrint('   ${startRoute.slug} (nearest to user)');
            debugPrint('   → ${endRoute.slug} (nearest to destination)');
            debugPrint('   Intersection at indices: [$route1Idx, $route2Idx]');
            
            // Trim route1 from start to intersection
            final trimmedRoute1 = trimRouteToIndex(
              startRoute.trimmedPoints, 
              route1Idx, 
              intersectPoint
            );
            
            // Trim route2 from intersection to end
            final trimmedRoute2 = trimRouteFromIndex(
              endRoute.trimmedPoints, 
              route2Idx, 
              intersectPoint
            );
            
            // Calculate length of second route segment
            double route2Length = 0.0;
            for (int i = 0; i < trimmedRoute2.length - 1; i++) {
              route2Length += distanceMeters(trimmedRoute2[i], trimmedRoute2[i + 1]);
            }
            
            debugPrint('   Route 2 segment length: ${(route2Length).toStringAsFixed(0)}m');
            
            // If second route is short (< 500m), replace with walking
            if (route2Length < 500.0) {
              // Check distance from intersection to final destination
              final distanceToDestination = distanceMeters(intersectPoint, dest);
              
              debugPrint('   ⚠️  Route 2 is short (${(route2Length).toStringAsFixed(0)}m)');
              debugPrint('   Distance from intersection to destination: ${(distanceToDestination).toStringAsFixed(0)}m');
              
              // If total walking distance from intersection is < 500m, walk to destination
              if (distanceToDestination < 500.0) {
                debugPrint('   Replacing Route 2 with walking to destination');
                final walkingToDestination = await _fetchWalkingDirections(
                  intersectPoint,
                  dest
                );
                
                debugInfo['case'] = 'single_route_with_walking';
                debugInfo['routes'] = [startRoute.slug];
                debugInfo['walkingDistance'] = distanceToDestination;
                
                return _buildSingleRouteResult(
                  startRoute, 
                  walkingToDestination, 
                  googlePath, 
                  debugInfo
                );
              }
            }
            
            debugInfo['case'] = 'two_routes_intersecting';
            debugInfo['routes'] = [startRoute.slug, endRoute.slug];
            debugInfo['intersectionPoint'] = {
              'lat': intersectPoint.latitude,
              'lng': intersectPoint.longitude,
            };
            
            return _buildTwoRouteResult(
              startRoute, endRoute, googlePath, debugInfo, 
              trimmedRoute1: trimmedRoute1,
              trimmedRoute2: trimmedRoute2,
              intersects: true
            );
          }
        }
      }

      // APPROACH 2: If no intersection found, check for walkable gaps
      for (final startRoute in startCandidates) {
        for (final endRoute in endCandidates) {
          if (startRoute.slug == endRoute.slug && 
              startRoute.partIndex == endRoute.partIndex) {
            continue; // Same route, already checked in case 1
          }

          final connection = findConnectionPoint(
            startRoute.trimmedPoints, 
            endRoute.trimmedPoints
          );
          
          if (connection != null) {
            final gap = connection['distance'] as double;
            final point1 = connection['point1'] as LatLng;
            final point2 = connection['point2'] as LatLng;
            
            // Calculate length of second route
            double route2Length = 0.0;
            for (int i = 0; i < endRoute.trimmedPoints.length - 1; i++) {
              route2Length += distanceMeters(endRoute.trimmedPoints[i], endRoute.trimmedPoints[i + 1]);
            }
            
            // If second route is less than 500m, extend walking gap allowance to 1km
            final effectiveWalkingGap = route2Length < 500.0 ? 1000.0 : maxWalkingGap;
            
            if (gap <= effectiveWalkingGap) {
              debugPrint('✅ Found routes with walking connection:');
              debugPrint('   ${startRoute.slug} (nearest to user)');
              debugPrint('   → Walk ${(gap).toStringAsFixed(0)}m');
              debugPrint('   → ${endRoute.slug} (nearest to destination, ${(route2Length).toStringAsFixed(0)}m)');
              debugPrint('   Effective walking gap allowed: ${(effectiveWalkingGap).toStringAsFixed(0)}m');
              
              // Get walking path between the two routes
              final walkingPath = await _fetchWalkingDirections(point1, point2);
              
              debugInfo['case'] = 'two_routes_with_walking';
              debugInfo['routes'] = [startRoute.slug, endRoute.slug];
              debugInfo['walkingDistance'] = gap;
              
              return _buildTwoRouteResult(
                startRoute, endRoute, googlePath, debugInfo,
                walkingPath: walkingPath,
                gap: gap
              );
            }
          }
        }
      }

      // CASE 3: Find connecting route
      debugPrint('');
      debugPrint('🔍 Case 3: Looking for three-route connection...');
      if (startCandidates.isNotEmpty && endCandidates.isNotEmpty) {
        final startRoute = startCandidates.first;
        final endRoute = endCandidates.first;

        // Look for a route that connects the two
        for (final connector in segments) {
          if (connector.slug == startRoute.slug || connector.slug == endRoute.slug) {
            continue;
          }

          // Find intersection between start route and connector
          final intersection1 = findIntersectionPoint(
            startRoute.trimmedPoints, 
            connector.trimmedPoints, 
            thresholdMeters: intersectionThreshold
          );
          
          // Find intersection between connector and end route
          final intersection2 = findIntersectionPoint(
            connector.trimmedPoints, 
            endRoute.trimmedPoints, 
            thresholdMeters: intersectionThreshold
          );

          if (intersection1 != null && intersection2 != null) {
            final intersectPoint1 = intersection1['point'] as LatLng;
            final route1Idx = intersection1['route1Index'] as int;
            final connector1Idx = intersection1['route2Index'] as int;
            
            final intersectPoint2 = intersection2['point'] as LatLng;
            final connector2Idx = intersection2['route1Index'] as int;
            final route2Idx = intersection2['route2Index'] as int;
            
            debugPrint('✅ Found connecting route:');
            debugPrint('   ${startRoute.slug} → ${connector.slug} → ${endRoute.slug}');
            debugPrint('   Intersection 1 at indices: [$route1Idx, $connector1Idx]');
            debugPrint('   Intersection 2 at indices: [$connector2Idx, $route2Idx]');
            
            // Trim route1 from start to first intersection
            final trimmedRoute1 = trimRouteToIndex(
              startRoute.trimmedPoints,
              route1Idx,
              intersectPoint1
            );
            
            // Trim connector from first intersection to second intersection
            final trimmedConnector = <LatLng>[intersectPoint1];
            for (int i = connector1Idx + 1; i <= connector2Idx && i < connector.trimmedPoints.length; i++) {
              trimmedConnector.add(connector.trimmedPoints[i]);
            }
            if (distanceMeters(trimmedConnector.last, intersectPoint2) > 1.0) {
              trimmedConnector.add(intersectPoint2);
            }
            
            // Trim route2 from second intersection to end
            final trimmedRoute2 = trimRouteFromIndex(
              endRoute.trimmedPoints,
              route2Idx,
              intersectPoint2
            );
            
            debugInfo['case'] = 'three_route_connection';
            debugInfo['routes'] = [startRoute.slug, connector.slug, endRoute.slug];
            debugInfo['intersection1'] = {
              'lat': intersectPoint1.latitude,
              'lng': intersectPoint1.longitude,
            };
            debugInfo['intersection2'] = {
              'lat': intersectPoint2.latitude,
              'lng': intersectPoint2.longitude,
            };
            
            return _buildThreeRouteResult(
              startRoute, connector, endRoute, googlePath, debugInfo,
              trimmedRoute1: trimmedRoute1,
              trimmedConnector: trimmedConnector,
              trimmedRoute2: trimmedRoute2
            );
          }
        }
      }

      // LAST RESORT: Try to find intersecting routes with relaxed constraints
      debugPrint('');
      debugPrint('🔍 Last Resort: Searching for ANY intersecting routes with relaxed constraints...');
      
      const relaxedStartDistance = 3000.0; // 3km from start
      const relaxedEndDistance = 3000.0; // 3km to destination
      const relaxedIntersectionThreshold = 200.0; // 200m intersection threshold
      
      // Get all routes within relaxed distance from start
      final relaxedStartCandidates = segments
          .where((s) => s.distanceToStart <= relaxedStartDistance)
          .toList()
        ..sort((a, b) => a.distanceToStart.compareTo(b.distanceToStart));
      
      // Get all routes within relaxed distance from destination
      final relaxedEndCandidates = segments
          .where((s) => s.distanceToEnd <= relaxedEndDistance)
          .toList()
        ..sort((a, b) => a.distanceToEnd.compareTo(b.distanceToEnd));
      
      debugPrint('   Relaxed start candidates: ${relaxedStartCandidates.length}');
      debugPrint('   Relaxed end candidates: ${relaxedEndCandidates.length}');
      
      // PRIORITY 1: Try two-route intersections with relaxed constraints
      for (final startRoute in relaxedStartCandidates) {
        for (final endRoute in relaxedEndCandidates) {
          if (startRoute.slug == endRoute.slug && 
              startRoute.partIndex == endRoute.partIndex) {
            continue;
          }
          
          final intersection = findIntersectionPoint(
            startRoute.trimmedPoints, 
            endRoute.trimmedPoints, 
            thresholdMeters: relaxedIntersectionThreshold
          );
          
          if (intersection != null) {
            final intersectPoint = intersection['point'] as LatLng;
            final route1Idx = intersection['route1Index'] as int;
            final route2Idx = intersection['route2Index'] as int;
            
            debugPrint('✅ Found intersecting routes with relaxed constraints (Case 2):');
            debugPrint('   ${startRoute.slug} (${(startRoute.distanceToStart).toStringAsFixed(0)}m from user)');
            debugPrint('   → ${endRoute.slug} (${(endRoute.distanceToEnd).toStringAsFixed(0)}m to destination)');
            
            final trimmedRoute1 = trimRouteToIndex(
              startRoute.trimmedPoints, 
              route1Idx, 
              intersectPoint
            );
            
            final trimmedRoute2 = trimRouteFromIndex(
              endRoute.trimmedPoints, 
              route2Idx, 
              intersectPoint
            );
            
            debugInfo['case'] = 'two_routes_intersecting_relaxed';
            debugInfo['routes'] = [startRoute.slug, endRoute.slug];
            debugInfo['intersectionPoint'] = {
              'lat': intersectPoint.latitude,
              'lng': intersectPoint.longitude,
            };
            
            return _buildTwoRouteResult(
              startRoute, endRoute, googlePath, debugInfo, 
              trimmedRoute1: trimmedRoute1,
              trimmedRoute2: trimmedRoute2,
              intersects: true
            );
          }
        }
      }
      
      // PRIORITY 2: Try three-route intersections with relaxed constraints
      for (final startRoute in relaxedStartCandidates) {
        for (final endRoute in relaxedEndCandidates) {
          if (startRoute.slug == endRoute.slug && 
              startRoute.partIndex == endRoute.partIndex) {
            continue;
          }
          
          // Look for a connector route
          for (final connector in segments) {
            if (connector.slug == startRoute.slug || connector.slug == endRoute.slug) {
              continue;
            }

            final intersection1 = findIntersectionPoint(
              startRoute.trimmedPoints, 
              connector.trimmedPoints, 
              thresholdMeters: relaxedIntersectionThreshold
            );
            
            final intersection2 = findIntersectionPoint(
              connector.trimmedPoints, 
              endRoute.trimmedPoints, 
              thresholdMeters: relaxedIntersectionThreshold
            );

            if (intersection1 != null && intersection2 != null) {
              final intersectPoint1 = intersection1['point'] as LatLng;
              final route1Idx = intersection1['route1Index'] as int;
              final connector1Idx = intersection1['route2Index'] as int;
              
              final intersectPoint2 = intersection2['point'] as LatLng;
              final connector2Idx = intersection2['route1Index'] as int;
              final route2Idx = intersection2['route2Index'] as int;
              
              debugPrint('✅ Found three-route connection with relaxed constraints (Case 3):');
              debugPrint('   ${startRoute.slug} (${(startRoute.distanceToStart).toStringAsFixed(0)}m from user)');
              debugPrint('   → ${connector.slug}');
              debugPrint('   → ${endRoute.slug} (${(endRoute.distanceToEnd).toStringAsFixed(0)}m to destination)');
              
              final trimmedRoute1 = trimRouteToIndex(
                startRoute.trimmedPoints,
                route1Idx,
                intersectPoint1
              );
              
              final trimmedConnector = <LatLng>[intersectPoint1];
              for (int i = connector1Idx + 1; i <= connector2Idx && i < connector.trimmedPoints.length; i++) {
                trimmedConnector.add(connector.trimmedPoints[i]);
              }
              if (distanceMeters(trimmedConnector.last, intersectPoint2) > 1.0) {
                trimmedConnector.add(intersectPoint2);
              }
              
              final trimmedRoute2 = trimRouteFromIndex(
                endRoute.trimmedPoints,
                route2Idx,
                intersectPoint2
              );
              
              debugInfo['case'] = 'three_route_connection_relaxed';
              debugInfo['routes'] = [startRoute.slug, connector.slug, endRoute.slug];
              debugInfo['intersection1'] = {
                'lat': intersectPoint1.latitude,
                'lng': intersectPoint1.longitude,
              };
              debugInfo['intersection2'] = {
                'lat': intersectPoint2.latitude,
                'lng': intersectPoint2.longitude,
              };
              
              return _buildThreeRouteResult(
                startRoute, connector, endRoute, googlePath, debugInfo,
                trimmedRoute1: trimmedRoute1,
                trimmedConnector: trimmedConnector,
                trimmedRoute2: trimmedRoute2
              );
            }
          }
        }
      }

      // FINAL FALLBACK: Use Google route
      debugPrint('');
      debugPrint('⚠️  No suitable route combination found even with relaxed constraints');
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
    List<LatLng>? walkingPath,
    List<LatLng> googlePath,
    Map<String, dynamic> debugInfo,
  ) {
    final polylines = <Polyline>[];
    
    // Main route polyline
    polylines.add(Polyline(
      polylineId: PolylineId('${segment.slug}-${segment.partIndex}'),
      points: segment.trimmedPoints,
      color: _colorPool[0],
      width: 5,
    ));

    // Add walking path if provided
    if (walkingPath != null && walkingPath.isNotEmpty) {
      polylines.add(Polyline(
        polylineId: const PolylineId('walking_path'),
        points: walkingPath,
        color: Colors.grey,
        width: 4,
        patterns: [PatternItem.dash(20), PatternItem.gap(10)], // Dashed line
      ));
    }

    final stitchedPath = walkingPath != null && walkingPath.isNotEmpty
        ? [...segment.trimmedPoints, ...walkingPath]
        : segment.trimmedPoints;

    return RoutingResult(
      polylines: polylines,
      stitchedPath: stitchedPath,
      googlePath: googlePath,
      debugInfo: debugInfo,
    );
  }

  static RoutingResult _buildTwoRouteResult(
    RouteSegment route1,
    RouteSegment route2,
    List<LatLng> googlePath,
    Map<String, dynamic> debugInfo, {
    List<LatLng>? trimmedRoute1, // Custom trimmed route 1 (for intersections)
    List<LatLng>? trimmedRoute2, // Custom trimmed route 2 (for intersections)
    List<LatLng>? walkingPath, // Walking path between routes
    bool intersects = false,
    double? gap,
  }) {
    final polylines = <Polyline>[];
    
    // Use custom trimmed routes if provided, otherwise use default trimmed points
    final route1Points = trimmedRoute1 ?? route1.trimmedPoints;
    final route2Points = trimmedRoute2 ?? route2.trimmedPoints;
    
    // Add first route
    polylines.add(Polyline(
      polylineId: PolylineId('${route1.slug}-${route1.partIndex}'),
      points: route1Points,
      color: _colorPool[0],
      width: 5,
    ));

    // Add walking path if provided (between routes)
    if (walkingPath != null && walkingPath.isNotEmpty) {
      polylines.add(Polyline(
        polylineId: const PolylineId('walking_connection'),
        points: walkingPath,
        color: Colors.grey,
        width: 4,
        patterns: [PatternItem.dash(20), PatternItem.gap(10)], // Dashed line
      ));
    }

    // Add second route
    polylines.add(Polyline(
      polylineId: PolylineId('${route2.slug}-${route2.partIndex}'),
      points: route2Points,
      color: _colorPool[1],
      width: 5,
    ));

    // Build stitched path
    final stitchedPath = <LatLng>[
      ...route1Points,
      if (walkingPath != null && walkingPath.isNotEmpty) ...walkingPath,
      ...route2Points,
    ];

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
    Map<String, dynamic> debugInfo, {
    List<LatLng>? trimmedRoute1,
    List<LatLng>? trimmedConnector,
    List<LatLng>? trimmedRoute2,
  }) {
    // Use custom trimmed routes if provided, otherwise use default trimmed points
    final route1Points = trimmedRoute1 ?? route1.trimmedPoints;
    final connectorPoints = trimmedConnector ?? connector.trimmedPoints;
    final route2Points = trimmedRoute2 ?? route2.trimmedPoints;
    
    final polylines = [
      Polyline(
        polylineId: PolylineId('${route1.slug}-${route1.partIndex}'),
        points: route1Points,
        color: _colorPool[0],
        width: 5,
      ),
      Polyline(
        polylineId: PolylineId('${connector.slug}-${connector.partIndex}'),
        points: connectorPoints,
        color: _colorPool[1],
        width: 5,
      ),
      Polyline(
        polylineId: PolylineId('${route2.slug}-${route2.partIndex}'),
        points: route2Points,
        color: _colorPool[2],
        width: 5,
      ),
    ];

    final stitchedPath = [...route1Points, ...connectorPoints, ...route2Points];

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