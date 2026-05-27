import 'package:flutter/material.dart';

import 'lunio_tokens.dart';

ThemeData buildLunioTheme({Brightness brightness = Brightness.light}) {
  final tokens = brightness == Brightness.dark
      ? LunioTokens.dark
      : LunioTokens.light;
  final colorScheme = brightness == Brightness.dark
      ? ColorScheme.dark(
          primary: tokens.primary,
          onPrimary: Colors.white,
          secondary: tokens.secondary,
          surface: tokens.surface,
          error: tokens.danger,
          onSurface: tokens.ink,
        )
      : ColorScheme.light(
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
    extensions: [tokens],
    textTheme: TextTheme(
      headlineLarge: TextStyle(
        color: tokens.ink,
        fontSize: 27,
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
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.55,
      ),
      bodySmall: TextStyle(
        color: tokens.muted,
        fontSize: 13,
        fontWeight: FontWeight.w400,
        height: 1.4,
      ),
      labelLarge: TextStyle(
        color: tokens.ink,
        fontSize: 13,
        fontWeight: FontWeight.w700,
        height: 1.35,
      ),
      labelSmall: TextStyle(
        color: tokens.muted,
        fontSize: 12,
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
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: tokens.surface2,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(tokens.radiusMedium),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(tokens.radiusMedium),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(tokens.radiusMedium),
        borderSide: BorderSide.none,
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(tokens.radiusMedium),
        borderSide: BorderSide.none,
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(tokens.radiusMedium),
        borderSide: BorderSide(color: tokens.danger, width: 1.2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(tokens.radiusMedium),
        borderSide: BorderSide(color: tokens.danger, width: 1.2),
      ),
      labelStyle: TextStyle(
        color: tokens.muted,
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
      floatingLabelStyle: TextStyle(
        color: tokens.primary,
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
      hintStyle: TextStyle(
        color: tokens.subtle,
        fontSize: 14,
        fontWeight: FontWeight.w400,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      constraints: const BoxConstraints(minHeight: 52),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return tokens.subtle;
        }
        if (states.contains(WidgetState.selected)) {
          return tokens.primary;
        }
        return tokens.surface;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return tokens.surface3.withValues(alpha: 0.5);
        }
        if (states.contains(WidgetState.selected)) {
          return tokens.primarySoft;
        }
        return tokens.surface3;
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return tokens.primary.withValues(alpha: 0.38);
        }
        return tokens.line;
      }),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: tokens.background,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(tokens.radiusXl),
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: tokens.surface,
      surfaceTintColor: Colors.transparent,
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
      backgroundColor: Colors.transparent,
      indicatorColor: tokens.primary,
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radiusLarge),
      ),
      labelTextStyle: WidgetStateProperty.all(
        TextStyle(
          color: tokens.muted,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        return IconThemeData(
          color: states.contains(WidgetState.selected)
              ? Colors.white
              : tokens.muted,
          size: 21,
        );
      }),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: tokens.surface,
      contentTextStyle: TextStyle(
        color: tokens.ink,
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radiusMedium),
        side: BorderSide(color: tokens.line),
      ),
    ),
  );
}
