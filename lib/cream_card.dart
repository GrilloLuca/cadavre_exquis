import 'package:cadavre_exquisite/app_colors.dart';
import 'package:flutter/material.dart';

/// The translucent cream card used across the app to lift content off the
/// background (story lists, empty states, the story reader, the account
/// nickname form).
///
/// When [padding] is non-null the [child] is wrapped in a [Padding] inside
/// the card; leave it null for children that manage their own insets, such
/// as a [ListTile].
class CreamCard extends StatelessWidget {
  const CreamCard({super.key, required this.child, this.padding});

  /// The card's content.
  final Widget child;

  /// Optional inner padding applied around [child].
  final EdgeInsetsGeometry? padding;

  static const double _elevation = 1.0;
  static const double _borderRadius = 14.0;
  static final Color _color = AppColors.cream.withValues(alpha: 0.92);

  @override
  Widget build(BuildContext context) {
    final padding = this.padding;
    return Card(
      color: _color,
      elevation: _elevation,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_borderRadius),
      ),
      child: padding == null ? child : Padding(padding: padding, child: child),
    );
  }
}
