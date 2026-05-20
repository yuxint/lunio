import 'package:flutter/material.dart';

import 'lunio_tokens.dart';

ThemeData buildLunioTheme() {
  const tokens = LunioTokens.light;
  final colorScheme = ColorScheme.light(
    primary: tokens.primary,
    onPrimary: Colors.white,
    secondary: tokens.secondary,
    surface: tokens.surface,
    error: tokens.danger,
    onSurface: tokens.ink,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: tokens.background,
    fontFamilyFallback: const [
      'Inter',
      'SF Pro Text',
      'PingFang SC',
      'Microsoft YaHei',
      'sans-serif',
    ],
    extensions: const [tokens],
    textTheme: TextTheme(
      headlineLarge: TextStyle(
        color: tokens.ink,
        fontSize: 28,
        fontWeight: FontWeight.w800,
        height: 1.12,
      ),
      titleLarge: TextStyle(
        color: tokens.ink,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        height: 1.25,
      ),
      titleMedium: TextStyle(
        color: tokens.ink,
        fontSize: 17,
        fontWeight: FontWeight.w700,
        height: 1.2,
      ),
      bodyMedium: TextStyle(
        color: tokens.muted,
        fontSize: 15,
        fontWeight: FontWeight.w400,
        height: 1.7,
      ),
      labelLarge: TextStyle(
        color: tokens.ink,
        fontSize: 13,
        fontWeight: FontWeight.w700,
        height: 1.35,
      ),
    ),
    cardTheme: CardThemeData(
      color: tokens.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radiusLarge),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(50),
        backgroundColor: tokens.primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radiusMedium),
        ),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: tokens.surface,
      indicatorColor: tokens.primary,
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
      ),
    ),
  );
}
