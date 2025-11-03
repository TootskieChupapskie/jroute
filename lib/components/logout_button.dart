import 'package:flutter/material.dart';

class LogoutButton extends StatelessWidget {
	final VoidCallback? onPressed;
	final double top;
	final double left;

	const LogoutButton({
		Key? key,
		this.onPressed,
		this.top = 50,
		this.left = 30,
	}) : super(key: key);

	@override
	Widget build(BuildContext context) {
		return Positioned(
			top: top,
			left: left,
			child: IconButton(
				icon: const Icon(Icons.logout),
				color: Colors.black,
				tooltip: 'Logout',
				onPressed: onPressed ?? () => Navigator.of(context).maybePop(),
				padding: const EdgeInsets.all(8.0),
				constraints: const BoxConstraints(),
			),
		);
	}
}
