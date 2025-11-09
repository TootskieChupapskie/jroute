import 'package:flutter/material.dart';
import 'package:jroute/commuter.dart';
import 'conductor.dart';
import 'services/routing_service.dart';
import 'package:lottie/lottie.dart';
import 'services/button_transition.dart'; // added import

class LoginPage extends StatelessWidget {
  const LoginPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        // use a Stack so we can place a gradient "blob" at the very top behind content
        child: Stack(
          children: [
            // Gradient blob positioned at the very top
            Positioned(
              top: -80,
              left: -60,
              child: Container(
                width: 320,
                height: 320,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF29ABE2),
                      const Color.fromARGB(255, 142, 244, 164),
                      const Color(0xFFFFFFFF),
                    ],
                    stops: const [0.0, 0.6, 1.0],
                    center: const Alignment(-0.2, -0.2),
                    radius: 0.9,
                  ),
                  borderRadius: BorderRadius.circular(200),
                  // slight blur-like effect using boxShadow
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.withOpacity(0.08),
                      blurRadius: 40,
                      spreadRadius: 10,
                    ),
                  ],
                ),
              ),
            ),

            // multiple gradient blobs positioned at the very top
            Positioned(
              top: -140,
              left: -100,
              child: Container(
                width: 380,
                height: 380,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF29ABE2),
                      const Color(0xFF8ED7F4),
                      Colors.white,
                    ],
                    stops: const [0.0, 0.6, 1.0],
                    center: const Alignment(-0.3, -0.3),
                    radius: 0.9,
                  ),
                  borderRadius: BorderRadius.circular(220),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.withOpacity(0.08),
                      blurRadius: 40,
                      spreadRadius: 10,
                    ),
                  ],
                ),
              ),
            ),

            Positioned(
              top: -70,
              right: -120,
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      const Color.fromARGB(255, 141, 60, 211),
                      const Color.fromARGB(255, 86, 32, 193).withOpacity(0.85),
                    ],
                    stops: const [0.0, 1.0],
                    center: const Alignment(-0.2, -0.2),
                    radius: 0.9,
                  ),
                  borderRadius: BorderRadius.circular(200),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.purple.withOpacity(0.06),
                      blurRadius: 30,
                      spreadRadius: 6,
                    ),
                  ],
                ),
              ),
            ),

            Positioned(
              top: -40,
              left: 140,
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      const Color.fromARGB(255, 108, 220, 133),
                      const Color(0xFF29ABE2).withOpacity(0.8),
                    ],
                    stops: const [0.0, 1.0],
                    center: const Alignment(0.0, -0.2),
                    radius: 0.9,
                  ),
                  borderRadius: BorderRadius.circular(200),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.green.withOpacity(0.06),
                      blurRadius: 30,
                      spreadRadius: 6,
                    ),
                  ],
                ),
              ),
            ),

            Column(
              mainAxisSize: MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end, // push buttons + image to bottom
                    children: [
                      // Buttons centered and placed just above the image
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // CONDUCTOR button: capture its position with Builder
                            Builder(builder: (btnContext) {
                              return SizedBox(
                                width: 300,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF29ABE2),
                                    padding: const EdgeInsets.symmetric(vertical: 20),
                                  ),
                                  onPressed: () {
                                    // get the button's global rect
                                    final RenderBox box = btnContext.findRenderObject() as RenderBox;
                                    final Rect rect = box.localToGlobal(Offset.zero) & box.size;

                                    startButtonTransition(
                                      context,
                                      (c) => const ConductorPage(),
                                      color: const Color(0xFF29ABE2),
                                      duration: const Duration(milliseconds: 900),
                                      buttonRect: rect,
                                    );
                                  },
                                  child: const Text(
                                    'CONDUCTOR',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              );
                            }),

                            const SizedBox(height: 16),

                            // COMMUTER button: same pattern
                            Builder(builder: (btnContext) {
                              return SizedBox(
                                width: 300,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFF7B731),
                                    padding: const EdgeInsets.symmetric(vertical: 20),
                                  ),
                                  onPressed: () {
                                    RoutingService.preloadAllRoutes();
                                    final RenderBox box = btnContext.findRenderObject() as RenderBox;
                                    final Rect rect = box.localToGlobal(Offset.zero) & box.size;

                                    startButtonTransition(
                                      context,
                                      (c) => const CommuterPage(),
                                      color: const Color(0xFFF7B731),
                                      duration: const Duration(milliseconds: 900),
                                      buttonRect: rect,
                                    );
                                  },
                                  child: const Text(
                                    'COMMUTER',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),

                      // Image at the very bottom, centered
                      Padding(
                        padding: const EdgeInsets.only(top: 20, bottom: 30),
                        child: Image.asset(
                          'assets/davao.png',
                          height: 70,
                          semanticLabel: 'Davao',
                          fit: BoxFit.contain,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // car_loading.gif centered in the middle and not overlapped by blobs or buttons
            // positioned with top/bottom constraints to avoid the top blobs and bottom buttons
            Positioned(
              top: 120,
              bottom: 180,
              left: 0,
              right: 0,
              child: Center(
                child: Lottie.asset(
                  'assets/Red Car.json',
                  height: 300,
                  fit: BoxFit.contain,
                  repeat: true,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}