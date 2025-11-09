import 'package:flutter/material.dart';

class RouteInfo {
  final String name;
  final double kilometers;
  final Color? color; // Color assigned to this route

  RouteInfo({required this.name, required this.kilometers, this.color});
}

class DistanceModal extends StatefulWidget {
  final bool isExpanded;
  final void Function(DragEndDetails) onVerticalDragEnd;
  final List<RouteInfo> routes; // List of routes with their distances (current route)
  final List<List<RouteInfo>> allRouteOptions; // All available route options
  final Function(int)? onRouteChanged; // Callback when user swipes to different route
  final Function(int)? onSakayPressed; // Callback when Sakay button is pressed
  final Function(int)? onSubrouteChanged; // Callback when user swipes to different subroute after Sakay

  const DistanceModal({
    Key? key,
    required this.isExpanded,
    required this.onVerticalDragEnd,
    required this.routes,
    this.allRouteOptions = const [],
    this.onRouteChanged,
    this.onSakayPressed,
    this.onSubrouteChanged,
  }) : super(key: key);

  @override
  State<DistanceModal> createState() => _DistanceModalState();
}

class _DistanceModalState extends State<DistanceModal> {
  late PageController _pageController;
  int _currentRouteIndex = 0;
  bool _sakayPressed = false; // Track if Sakay button has been pressed
  int _currentOtherRouteIndex = 0; // Track current page in "Other Routes" section
  
