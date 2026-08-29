import 'package:flutter/material.dart';

abstract final class MoveColors {
  static const background = Color(0xFF080B0A);
  static const surface = Color(0xFF101512);
  static const surfaceHigh = Color(0xFF171E1A);
  static const border = Color(0xFF263029);
  static const primary = Color(0xFFC5F65A);
  static const secondary = Color(0xFF4FE1C1);
  static const sleep = Color(0xFF9C9CFF);
  static const textPrimary = Color(0xFFF1F5F0);
  static const textSecondary = Color(0xFF9CA89F);
  static const danger = Color(0xFFFF7272);
}

abstract final class MoveTheme {
  static ThemeData get dark {
    const scheme = ColorScheme.dark(
      primary: MoveColors.primary,
      onPrimary: Color(0xFF142000),
      secondary: MoveColors.secondary,
      onSecondary: Color(0xFF002019),
      surface: MoveColors.surface,
      onSurface: MoveColors.textPrimary,
      error: MoveColors.danger,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: MoveColors.background,
    );

    return base.copyWith(
      splashFactory: InkSparkle.splashFactory,
      textTheme: base.textTheme.copyWith(
        displaySmall: base.textTheme.displaySmall?.copyWith(
          color: MoveColors.textPrimary,
          fontWeight: FontWeight.w700,
          letterSpacing: -1.6,
          height: 1.05,
        ),
        headlineMedium: base.textTheme.headlineMedium?.copyWith(
          color: MoveColors.textPrimary,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.8,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          color: MoveColors.textPrimary,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.35,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          color: MoveColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: base.textTheme.bodyLarge?.copyWith(
          color: MoveColors.textPrimary,
        ),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(
          color: MoveColors.textSecondary,
        ),
        labelLarge: base.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      dividerColor: MoveColors.border,
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 64,
        backgroundColor: MoveColors.surface,
        indicatorColor: MoveColors.primary.withValues(alpha: 0.14),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            color: selected ? MoveColors.primary : MoveColors.textSecondary,
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          return IconThemeData(
            color: states.contains(WidgetState.selected)
                ? MoveColors.primary
                : MoveColors.textSecondary,
          );
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: MoveColors.surfaceHigh,
        hintStyle: const TextStyle(color: MoveColors.textSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: MoveColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: MoveColors.primary, width: 1.4),
        ),
      ),
    );
  }
}
