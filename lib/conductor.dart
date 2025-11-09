import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'components/bottom_modal.dart';
import 'components/logout_button.dart';
import 'components/passenger.dart';
import 'components/recenter.dart';
import 'package:geolocator/geolocator.dart';
import 'services/conductor_map_render.dart';
import 'login.dart'; // add this import near the top

class ConductorPage extends StatefulWidget {
  const ConductorPage({Key? key}) : super(key: key);

  @override
  _ConductorPageState createState() => _ConductorPageState();
}

class _ConductorPageState extends State<ConductorPage> {
  GoogleMapController? _mapController;
  final TextEditingController _routeController = TextEditingController();
  final TextEditingController _passengersController = TextEditingController();
  final FocusNode _routeFocusNode = FocusNode();
  final FocusNode _passengersFocusNode = FocusNode();

  bool _isExpanded = false;
  String _autocompleteSuggestion = '';
  bool _isLoadingRoute = false;
  bool _isPassengerView = false;
  int _maxPassengers = 0;
  bool _myLocationEnabled = false;

  static const List<String> _routes = [
    'BAGO APLAYA',
    'BANGKAL',
    'BARRIO OBRERO',
    'BUHANGIN VIA DACUDAO',
    'BUHANGIN VIA JP. LAUREL',
    'BUNAWAN VIA BUHANGIN',
    'BUNAWAN VIA SASA',
    'CALINAN',
    'CAMP CATITIPAN VIA JP. LAUREL',
    'CATALUNAN GRANDE',
    'ECOLAND',
    'EL RIO',
    'TORIL',
    "EMILY HOMES",
    "JADE VALLEY",
    "LASANG VIA BUHANGIN",
    "LASANG VIA SASA",
    "MAA AGDAO",
    "MAA BANKEROHAN",
    "MAGTUOD",
    "MATINA",
    "MATINA APLAYA",
    "MATINA CROSSING",
    "MATINA PANGI",
    "MINTAL",
    "PANACAN VIA CABAGUIO",
    "PANACA VIA SM CITY DAVAO",
    "PUAN",
    "ROUTE 1",
    "ROUTE 2",
    "ROUTE 3",
    "ROUTE 4",
    "ROUTE 5",
    "ROUTE 6",
    "ROUTE 7",
    "ROUTE 8",
    "ROUTE 9",
    "ROUTE 10",
    "ROUTE 11",
    "ROUTE 12",
    "ROUTE 13",
    "ROUTE 14",
    "ROUTE 15",
    "SASA VIA CABAGUIO",
    "SASA VIA JP LAUREL",
    "SASA VIA R. CASTILLO",
    "TALOMO",
    "TIBUNGCO VIA BUHANGIN",
    "TIBUNGCO VIA CABAGUIO",
    "TIBUNGCO VIA R. CASTILLO",
    "ULAS",
    "WAAN"
  ];

  Set<Polyline> _polylines = {};
  Set<Polygon> _polygons = {};
  Set<Marker> _markers = {};

  static const CameraPosition _initialPosition = CameraPosition(
    target: LatLng(7.1907, 125.4553), // Davao City
    zoom: 12.0,
  );

  @override
  void initState() {
    super.initState();
    _routeController.addListener(_onRouteTextChanged);
    // Ensure we request location permission so the native blue dot can be shown
    // on the GoogleMap. This will set `_myLocationEnabled` to true when allowed.
    _ensureLocationEnabled();
  }

  @override
  void dispose() {
    _routeController.removeListener(_onRouteTextChanged);
    _routeController.dispose();
    _passengersController.dispose();
    _routeFocusNode.dispose();
    _passengersFocusNode.dispose();
    super.dispose();
  }