  // Group routes into unique route options
  List<List<RouteInfo>> get routeOptions {
    // If we have multiple route options passed from parent, use those
    if (widget.allRouteOptions.isNotEmpty) {
      // Filter out duplicate route options based on route names
      List<List<RouteInfo>> uniqueOptions = [];
      Set<String> seenRouteKeys = {};
      
      for (final routeOption in widget.allRouteOptions) {
        String routeKey = routeOption.map((r) => r.name).join('|');
        if (!seenRouteKeys.contains(routeKey)) {
          uniqueOptions.add(routeOption);
          seenRouteKeys.add(routeKey);
        }
      }
      
      return uniqueOptions;
    }
    
    // Fallback to single route if no options provided
    if (widget.routes.isEmpty) return [];
    return [widget.routes];
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // Calculate total distance for a specific route option
  double getTotalDistance(List<RouteInfo> routes) {
    return routes.fold(0.0, (sum, route) => sum + route.kilometers);
  }

  // Calculate standard fare: 13 pesos for first 4km, then 1.80 per km
  double getStandardFare(double totalDistance) {
    if (totalDistance <= 4.0) {
      return 13.0;
    } else {
      final extraKm = totalDistance - 4.0;
      return 13.0 + (extraKm * 1.80);
    }
  }

  // Calculate discounted fare: 20% off standard fare
  double getDiscountedFare(double standardFare) {
    return standardFare * 0.80; // 80% of standard fare (20% discount)
  }

  // Debug function for route names
  void _debugRouteName(RouteInfo route) {
    print('=== ROUTE DEBUG START ===');
    print('Raw route name: "${route.name}"');
    print('Route name length: ${route.name.length}');
    print('Route name isEmpty: ${route.name.isEmpty}');
    print('Route name characters: ${route.name.split('').join(', ')}');
    print('Route kilometers: ${route.kilometers}');
    print('Route color: ${route.color}');
    
    // Check for hidden characters
    if (route.name.contains('\n')) print('⚠️ Contains newline');
    if (route.name.contains('\t')) print('⚠️ Contains tab');
    if (route.name.contains('\r')) print('⚠️ Contains carriage return');
    
    // Show formatted version
    final formatted = _formatRouteName(route.name);
    print('Formatted route name: "$formatted"');
    print('Formatted length: ${formatted.length}');
    print('=== ROUTE DEBUG END ===\n');
  }

  // Format route name: keep full route names intact, just fix capitalization
  String _formatRouteName(String routeName) {
    if (routeName.trim().isEmpty) return routeName;
    
    // Convert to lowercase first
    String cleaned = routeName.toLowerCase().trim();
    
    // Title-case each word
    final words = cleaned.split(' ');
    return words
        .map((w) => w.isEmpty ? w : (w.length == 1 ? w.toUpperCase() : (w[0].toUpperCase() + w.substring(1))))
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final options = routeOptions;
    
    // Adjust height based on whether Sakay was pressed
    final double expandedHeight = _sakayPressed 
        ? screenHeight * 0.30  // Collapsed height after Sakay (30% instead of 38%)
        : screenHeight * 0.38; // Normal expanded height

    return Align(
      alignment: Alignment.bottomCenter,
      child: GestureDetector(
        onVerticalDragEnd: widget.onVerticalDragEnd,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          height: widget.isExpanded ? expandedHeight : screenHeight * 0.09,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(40),
              topRight: Radius.circular(40),
            ),
          ),
          child: Column(
            children: [
              // Dragger Handle
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 20),
                color: Colors.transparent,
                child: Center(
                  child: Container(
                    width: 80,
                    height: 10,
                    decoration: BoxDecoration(
                      color: Colors.grey[400],
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),

              // Route title and navigation indicators
              if (widget.isExpanded && !_sakayPressed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Center(
                    child: Text(
                      'Route ${_currentRouteIndex + 1}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ),

              // Page indicator dots (only show if there are multiple routes and not after Sakay)
              if (widget.isExpanded && options.length > 1 && !_sakayPressed)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    options.length,
                    (index) => Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _currentRouteIndex == index
                            ? const Color(0xFFF7B731)
                            : Colors.grey[300],
                      ),
                    ),
                  ),
                ),

              // Add spacing between dots and content (only if dots are shown)
              if (widget.isExpanded && options.length > 1 && !_sakayPressed)
                const SizedBox(height: 20),

              // Content - Only show when expanded
              if (widget.isExpanded && options.isNotEmpty)
                Expanded(
                  child: _sakayPressed
                      ? _buildAfterSakayView(options)
                      : PageView.builder(
                          controller: _pageController,
                          onPageChanged: (index) {
                            setState(() {
                              _currentRouteIndex = index;
                            });
                            // Notify parent about route change
                            if (widget.onRouteChanged != null) {
                              widget.onRouteChanged!(index);
                            }
                          },
                          itemCount: options.length,
                          itemBuilder: (context, index) {
                      final currentRoutes = options[index];
                      final totalDistance = getTotalDistance(currentRoutes);
                      final standardFare = getStandardFare(totalDistance);
                      final discountedFare = getDiscountedFare(standardFare);
                      
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Headers row
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Left header - Minimum Fare
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.only(right: 12),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: const [
                                        Text(
                                          'Total Fare',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.black87,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                                const SizedBox(width: 16),

                                // Right header - Total Distance
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.only(left: 12),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: const [
                                        Text(
                                          'Total Distance',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.black87,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 12),

                            // Content row
                            Expanded(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Left side - Fare values
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.only(right: 12),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.center,
                                        children: [
                                          Text(
                                            'Standard: ₱${standardFare.toStringAsFixed(2)}',
                                            style: const TextStyle(
                                              fontSize: 15,
                                              color: Colors.black87,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            'Discount: ₱${discountedFare.toStringAsFixed(2)}',
                                            style: const TextStyle(
                                              fontSize: 15,
                                              color: Colors.black87,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),

                                  const SizedBox(width: 16),

                                  // Right side - Total distance only
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.only(left: 12),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.center,
                                        mainAxisAlignment: MainAxisAlignment.start,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 8,
                                              horizontal: 16,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.blue[50],
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              '${totalDistance.toStringAsFixed(2)} km',
                                              style: const TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.black87,
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
                            
                            const SizedBox(height: 20),
                            
                            // Sakay button
                            SizedBox(
                              width: 150,
                              height: 50,
                              child: ElevatedButton(
                                onPressed: () {
                                  setState(() {
                                    _sakayPressed = true;
                                  });
                                  if (widget.onSakayPressed != null) {
                                    widget.onSakayPressed!(index);
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFF7B731),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(30),
                                  ),
                                ),
                                child: const Text(
                                  'SAKAY',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),

              if (widget.isExpanded) const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  // Build view shown after Sakay button is pressed
  Widget _buildAfterSakayView(List<List<RouteInfo>> options) {
    // After Sakay, options should only contain one route (the selected one)
    if (options.isEmpty) return const SizedBox.shrink();
    
    final selectedRoutes = options.first; // Use first since we only have one option now
    
    // Filter out walking routes - get only jeepney routes from selected option
    final jeepneyRoutes = selectedRoutes
        .where((route) => !route.name.toLowerCase().contains('walk'))
        .toList();
    
    if (jeepneyRoutes.isEmpty) return const SizedBox.shrink();
    
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Swipeable individual routes with their full details
        Expanded(
          child: PageView.builder(
            itemCount: jeepneyRoutes.length,
            onPageChanged: (index) {
              setState(() {
                _currentOtherRouteIndex = index;
              });
              // Notify parent about subroute change
              if (widget.onSubrouteChanged != null) {
                widget.onSubrouteChanged!(index);
              }
            },
            itemBuilder: (context, index) {
              final route = jeepneyRoutes[index];
              
              // Debug the route
              _debugRouteName(route);
              
              final routeName = _formatRouteName(route.name);
              final routeColor = route.color ?? const Color(0xFFF7B731); // Use route color or default yellow
              final distance = route.kilometers;
              final standardFare = getStandardFare(distance);
              final discountedFare = getDiscountedFare(standardFare);
              
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Route name
                    Text(
                      routeName,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: routeColor,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2, // allow up to two lines for multi-word names
                      overflow: TextOverflow.ellipsis,
                      softWrap: true,
                    ),
                    const SizedBox(height: 12),
                    
                    // Page indicator dots (show below route name if more than 1)
                    if (jeepneyRoutes.length > 1)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          jeepneyRoutes.length,
                          (dotIndex) => Container(
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _currentOtherRouteIndex == dotIndex
                                  ? routeColor
                                  : Colors.grey[300],
                            ),
                          ),
                        ),
                      ),
                    
                    SizedBox(height: jeepneyRoutes.length > 1 ? 20 : 8),
                    
                    // Headers row
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Left header - Total Fare
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: const [
                                Text(
                                  'Total Fare',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        // Right header - Total Distance
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(left: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: const [
                                Text(
                                  'Total Distance',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    
                    // Content row
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Left side - Fare values
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text(
                                  'Standard: ₱${standardFare.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    color: Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Discount: ₱${discountedFare.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    color: Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        // Right side - Distance
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(left: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              mainAxisAlignment: MainAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                    horizontal: 16,
                                  ),
                                  decoration: BoxDecoration(
                                    color: routeColor.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '${distance.toStringAsFixed(2)} km',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: routeColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}