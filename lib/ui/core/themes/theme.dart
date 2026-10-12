import 'package:cadavre_exquisite/ui/core/themes/app_colors.dart';
import 'package:flutter/material.dart';

abstract final class AppTheme {
  static final ThemeData light = ThemeData.light().copyWith(
    colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
    scaffoldBackgroundColor: AppColors.sage,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.primary,
      foregroundColor: AppColors.cream,
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.cream,
      selectedItemColor: AppColors.primaryDark,
      unselectedItemColor: AppColors.ink,
    ),
    textTheme: TextTheme(
      bodyLarge: TextStyle(color: Colors.black54),
    ),
    // The textTheme above has no title/body styles, so dialogs would
    // otherwise render light text on their light background.
    dialogTheme: const DialogThemeData(
      backgroundColor: AppColors.cream,
      titleTextStyle: TextStyle(
        color: AppColors.ink,
        fontSize: 22.0,
        fontWeight: FontWeight.w600,
      ),
      contentTextStyle: TextStyle(
        color: AppColors.ink,
        fontSize: 16.0,
        height: 1.4,
      ),
    ),
  );
}
