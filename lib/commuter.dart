import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'components/logout_button.dart';
import 'components/search_field.dart';
import 'components/distance_modal.dart';
import 'components/recenter.dart';
import 'package:geolocator/geolocator.dart';
import 'services/conductor_map_render.dart';
import 'services/routing_service.dart';

class CommuterPage extends StatefulWidget {
  const CommuterPage({Key? key}) : super(key: key);

  @override
  State<CommuterPage> createState() => _CommuterPageState();
}

class _CommuterPageState extends State<CommuterPage> {
  GoogleMapController? _mapController;
  Set<Polyline> _polylines = {};
  Set<Polygon> _polygons = {};
  Set<Marker> _markers = {};
  bool _myLocationEnabled = false;
  bool _isRouting = false;
  bool _isModalExpanded = false;
  bool _sakayPressed = false; // Track if Sakay button was pressed
  List<RouteInfo> _routeInfoList = [];
  List<List<RouteInfo>> _allRouteOptions = []; // Store all 3 route options
  List<RoutingResult> _routingResults = []; // Store routing results for switching
  // ignore: unused_field
  int _currentRouteIndex = 0; // Track which route option is currently displayed

  static const CameraPosition _initialPosition = CameraPosition(
    target: LatLng(7.1907, 125.4553),
    zoom: 12,
  );

  @override
  void initState() {
    super.initState();
    _ensureLocationEnabled();
  }

