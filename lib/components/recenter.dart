import 'package:flutter/material.dart';

class RecenterButton extends StatefulWidget {
	final double bottom;
	final double right;
	final VoidCallback onPressed;
	final double size;

	const RecenterButton({
		Key? key,
		required this.bottom,
		required this.right,
		required this.onPressed,
		this.size = 54.0,
	}) : super(key: key);

	@override
	State<RecenterButton> createState() => _RecenterButtonState();
}

class _RecenterButtonState extends State<RecenterButton> with SingleTickerProviderStateMixin {
	late final AnimationController _ctrl;
	late final Animation<double> _scale;

	@override
	void initState() {
		super.initState();
		_ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 160));
		_scale = TweenSequence<double>([
			TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.9).chain(CurveTween(curve: Curves.easeOut)), weight: 50),
			TweenSequenceItem(tween: Tween(begin: 0.9, end: 1.06).chain(CurveTween(curve: Curves.easeOut)), weight: 30),
			TweenSequenceItem(tween: Tween(begin: 1.06, end: 1.0).chain(CurveTween(curve: Curves.easeIn)), weight: 20),
		]).animate(_ctrl);
	}

	@override
	void dispose() {
		_ctrl.dispose();
		super.dispose();
	}

	Future<void> _onTap() async {
		try {
			await _ctrl.forward();
			_ctrl.reset();
		} catch (_) {}
		widget.onPressed();
	}

	@override
	Widget build(BuildContext context) {
		return Positioned(
			bottom: widget.bottom,
			right: widget.right,
			child: ScaleTransition(
				scale: _scale,
				child: Material(
					color: Colors.white,
					shape: const CircleBorder(),
					elevation: 6,
					child: InkWell(
						onTap: _onTap,
						customBorder: const CircleBorder(),
						child: SizedBox(
							width: widget.size,
							height: widget.size,
							child: const Center(
								child: Icon(
									Icons.my_location,
									color: Colors.black,
									size: 22,
								),
							),
						),
					),
				),
			),
		);
	}
}

