import 'package:cadavre_exquisite/app_colors.dart';
import 'package:flutter/material.dart';

/// Full-screen background image that switches between the portrait and
/// landscape variants based on the current device orientation.
///
/// Lower [opacity] fades the illustration into the sage background colour,
/// which keeps text drawn on top of it readable.
class Background extends StatelessWidget {
  const Background({super.key, required this.child, this.opacity = 1.0});

  final Widget child;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final isPortrait =
        MediaQuery.of(context).orientation == Orientation.portrait;
    return Container(
      // Always fill the available space, even when the child is smaller.
      constraints: const BoxConstraints.expand(),
      decoration: BoxDecoration(
        color: AppColors.sage,
        image: DecorationImage(
          image: AssetImage(isPortrait
              ? 'images/background_portrait.jpeg'
              : 'images/background_landscape.jpeg'),
          fit: BoxFit.cover,
          opacity: opacity,
        ),
      ),
      child: child,
    );
  }
}