  Future<void> _ensureLocationEnabled() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        // Optionally prompt the user to enable location services
        // We won't block here, just return.
        debugPrint('Location services are disabled.');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
        setState(() => _myLocationEnabled = true);
      } else {
        debugPrint('Location permission not granted: $permission');
      }
    } catch (e) {
      debugPrint('Error checking location permission: $e');
    }
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
  }

  void _onRouteTextChanged() {
    final input = _routeController.text;
    if (input.isEmpty) {
      setState(() => _autocompleteSuggestion = '');
      return;
    }

    final match = _routes.firstWhere(
      (route) => route.startsWith(input.toUpperCase()),
      orElse: () => '',
    );

    setState(() => _autocompleteSuggestion = match);
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    if (details.primaryVelocity != null) {
      setState(() {
        _isExpanded = details.primaryVelocity! < 0;
      });
    }
  }

  void _onCompleteText() {
    if (_autocompleteSuggestion.isNotEmpty) {
      _routeController.text = _autocompleteSuggestion;
      _routeController.selection = TextSelection.fromPosition(
        TextPosition(offset: _routeController.text.length),
      );
      setState(() => _autocompleteSuggestion = '');
      // Load the route immediately when the CHOOSE ROUTE textbox completes
      // (binds to ConductorMapRender.getLayersForRoute via _loadRouteData)
      _loadRouteData(_routeController.text);
    }
  }

  Future<void> _loadRouteData(String routeName) async {
    setState(() => _isLoadingRoute = true);

    try {
      final layers = await ConductorMapRender.getLayersForRoute(routeName);

      setState(() {
        _polylines = layers.polylines.toSet();
        _polygons = layers.polygons.toSet();
        _markers = layers.markers.toSet();
        _isLoadingRoute = false;
      });

      // Fit the map bounds to show the route
      if (layers.polylines.isNotEmpty && _mapController != null) {
        _fitMapToRoute(layers);
      }
    } catch (e) {
      debugPrint('Error loading route: $e');
      setState(() => _isLoadingRoute = false);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load route: $e')),
        );
      }
    }
  }

  void _fitMapToRoute(MapLayers layers) {
    if (layers.polylines.isEmpty) return;

    double? minLat, maxLat, minLng, maxLng;

    for (final polyline in layers.polylines) {
      for (final point in polyline.points) {
        minLat = minLat == null ? point.latitude : (point.latitude < minLat ? point.latitude : minLat);
        maxLat = maxLat == null ? point.latitude : (point.latitude > maxLat ? point.latitude : maxLat);
        minLng = minLng == null ? point.longitude : (point.longitude < minLng ? point.longitude : minLng);
        maxLng = maxLng == null ? point.longitude : (point.longitude > maxLng ? point.longitude : maxLng);
      }
    }

    if (minLat != null && maxLat != null && minLng != null && maxLng != null) {
      final bounds = LatLngBounds(
        southwest: LatLng(minLat, minLng),
        northeast: LatLng(maxLat, maxLng),
      );

      _mapController?.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, 50),
      );
    }
  }

  Future<void> _onSubmit() async {
    final route = _routeController.text.trim();
    final passengers = _passengersController.text.trim();

    if (route.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please choose a route')),
      );
      return;
    }

    if (passengers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter number of passengers')),
      );
      return;
    }

    debugPrint('Route: $route');
    debugPrint('Passengers: $passengers');

    // Load the route on the map
    await _loadRouteData(route);

    // Collapse the modal
    setState(() {
      _isExpanded = false;
      _maxPassengers = int.tryParse(passengers) ?? 0;
      _isPassengerView = true; // show passenger selector
    });
  }

  /// Recenter to user's location.
  ///
  /// NOTE: This implementation uses a simple fallback: if you have a location
  /// provider (e.g. Geolocator or location package) replace the body to fetch
  /// the real user coordinates and animate the camera there. For now it will
  /// animate to the initial position if no location is available.
  Future<void> _recenterToUser() async {
    if (_mapController == null) return;
    try {
      // Check permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permission denied. Enable location permissions to recenter.')),
          );
        }
        return;
      }

      // Try last known position first for speed, fallback to current position
      Position? pos = await Geolocator.getLastKnownPosition();
      pos ??= await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best);

      final latLng = LatLng(pos.latitude, pos.longitude);
      await _mapController!.animateCamera(CameraUpdate.newLatLng(latLng));
    } catch (e) {
      debugPrint('Recenter failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to get location: $e')),
        );
      }
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
            mapType: MapType.normal,
            myLocationEnabled: _myLocationEnabled,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            polylines: _polylines,
            polygons: _polygons,
            markers: _markers,
          ),
          
          if (_isLoadingRoute)
            Container(
              color: Colors.black26,
              child: const Center(
              ),
            ),

          if (!_isPassengerView)
          BottomModal(
            isExpanded: _isExpanded,
            onExpandToggle: () {
              setState(() => _isExpanded = !_isExpanded);
            },
            onVerticalDragEnd: _onVerticalDragEnd,
            routeController: _routeController,
            passengersController: _passengersController,
            routeFocusNode: _routeFocusNode,
            passengersFocusNode: _passengersFocusNode,
            autocompleteSuggestion: _autocompleteSuggestion,
            onCompleteText: _onCompleteText,
            onSubmit: _onSubmit,
          ),
          if (_isPassengerView)
            PassengerWidget(
              maxPassengers: _maxPassengers,
              onClose: () => setState(() => _isPassengerView = false),
            ),
          // Top-left logout button (replace existing maybePop)
          LogoutButton(
            onPressed: () {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginPage()),
                (route) => false,
              );
            },
          ),
          // Recenter button positioned above the modal/passenger area at top-right
          Builder(builder: (ctx) {
            final screenHeight = MediaQuery.of(context).size.height;
            // modal height when not in passenger view
            final modalHeight = _isExpanded ? screenHeight * 0.38 : screenHeight * 0.09;
            // when passenger view is active, approximate the passenger widget height
            // PassengerWidget uses sideSize=70 and midSize=120; choose a conservative value
            final passengerHeight = 120.0;

            final double bottomOffset = !_isPassengerView
                ? modalHeight + 12.0
                : (MediaQuery.of(context).padding.bottom + 16.0) + passengerHeight + 12.0;

            return RecenterButton(
              bottom: bottomOffset,
              right: 20,
              onPressed: _recenterToUser,
            );
          }),
        ],
      ),
    );
  }
}