import 'dart:math' show min;
import 'package:flutter/material.dart';
import 'dart:ui' show lerpDouble;

class LogoutButton extends StatefulWidget {
  final VoidCallback? onPressed;
  const LogoutButton({Key? key, this.onPressed}) : super(key: key);

  @override
  State<LogoutButton> createState() => _LogoutButtonState();
}

class _LogoutButtonState extends State<LogoutButton> {
  final GlobalKey _btnKey = GlobalKey();

  void _onTap() {
    final ctx = _btnKey.currentContext;
    if (ctx == null) {
      widget.onPressed?.call();
      return;
    }
    final RenderBox box = ctx.findRenderObject() as RenderBox;
    final Rect rect = box.localToGlobal(Offset.zero) & box.size;
    final overlay = Overlay.of(context);
    if (overlay == null) {
      widget.onPressed?.call();
      return;
    }

    // simple grey flash overlay (no animation)
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => Positioned(
        left: rect.left,
        top: rect.top,
        width: rect.width,
        height: rect.height,
        child: IgnorePointer(
          ignoring: true,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.grey.shade700.withOpacity(0.25),
              borderRadius: BorderRadius.circular(min(rect.width, rect.height) / 2),
            ),
          ),
        ),
      ),
    );

    overlay.insert(entry);

    // remove the grey flash shortly after and then call the handler
    Future.delayed(const Duration(milliseconds: 180), () {
      entry.remove();
      widget.onPressed?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 55,
      left: 26,
      child: SizedBox(
        key: _btnKey,
        width: 44,
        height: 44,
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: IconButton(
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.logout, color: Colors.black87),
            onPressed: _onTap,
          ),
        ),
      ),
    );
  }
}

// small helper for interpolation (already imported dart:ui.lerpDouble above)
double? lerpDouble(num a, num b, double t) => a + (b - a) * t;
