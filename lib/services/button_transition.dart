import 'dart:math';
import 'package:flutter/material.dart';

Future<void> startButtonTransition(
  BuildContext context,
  WidgetBuilder destinationBuilder, {
  Color color = Colors.blue,
  Duration duration = const Duration(milliseconds: 900),
  Rect? buttonRect, // optional: rect of the button in global coordinates
}) async {
  final overlay = Overlay.of(context);
  if (overlay == null) return;

  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) => _ButtonExpandOverlay(
      parentContext: context,
      destinationBuilder: destinationBuilder,
      color: color,
      duration: duration,
      entry: entry,
      buttonRect: buttonRect,
    ),
  );

  overlay.insert(entry);
}

class _ButtonExpandOverlay extends StatefulWidget {
  final BuildContext parentContext;
  final WidgetBuilder destinationBuilder;
  final Color color;
  final Duration duration;
  final OverlayEntry entry;
  final Rect? buttonRect;

  const _ButtonExpandOverlay({
    Key? key,
    required this.parentContext,
    required this.destinationBuilder,
    required this.color,
    required this.duration,
    required this.entry,
    this.buttonRect,
  }) : super(key: key);

  @override
  State<_ButtonExpandOverlay> createState() => _ButtonExpandOverlayState();
}

class _ButtonExpandOverlayState extends State<_ButtonExpandOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl;
  late final Animation<double> _expand;
  late final Animation<Color?> _colorAnim;
  late final Animation<double> _opacityAnim;

  @override
  void initState() {
    super.initState();
    _ctl = AnimationController(vsync: this, duration: widget.duration);

    _expand = CurvedAnimation(parent: _ctl, curve: Curves.easeInOut);
    _colorAnim = ColorTween(begin: widget.color, end: Colors.white).animate(
      CurvedAnimation(parent: _ctl, curve: const Interval(0.0, 0.8, curve: Curves.easeIn)),
    );
    _opacityAnim = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _ctl, curve: const Interval(0.4, 1.0, curve: Curves.easeOut)),
    );

    _ctl.forward();
    _ctl.addStatusListener((s) async {
      if (s == AnimationStatus.completed) {
        // Replace route immediately so LoginPage cannot reappear
        Navigator.of(widget.parentContext).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => widget.destinationBuilder(widget.parentContext),
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
            transitionsBuilder: (_, __, ___, child) => child,
          ),
        );

        await Future.delayed(const Duration(milliseconds: 300));
        widget.entry.remove();
      }
    });
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    // If a buttonRect is provided, expand from that button; otherwise fallback to bottom-center.
    final Rect btnRect = widget.buttonRect ??
        Rect.fromCenter(
          center: Offset(size.width / 2, size.height - 140),
          width: 300,
          height: 56,
        );

    final Offset startCenter = btnRect.center;
    final double initialW = btnRect.width;
    final double initialH = btnRect.height;
    final double initialRadius = min(16.0, min(initialW, initialH) / 2);

    // final size large enough to cover the screen
    final double maxDim = (size.longestSide) * 2.2;
    final double finalW = maxDim;
    final double finalH = maxDim;

    return Positioned.fill(
      child: IgnorePointer(
        ignoring: true,
        child: AnimatedBuilder(
          animation: _ctl,
          builder: (context, _) {
            final double t = _expand.value;

            // interpolate width/height from button size to final cover size
            final double curW = lerpDouble(initialW, finalW, t)!;
            final double curH = lerpDouble(initialH, finalH, t)!;

            // keep expansion centered on the button center while growing
            final double left = startCenter.dx - curW / 2;
            final double top = startCenter.dy - curH / 2;

            // border radius interpolates from the button's radius to 0 (full rect)
            final double curRadius = lerpDouble(initialRadius, 0, t)!;

            // keep the full-screen white cover fully opaque for entire animation
            const double coverOpacity = 1.0;

            return Stack(
              children: [
                // full-screen white cover that always hides the login contents
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: true,
                    child: Opacity(
                      opacity: coverOpacity,
                      child: const DecoratedBox(
                        decoration: BoxDecoration(color: Colors.white),
                      ),
                    ),
                  ),
                ),

                // expanding rect that keeps the button shape (rounded rect) and grows to fill
                Positioned(
                  left: left,
                  top: top,
                  width: curW,
                  height: curH,
                  child: Opacity(
                    opacity: _opacityAnim.value,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: _colorAnim.value,
                        borderRadius: BorderRadius.circular(curRadius),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// small helper since dart:ui.lerpDouble is not imported here
double? lerpDouble(num a, num b, double t) => a + (b - a) * t;