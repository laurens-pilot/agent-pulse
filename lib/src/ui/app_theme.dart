import 'package:flutter/material.dart';

abstract final class AppColors {
  static const canvas = Color(0xFFF4F5F8);
  static const surface = Color(0xFFFFFFFF);
  static const ink = Color(0xFF1D2433);
  static const muted = Color(0xFF747D8E);
  static const subtle = Color(0xFFA3AABA);
  static const border = Color(0xFFE4E7ED);
  static const sidebar = Color(0xFF171C27);
  static const primary = Color(0xFF5469E8);
  static const primarySoft = Color(0xFFE9ECFF);
  static const orange = Color(0xFFF0A05A);
  static const orangeSoft = Color(0xFFFFF0E2);
  static const pink = Color(0xFFD879A6);
  static const olive = Color(0xFF8C9B5A);
}

ThemeData buildAppTheme() {
  const colorScheme = ColorScheme.light(
    primary: AppColors.primary,
    onPrimary: Colors.white,
    surface: AppColors.surface,
    onSurface: AppColors.ink,
    outline: AppColors.border,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: AppColors.canvas,
    splashFactory: InkSparkle.splashFactory,
  );
  return base.copyWith(
    textTheme: base.textTheme.copyWith(
      displaySmall: const TextStyle(
        color: AppColors.ink,
        fontSize: 34,
        height: 1.12,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.2,
      ),
      headlineSmall: const TextStyle(
        color: AppColors.ink,
        fontSize: 22,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
      ),
      titleLarge: const TextStyle(
        color: AppColors.ink,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.25,
      ),
      titleMedium: const TextStyle(
        color: AppColors.ink,
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: const TextStyle(
        color: AppColors.ink,
        fontSize: 15,
        height: 1.45,
      ),
      bodyMedium: const TextStyle(
        color: AppColors.muted,
        fontSize: 13,
        height: 1.45,
      ),
      labelLarge: const TextStyle(
        color: AppColors.ink,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      labelMedium: const TextStyle(
        color: AppColors.muted,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      ),
    ),
    cardTheme: const CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(18)),
        side: BorderSide(color: AppColors.border),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: AppColors.sidebar,
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: const TextStyle(color: Colors.white, fontSize: 12),
      waitDuration: const Duration(milliseconds: 300),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.border,
      thickness: 1,
      space: 1,
    ),
  );
}