  Future<void> _ensureLocationEnabled() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
        setState(() => _myLocationEnabled = true);
      }
    } catch (e) {
      debugPrint('Error enabling location: $e');
    }
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
  }

  /// Calculate distance of a polyline in kilometers
  double _calculatePolylineDistance(List<LatLng> points) {
    if (points.length < 2) return 0.0;
    double totalMeters = 0.0;
    for (int i = 0; i < points.length - 1; i++) {
      totalMeters += RoutingService.distanceMeters(points[i], points[i + 1]);
    }
    return totalMeters / 1000.0; // Convert to kilometers
  }

  /// Extract route name from polyline ID and convert to display format
  /// Converts "bago-aplaya" to "Bago Aplaya" (camel case with spaces)
  String _extractRouteName(String polylineId) {
    // polylineId format is usually "slug-partIndex" or "slug_partIndex"
    final parts = polylineId.split(RegExp(r'[-_]'));
    final slug = parts.isNotEmpty ? parts[0] : polylineId;
    
    // Split by hyphens and capitalize each word
    final words = slug.split('-');
    final capitalizedWords = words.map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).toList();
    
    return capitalizedWords.join(' ');
  }

  /// Load a route by name using the conductor map service.
  Future<void> loadRoute(String name) async {
    final layers = await ConductorMapRender.getLayersForRoute(name);
    setState(() {
      _polylines = layers.polylines.toSet();
      _polygons = layers.polygons.toSet();
      _markers = layers.markers.toSet();
    });

    if (layers.polylines.isNotEmpty && _mapController != null) {
      // Fit bounds to first polyline
      final points = layers.polylines.first.points;
      double minLat = points.first.latitude, maxLat = points.first.latitude;
      double minLng = points.first.longitude, maxLng = points.first.longitude;
      for (final p in points) {
        minLat = p.latitude < minLat ? p.latitude : minLat;
        maxLat = p.latitude > maxLat ? p.latitude : maxLat;
        minLng = p.longitude < minLng ? p.longitude : minLng;
        maxLng = p.longitude > maxLng ? p.longitude : maxLng;
      }
      final bounds = LatLngBounds(southwest: LatLng(minLat, minLng), northeast: LatLng(maxLat, maxLng));
      _mapController?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 40));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: _onMapCreated,
            initialCameraPosition: _initialPosition,
            myLocationEnabled: _myLocationEnabled,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            polylines: _polylines,
            polygons: _polygons,
            markers: _markers,
          ),

          // Top-left logout button
          LogoutButton(onPressed: () => Navigator.of(context).maybePop()),
          // Search field placed to the right of the logout button (top:50, left:90)
          SearchField(
            top: 50,
            left: 80,
            onPlaceSelected: (loc, desc) async {
              // Try to get device location as start point
              setState(() {
                _isRouting = true;
                _isModalExpanded = false; // Hide modal while routing
                _sakayPressed = false; // Reset Sakay state for new search
                _routeInfoList = []; // Clear previous route info
                _allRouteOptions = []; // Clear previous route options
                _routingResults = []; // Clear previous routing results
              });
              try {
                final pos = await Geolocator.getCurrentPosition();
                final start = LatLng(pos.latitude, pos.longitude);

                // Build multiple route options (up to 3)
                final routingOptions = await RoutingService.buildMultipleRoutes(start, loc);

                // If no routes found, show a user-friendly message
                if (routingOptions.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Sorry, no routes found'),
                    duration: Duration(seconds: 4),
                  ));
                  // fallback: just show the selected location
                  await _mapController?.animateCamera(CameraUpdate.newLatLngZoom(loc, 15));
                  setState(() {
                    _markers = {Marker(markerId: const MarkerId('search_result'), position: loc, infoWindow: InfoWindow(title: desc))};
                  });
                  return;
                }

                // Show SnackBar if fell back to Google route only
                if (routingOptions.first.usedFallback) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('No public routes found. Showing optimal route.'),
                    duration: Duration(seconds: 3),
                    backgroundColor: Colors.orange,
                  ));
                }

                // Build route info list for each routing option
                final allRouteOptions = <List<RouteInfo>>[];
                for (final routing in routingOptions) {
                  final routeInfoList = <RouteInfo>[];
                  for (final polyline in routing.polylines) {
                    final routeName = _extractRouteName(polyline.polylineId.value);
                    final distance = _calculatePolylineDistance(polyline.points);
                    final color = polyline.color; // Get the color from the polyline
                    routeInfoList.add(RouteInfo(name: routeName, kilometers: distance, color: color));
                  }
                  allRouteOptions.add(routeInfoList);
                }

                // Display the first route option by default
                final firstRouting = routingOptions.first;

                setState(() {
                  // Store all routing results
                  _routingResults = routingOptions;
                  _allRouteOptions = allRouteOptions;
                  _currentRouteIndex = 0;
                  
                  // Display first route on map
                  _polylines = firstRouting.polylines.toSet();
                  
                  // markers: start and destination
                  _markers = {
                    Marker(markerId: const MarkerId('start'), position: start, infoWindow: const InfoWindow(title: 'You')),
                    Marker(markerId: const MarkerId('dest'), position: loc, infoWindow: InfoWindow(title: desc)),
                  };
                  
                  // Update route info and show modal
                  _routeInfoList = allRouteOptions.first;
                  _isModalExpanded = true;
                });

                // fit camera to stitched path if available, otherwise to dest
                if (firstRouting.stitchedPath.isNotEmpty && _mapController != null) {
                  double minLat = firstRouting.stitchedPath.first.latitude, maxLat = firstRouting.stitchedPath.first.latitude;
                  double minLng = firstRouting.stitchedPath.first.longitude, maxLng = firstRouting.stitchedPath.first.longitude;
                  for (final p in firstRouting.stitchedPath) {
                    minLat = p.latitude < minLat ? p.latitude : minLat;
                    maxLat = p.latitude > maxLat ? p.latitude : maxLat;
                    minLng = p.longitude < minLng ? p.longitude : minLng;
                    maxLng = p.longitude > maxLng ? p.longitude : maxLng;
                  }
                  final bounds = LatLngBounds(southwest: LatLng(minLat, minLng), northeast: LatLng(maxLat, maxLng));
                  await _mapController?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 40));
                } else {
                  await _mapController?.animateCamera(CameraUpdate.newLatLngZoom(loc, 15));
                }
              } catch (e) {
                debugPrint('Routing failed or location unavailable: $e');
                // If routing couldn't find nearby routes, show a SnackBar with the reason
                if (e is RouteNotFoundException) {
                  // Show a friendly, consistent message when routing couldn't find a connection
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Sorry, no routes found'),
                    duration: Duration(seconds: 4),
                  ));
                } else {
                  // generic error
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Routing failed — showing selected location'),
                    duration: Duration(seconds: 3),
                  ));
                }

                // fallback: just show the selected location
                await _mapController?.animateCamera(CameraUpdate.newLatLngZoom(loc, 15));
                setState(() {
                  _markers = {Marker(markerId: const MarkerId('search_result'), position: loc, infoWindow: InfoWindow(title: desc))};
                });
              } finally {
                setState(() => _isRouting = false);
              }
            },
          ),
          // routing overlay
          if (_isRouting)
            Positioned.fill(
              child: Container(
                color: Colors.black26,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 80,
                          height: 80,
                          child: Image.network('https://media.giphy.com/media/3o7TKtnuHOHHUjR38Y/giphy.gif', fit: BoxFit.contain),
                        ),
                        const SizedBox(height: 8),
                        const Text('Finding route...', style: TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // Distance modal - shows route info and fare
          if (_routeInfoList.isNotEmpty)
            DistanceModal(
              isExpanded: _isModalExpanded,
              onVerticalDragEnd: (details) {
                if (details.primaryVelocity != null) {
                  if (details.primaryVelocity! < -300) {
                    setState(() => _isModalExpanded = true);
                  } else if (details.primaryVelocity! > 300) {
                    setState(() => _isModalExpanded = false);
                  }
                }
              },
              routes: _routeInfoList,
              allRouteOptions: _allRouteOptions,
              onRouteChanged: (index) {
                // Switch to the selected route option on the map
                if (index < _routingResults.length) {
                  setState(() {
                    _currentRouteIndex = index;
                    _polylines = _routingResults[index].polylines.toSet();
                    _routeInfoList = _allRouteOptions[index];
                  });
                }
              },
              onSakayPressed: (selectedIndex) {
                // Keep only the selected route and clear others
                if (selectedIndex < _routingResults.length) {
                  setState(() {
                    _sakayPressed = true;
                    // Keep only the selected route option
                    _allRouteOptions = [_allRouteOptions[selectedIndex]];
                    _routingResults = [_routingResults[selectedIndex]];
                    _currentRouteIndex = 0;
                    // Set initial state: first subroute featured, others greyed
                    _polylines = _greyOutNonFeaturedSubroutes(0);
                  });
                }
              },
              onSubrouteChanged: (subrouteIndex) {
                // Grey out non-featured subroutes when swiping
                if (_sakayPressed && _routingResults.isNotEmpty) {
                  setState(() {
                    _polylines = _greyOutNonFeaturedSubroutes(subrouteIndex);
                  });
                }
              },
            ),
          
          // Recenter button - positioned dynamically based on modal state
          RecenterButton(
            bottom: _isModalExpanded 
                ? (_sakayPressed 
                    ? MediaQuery.of(context).size.height * 0.32  // Above collapsed Sakay modal
                    : MediaQuery.of(context).size.height * 0.40) // Above expanded modal
                : MediaQuery.of(context).size.height * 0.12, // Above collapsed modal
            right: 16,
            onPressed: () async {
              // Recenter to user's current location
              try {
                final pos = await Geolocator.getCurrentPosition();
                final userLocation = LatLng(pos.latitude, pos.longitude);
                _mapController?.animateCamera(
                  CameraUpdate.newLatLngZoom(userLocation, 15),
                );
              } catch (e) {
                debugPrint('Error recentering: $e');
              }
            },
          ),
        ],
      ),
    );
  }

  // Grey out non-featured subroutes while keeping the featured one in full color
  Set<Polyline> _greyOutNonFeaturedSubroutes(int featuredSubrouteIndex) {
    if (_routingResults.isEmpty) return {};
    
    Set<Polyline> updatedPolylines = {};
    final polylines = _routingResults.first.polylines;
    
    // Get only jeepney route polylines (exclude walking routes)
    final jeepneyPolylines = polylines.where((p) {
      final routeName = _extractRouteName(p.polylineId.value).toLowerCase();
      return !routeName.contains('walk');
    }).toList();
    
    // Get all polylines including walking routes
    for (int i = 0; i < polylines.length; i++) {
      final polyline = polylines[i];
      final routeName = _extractRouteName(polyline.polylineId.value).toLowerCase();
      final isWalkingRoute = routeName.contains('walk');
      
      if (isWalkingRoute) {
        // Keep walking routes as-is (grey)
        updatedPolylines.add(polyline);
      } else {
        // Find the index of this jeepney route
        final jeepneyIndex = jeepneyPolylines.indexOf(polyline);
        
        if (jeepneyIndex == featuredSubrouteIndex) {
          // Keep featured subroute in full color
          updatedPolylines.add(polyline);
        } else {
          // Grey out non-featured subroutes
          updatedPolylines.add(polyline.copyWith(
            colorParam: polyline.color.withOpacity(0.3),
            widthParam: 4,
          ));
        }
      }
    }
    
    return updatedPolylines;
  }
}
