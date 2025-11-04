import 'package:flutter/material.dart';

class RouteInfo {
  final String name;
  final double kilometers;

  RouteInfo({required this.name, required this.kilometers});
}

class DistanceModal extends StatelessWidget {
  final bool isExpanded;
  final void Function(DragEndDetails) onVerticalDragEnd;
  final List<RouteInfo> routes; // List of routes with their distances

  const DistanceModal({
    Key? key,
    required this.isExpanded,
    required this.onVerticalDragEnd,
    required this.routes,
  }) : super(key: key);

  // Calculate total distance
  double get totalDistance {
    return routes.fold(0.0, (sum, route) => sum + route.kilometers);
  }

  // Calculate standard fare: 13 pesos for first 4km, then 1.80 per km
  double get standardFare {
    if (totalDistance <= 4.0) {
      return 13.0;
    } else {
      final extraKm = totalDistance - 4.0;
      return 13.0 + (extraKm * 1.80);
    }
  }

  // Calculate discounted fare: 20% off standard fare
  double get discountedFare {
    return standardFare * 0.80; // 80% of standard fare (20% discount)
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Align(
      alignment: Alignment.bottomCenter,
      child: GestureDetector(
        onVerticalDragEnd: onVerticalDragEnd,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          height: isExpanded ? screenHeight * 0.38 : screenHeight * 0.09,
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

              // Route title just below grabber
              if (isExpanded)
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: Center(
                    child: Text(
                      'Route 1',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ),

              // Content - Only show when expanded
              if (isExpanded)
                Expanded(
                  child: Padding(
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
                                      'Minimum Fare:',
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
                                      'Total Distance:',
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

                              // Right side - Routes list and total
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(left: 12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      // List of routes with distances (exclude walking, max 2)
                                      routes.isEmpty
                                          ? const Text(
                                              'No routes',
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: Colors.grey,
                                              ),
                                            )
                                          : Column(
                                              children: [
                                                // Filter out walking distances
                                                ...routes
                                                    .where((route) => !route.name.toLowerCase().contains('walk'))
                                                    .take(2)
                                                    .toList()
                                                    .asMap()
                                                    .entries
                                                    .map((entry) {
                                                  final index = entry.key;
                                                  final route = entry.value;
                                                  final nonWalkingCount = routes.where((r) => !r.name.toLowerCase().contains('walk')).length;
                                                  final isLastShown = index == 1;
                                                  final hasMore = nonWalkingCount > 2;
                                                  
                                                  return Padding(
                                                    padding: const EdgeInsets.only(bottom: 6),
                                                    child: Text(
                                                      '${route.name}: ${route.kilometers.toStringAsFixed(2)} km${(isLastShown && hasMore) ? ' ...' : ''}',
                                                      style: const TextStyle(
                                                        fontSize: 15,
                                                        color: Colors.black87,
                                                      ),
                                                      textAlign: TextAlign.center,
                                                    ),
                                                  );
                                                }).toList(),
                                              ],
                                            ),
                                      const SizedBox(height: 8),
                                      // Total distance summary
                                      Container(
                                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.shade50,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          'Total: ${totalDistance.toStringAsFixed(2)} km',
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
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
                              // TODO: Implement button action
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
                  ),
                ),

              if (isExpanded) const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}
