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
  final Map<String, dynamic> debugInfo; // Added for debugging

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
      debugPrint('   Routes: $_routeIndexCache');
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
      
      debugPrint('✅ Loaded ${_routeIndexCache!.length} routes:');
      for (int i = 0; i < _routeIndexCache!.length; i++) {
        debugPrint('   [$i] ${_routeIndexCache![i]}');
      }
      
      return _routeIndexCache!;
    } catch (e, st) {
      debugPrint('❌ fetchRouteIndex EXCEPTION: $e');
      debugPrint('   Stack trace: $st');
      return [];
    }
  }

  static Future<List<List<LatLng>>> loadRouteLines(String slug) async {
    debugPrint('');
    debugPrint('───────────────────────────────────────────');
    debugPrint('📥 LOADING ROUTE: $slug');
    debugPrint('───────────────────────────────────────────');
    
    if (_routeCache.containsKey(slug)) {
      debugPrint('✅ Cache hit for $slug (${_routeCache[slug]!.length} parts)');
      return _routeCache[slug]!;
    }

    final supabaseUrl = dotenv.env['SUPABASE_URL'] ?? '';
    final bucket = dotenv.env['SUPABASE_BUCKET'] ?? 'Jroute';
    
    debugPrint('🔧 Config:');
    debugPrint('   SUPABASE_URL: ${supabaseUrl.isEmpty ? "❌ EMPTY" : supabaseUrl}');
    debugPrint('   BUCKET: $bucket');
    
    if (supabaseUrl.isEmpty) {
      debugPrint('❌ Missing SUPABASE_URL');
      return [];
    }

    try {
      final filePath = 'routes/$slug.geojson';
      final url = Uri.parse('$supabaseUrl/storage/v1/object/public/$bucket/$filePath');
      debugPrint('🌐 Fetching GeoJSON: $url');

      final res = await http.get(url);
      debugPrint('📡 Response status: ${res.statusCode}');
      
      if (res.statusCode != 200) {
        debugPrint('❌ Failed to fetch $filePath (${res.statusCode})');
        debugPrint('   Response: ${res.body.substring(0, math.min(200, res.body.length))}');
        return [];
      }

      debugPrint('✅ Parsing GeoJSON...');
      final data = json.decode(res.body);
      
      if (data is! Map<String, dynamic>) {
        debugPrint('❌ Invalid JSON structure for $slug');
        return [];
      }

      final features = (data['features'] as List<dynamic>?) ?? [];
      debugPrint('📊 Found ${features.length} features');
      
      if (features.isEmpty) {
        debugPrint('⚠️ No features found in $slug');
      }

      final parts = <List<LatLng>>[];
      for (int i = 0; i < features.length; i++) {
        final f = features[i];
        debugPrint('   Processing feature [$i]...');
        
        final geometry = (f as Map<String, dynamic>)['geometry'] as Map<String, dynamic>?;
        if (geometry == null) {
          debugPrint('      ⚠️ No geometry');
          continue;
        }

        final type = (geometry['type'] as String?) ?? '';
        debugPrint('      Type: $type');
        
        final coords = geometry['coordinates'];
        if (coords == null) {
          debugPrint('      ⚠️ No coordinates');
          continue;
        }

        List<List<dynamic>> lineGroups = [];

        if (type == 'LineString') {
          lineGroups = [coords as List<dynamic>];
        } else if (type == 'MultiLineString') {
          lineGroups = (coords as List<dynamic>).cast<List<dynamic>>();
        } else {
          debugPrint('      ⚠️ Unsupported type: $type');
        }

        debugPrint('      Line groups: ${lineGroups.length}');

        for (int j = 0; j < lineGroups.length; j++) {
          final line = lineGroups[j];
          final pts = line.map((p) {
            final a = p as List<dynamic>;
            return LatLng((a[1] as num).toDouble(), (a[0] as num).toDouble());
          }).toList();

          if (pts.isNotEmpty) {
            parts.add(pts);
            debugPrint('      ✅ Added part with ${pts.length} points');
          }
        }
      }

      debugPrint('✅ Loaded ${parts.length} parts for $slug');
      _routeCache[slug] = parts;
      return parts;
    } catch (e, st) {
      debugPrint('❌ loadRouteLines EXCEPTION for $slug: $e');
      debugPrint('   Stack trace: $st');
      return [];
    }
  }

  static Future<List<LatLng>> fetchGoogleDirections(LatLng start, LatLng dest) async {
    debugPrint('');
    debugPrint('═══════════════════════════════════════════');
    debugPrint('🗺️  FETCHING GOOGLE DIRECTIONS');
    debugPrint('═══════════════════════════════════════════');
    debugPrint('📍 From: ${start.latitude}, ${start.longitude}');
    debugPrint('📍 To: ${dest.latitude}, ${dest.longitude}');
    
    final apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';
    if (apiKey.isEmpty) {
      debugPrint('❌ Google Maps API key not configured');
      throw RouteNotFoundException('Google Maps API key not configured');
    }
    
    debugPrint('✅ API Key present: ${apiKey.substring(0, 10)}...');

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
      debugPrint('🌐 Making request...');
      final res = await http.get(url);
      debugPrint('📡 Response status: ${res.statusCode}');
      
      if (res.statusCode != 200) {
        debugPrint('❌ Request failed');
        throw RouteNotFoundException('Directions API request failed');
      }

      final data = json.decode(res.body) as Map<String, dynamic>;
      final status = data['status'] as String?;
      debugPrint('📊 API Status: $status');
      
      if (status != 'OK') {
        debugPrint('❌ API Error: $status');
        if (data.containsKey('error_message')) {
          debugPrint('   Error message: ${data['error_message']}');
        }
        throw RouteNotFoundException('Directions API error: $status');
      }

      final routes = data['routes'] as List<dynamic>?;
      debugPrint('✅ Found ${routes?.length ?? 0} route(s)');
      
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
      debugPrint('✅ Decoded ${decoded.length} points from Google route');
      
      return decoded;
    } catch (e, st) {
      debugPrint('❌ fetchGoogleDirections EXCEPTION: $e');
      debugPrint('   Stack trace: $st');
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

  static double calculateOverlap(
    List<LatLng> routePart,
    List<LatLng> googlePath,
    {double thresholdMeters = 50.0}
  ) {
    if (routePart.isEmpty || googlePath.isEmpty) return 0.0;

    int overlappingSegments = 0;
    int totalSegments = routePart.length - 1;
    if (totalSegments <= 0) return 0.0;

    for (int i = 0; i < routePart.length - 1; i++) {
      final rp1 = routePart[i];
      final rp2 = routePart[i + 1];
      final midpoint = LatLng(
        (rp1.latitude + rp2.latitude) / 2,
        (rp1.longitude + rp2.longitude) / 2,
      );

      bool isClose = false;
      for (int j = 0; j < googlePath.length - 1; j++) {
        final gp1 = googlePath[j];
        final gp2 = googlePath[j + 1];
        final proj = closestPointOnSegment(midpoint, gp1, gp2);
        final projPoint = proj['point'] as LatLng;
        final dist = distanceMeters(midpoint, projPoint);
        
        if (dist <= thresholdMeters) {
          isClose = true;
          break;
        }
      }
      
      if (isClose) overlappingSegments++;
    }

    return overlappingSegments / totalSegments;
  }

  static Future<List<Map<String, dynamic>>> findBestOverlappingRoutes(
    List<LatLng> googlePath,
    {double minOverlap = 0.3, double thresholdMeters = 50.0}
  ) async {
    debugPrint('');
    debugPrint('═══════════════════════════════════════════');
    debugPrint('🔍 FINDING OVERLAPPING ROUTES');
    debugPrint('═══════════════════════════════════════════');
    debugPrint('⚙️  Parameters:');
    debugPrint('   Google path points: ${googlePath.length}');
    debugPrint('   Min overlap: ${(minOverlap * 100).toStringAsFixed(1)}%');
    debugPrint('   Threshold: ${thresholdMeters}m');
    
    final slugs = await fetchRouteIndex();
    debugPrint('');
    debugPrint('📋 Checking ${slugs.length} routes from index');
    
    if (slugs.isEmpty) {
      debugPrint('❌ No routes in index - cannot find overlaps');
      return [];
    }
    
    final candidates = <Map<String, dynamic>>[];

    for (int idx = 0; idx < slugs.length; idx++) {
      final slug = slugs[idx];
      debugPrint('');
      debugPrint('🔄 [$idx/${slugs.length}] Checking route: $slug');
      
      final parts = await loadRouteLines(slug);
      debugPrint('   Found ${parts.length} part(s) in $slug');
      
      for (int partIndex = 0; partIndex < parts.length; partIndex++) {
        final part = parts[partIndex];
        debugPrint('   Analyzing part $partIndex (${part.length} points)...');
        
        final overlap = calculateOverlap(part, googlePath, thresholdMeters: thresholdMeters);
        debugPrint('   Overlap: ${(overlap * 100).toStringAsFixed(1)}% (threshold: ${(minOverlap * 100).toStringAsFixed(1)}%)');
        
        if (overlap >= minOverlap) {
          debugPrint('   ✅ MATCH! Adding to candidates');
          candidates.add({
            'slug': slug,
            'partIndex': partIndex,
            'part': part,
            'overlap': overlap,
          });
        } else {
          debugPrint('   ❌ Below threshold');
        }
      }
    }

    candidates.sort((a, b) => (b['overlap'] as double).compareTo(a['overlap'] as double));
    
    debugPrint('');
    debugPrint('═══════════════════════════════════════════');
    debugPrint('📊 OVERLAP RESULTS');
    debugPrint('═══════════════════════════════════════════');
    debugPrint('✅ Found ${candidates.length} matching route(s)');
    
    for (int i = 0; i < candidates.length; i++) {
      final c = candidates[i];
      debugPrint('   [$i] ${c['slug']} (part ${c['partIndex']}) - ${((c['overlap'] as double) * 100).toStringAsFixed(1)}% overlap');
    }
    
    return candidates;
  }

  static List<LatLng> trimRouteToOverlap(
    List<LatLng> routePart,
    List<LatLng> googlePath,
    {double thresholdMeters = 50.0}
  ) {
    if (routePart.isEmpty) return [];

    int? firstIndex;
    int? lastIndex;

    for (int i = 0; i < routePart.length; i++) {
      final point = routePart[i];
      
      bool isClose = false;
      for (int j = 0; j < googlePath.length - 1; j++) {
        final gp1 = googlePath[j];
        final gp2 = googlePath[j + 1];
        final proj = closestPointOnSegment(point, gp1, gp2);
        final projPoint = proj['point'] as LatLng;
        final dist = distanceMeters(point, projPoint);
        
        if (dist <= thresholdMeters) {
          isClose = true;
          break;
        }
      }
      
      if (isClose) {
        firstIndex ??= i;
        lastIndex = i;
      }
    }

    if (firstIndex == null || lastIndex == null) return [];
    final trimmed = routePart.sublist(firstIndex, lastIndex + 1);
    debugPrint('      Trimmed: ${routePart.length} → ${trimmed.length} points');
    return trimmed;
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
        debugPrint('❌ Google returned empty route');
        throw RouteNotFoundException('Google returned empty route');
      }

      final overlapThreshold = double.tryParse(dotenv.env['ROUTE_OVERLAP_THRESHOLD'] ?? '') ?? 500.0;
      final minOverlap = double.tryParse(dotenv.env['ROUTE_MIN_OVERLAP'] ?? '') ?? 0.3;
      
      debugPrint('');
      debugPrint('⚙️  Configuration:');
      debugPrint('   ROUTE_OVERLAP_THRESHOLD: ${overlapThreshold}m');
      debugPrint('   ROUTE_MIN_OVERLAP: ${(minOverlap * 100).toStringAsFixed(1)}%');
      
      debugInfo['overlapThreshold'] = overlapThreshold;
      debugInfo['minOverlap'] = minOverlap;
      
      final overlappingRoutes = await findBestOverlappingRoutes(
        googlePath,
        minOverlap: minOverlap,
        thresholdMeters: overlapThreshold,
      );
      
      debugInfo['candidatesFound'] = overlappingRoutes.length;

      if (overlappingRoutes.isEmpty) {
        debugPrint('');
        debugPrint('⚠️  NO OVERLAPPING ROUTES FOUND');
        debugPrint('   Falling back to Google route only');
        
        final googlePolyline = Polyline(
          polylineId: const PolylineId('google_route'),
          points: googlePath,
          color: Colors.grey,
          width: 5,
        );
        
        debugInfo['outcome'] = 'fallback_google';
        
        return RoutingResult(
          polylines: [googlePolyline],
          stitchedPath: googlePath,
          googlePath: googlePath,
          usedFallback: true,
          debugInfo: debugInfo,
        );
      }

      debugPrint('');
      debugPrint('🎨 Building polylines from matches...');
      
      final usedPolylines = <Polyline>[];
      final stitchedPath = <LatLng>[];
      int colorIdx = 0;

      final usedRoutes = <String>{};
      for (int i = 0; i < overlappingRoutes.length; i++) {
        final routeInfo = overlappingRoutes[i];
        final slug = routeInfo['slug'] as String;
        final part = routeInfo['part'] as List<LatLng>;
        final overlap = routeInfo['overlap'] as double;
        
        final routeKey = '$slug-${routeInfo['partIndex']}';
        
        debugPrint('   [$i] Processing $routeKey (${(overlap * 100).toStringAsFixed(1)}% overlap)');
        
        if (usedRoutes.contains(routeKey)) {
          debugPrint('      ⚠️ Already used, skipping');
          continue;
        }
        usedRoutes.add(routeKey);

        final trimmed = trimRouteToOverlap(part, googlePath, thresholdMeters: overlapThreshold);
        
        if (trimmed.isNotEmpty) {
          final color = _colorPool[colorIdx % _colorPool.length];
          colorIdx++;
          
          usedPolylines.add(Polyline(
            polylineId: PolylineId(routeKey),
            points: trimmed,
            color: color,
            width: 5,
          ));
          
          stitchedPath.addAll(trimmed);
          debugPrint('      ✅ Added polyline (${trimmed.length} points, color: $color)');
        } else {
          debugPrint('      ⚠️ Empty after trimming, skipping');
        }
      }

      debugInfo['polylinesCreated'] = usedPolylines.length;
      debugInfo['stitchedPathLength'] = stitchedPath.length;

      if (usedPolylines.isNotEmpty) {
        debugPrint('');
        debugPrint('╔═══════════════════════════════════════════╗');
        debugPrint('║     ✅ SUCCESS - USING CUSTOM ROUTES     ║');
        debugPrint('╚═══════════════════════════════════════════╝');
        debugPrint('Polylines: ${usedPolylines.length}');
        debugPrint('Stitched path points: ${stitchedPath.length}');
        
        debugInfo['outcome'] = 'success_custom';
        
        return RoutingResult(
          polylines: usedPolylines,
          stitchedPath: stitchedPath,
          googlePath: googlePath,
          debugInfo: debugInfo,
        );
      } else {
        debugPrint('');
        debugPrint('⚠️  No usable polylines after trimming');
        debugPrint('   Falling back to Google route');
        
        final googlePolyline = Polyline(
          polylineId: const PolylineId('google_route'),
          points: googlePath,
          color: Colors.grey,
          width: 5,
        );
        
        debugInfo['outcome'] = 'fallback_after_trim';
        
        return RoutingResult(
          polylines: [googlePolyline],
          stitchedPath: googlePath,
          googlePath: googlePath,
          usedFallback: true,
          debugInfo: debugInfo,
        );
      }
    } catch (e, st) {
      debugPrint('');
      debugPrint('╔═══════════════════════════════════════════╗');
      debugPrint('║     ❌ BUILD ROUTE FAILED                ║');
      debugPrint('╚═══════════════════════════════════════════╝');
      debugPrint('Error: $e');
      debugPrint('Stack trace: $st');
      
      debugInfo['outcome'] = 'error';
      debugInfo['error'] = e.toString();
      
      if (e is RouteNotFoundException) rethrow;
      throw RouteNotFoundException('Routing failed: $e');
    }
  }

  static void clearCache() {
    debugPrint('🗑️  Clearing route cache');
    debugPrint('   Routes in cache: ${_routeCache.length}');
    debugPrint('   Index cached: ${_routeIndexCache != null}');
    _routeCache.clear();
    _routeIndexCache = null;
    debugPrint('   ✅ Cache cleared');
  }
}