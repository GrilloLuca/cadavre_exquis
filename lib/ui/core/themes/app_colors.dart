import 'package:flutter/material.dart';

/// Palette sampled from the background illustration
/// (images/background_portrait.jpeg): sage greens, cream and ink.
class AppColors {
  AppColors._();

  /// Main accent: app bars, buttons, own message bubbles.
  static const primary = Color(0xFF5E7F55);

  /// Darker accent: secondary buttons, focused borders.
  static const primaryDark = Color(0xFF3F5A3A);

  /// The sage tone of the illustration's background.
  static const sage = Color(0xFFD5E2C8);

  /// The cream fill used inside the illustration's shapes.
  static const cream = Color(0xFFF4EEDA);

  /// The ink colour of the illustration's outlines.
  static const ink = Color(0xFF2E2E28);
}
