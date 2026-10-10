import 'package:cadavre_exquisite/app_colors.dart';
import 'package:flutter/material.dart';

class ChatButton extends StatelessWidget {
  final String? text;
  final Color? color;
  final VoidCallback? onPressed;
  final Widget? icon;

  const ChatButton({
    super.key,
    this.text,
    this.color,
    this.onPressed,
    this.icon,
  });

  /// Cream on the dark (green) buttons, ink on light ones like Google sign-in.
  Color get _textColor {
    final background = color;
    if (background == null) return AppColors.ink;
    return ThemeData.estimateBrightnessForColor(background) == Brightness.dark
        ? AppColors.cream
        : AppColors.ink;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 16.0),
      child: Material(
        elevation: 5.0,
        color: color,
        borderRadius: BorderRadius.circular(30.0),
        child: MaterialButton(
          onPressed: onPressed,
          textColor: _textColor,
          minWidth: 200.0,
          height: 42.0,
          child: icon == null
              ? Text(text!)
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    icon!,
                    SizedBox(width: 12.0),
                    Text(text!),
                  ],
                ),
        ),
      ),
    );
  }
}
