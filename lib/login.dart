import 'package:flutter/material.dart';
import 'package:jroute/commuter.dart';
import 'conductor.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.max,
          children: [
            // Top image with 40px top margin and 20px horizontal margins, size increased by 10%
            Padding(
              padding: const EdgeInsets.only(top: 40, left: 20, right: 20),
              child: Align(
                alignment: Alignment.topCenter,
                child: Image.asset(
                  'assets/davao.png',
                  height: 140, // 120 * 1.1
                  semanticLabel: 'Davao',
                  fit: BoxFit.contain,
                ),
              ),
            ),

            // 50px spacing below the image before the buttons
            const SizedBox(height: 200),

            // Buttons placed below the image (not vertically centered)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Button 1 - CONDUCTOR (blue)
                SizedBox(
                  width: 300,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF29ABE2),
                      padding: const EdgeInsets.symmetric(vertical: 20),
                    ),
                    onPressed: () {
                      // navigate to ConductorPage
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ConductorPage(),
                        ),
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
                ),

                const SizedBox(height: 30),

                // Button 2 - COMMUTER (yellow)
                SizedBox(
                  width: 300,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF7B731),
                      padding: const EdgeInsets.symmetric(vertical: 20),
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const CommuterPage(),
                        ),
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
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}