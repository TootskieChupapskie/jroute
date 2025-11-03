import 'package:flutter/material.dart';

/// Passenger selector shown after BIYAHE is clicked.
/// Shows three boxes at the bottom: decrement, current/max, increment.
class PassengerWidget extends StatefulWidget {
  final int maxPassengers;
  final VoidCallback? onClose;

  const PassengerWidget({Key? key, required this.maxPassengers, this.onClose}) : super(key: key);

  @override
  State<PassengerWidget> createState() => _PassengerWidgetState();
}

class _PassengerWidgetState extends State<PassengerWidget> with SingleTickerProviderStateMixin {
  int _current = 0;

  // quick pop animation state for left and right buttons
  double _leftScale = 1.0;
  double _rightScale = 1.0;

  Future<void> _tapLeft() async {
    setState(() => _leftScale = 0.85);
    await Future.delayed(const Duration(milliseconds: 80));
    setState(() => _leftScale = 1.0);
    setState(() => _current = (_current - 1).clamp(0, widget.maxPassengers));
  }

  Future<void> _tapRight() async {
    setState(() => _rightScale = 0.85);
    await Future.delayed(const Duration(milliseconds: 80));
    setState(() => _rightScale = 1.0);
    setState(() => _current = (_current + 1).clamp(0, widget.maxPassengers));
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom + 35.0;

    Widget _box({required Widget child, required double size, required VoidCallback? onTap, double scale = 1.0, Color? bgColor}) {
      return GestureDetector(
        onTap: onTap,
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
                  color: bgColor ?? Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.black12),
            ),
            child: Center(child: child),
          ),
        ),
      );
    }

    final sideSize = 70.0;
    final midSize = 120.0;

    return Positioned(
      left: 16,
      right: 16,
      bottom: bottomPadding,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // decrement (person with attached operator badge bottom-right)
          _box(
            size: sideSize,
            scale: _leftScale,
            onTap: _tapLeft,
            // main box background is white; operator badge will be red
            bgColor: Colors.white,
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Icon(Icons.person, color: Colors.red, size: 40),
                Positioned(
                  bottom: 6,
                  right: 6,
                  child: Container(
                    width: 7,
                    height: 7,
                    child: const Icon(Icons.remove, color: Colors.red, size: 20),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 20),

          // middle display larger (white box, black icon/text)
          _box(
            size: midSize,
            scale: 1.0,
            onTap: null,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$_current/${widget.maxPassengers}', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                const SizedBox(height: 5),
                const Icon(Icons.person, color: Colors.black, size: 50),
              ],
            ),
          ),

          const SizedBox(width: 20),

          // increment (person with attached operator badge bottom-right)
          _box(
            size: sideSize,
            scale: _rightScale,
            onTap: _tapRight,
            bgColor: Colors.white,
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Icon(Icons.person, color: Colors.green, size: 40),
                Positioned(
                  bottom: 6,
                  right: 6,
                  child: Container(
                    width: 7,
                    height: 7,
                    child: const Icon(Icons.add, color: Colors.green, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
