import 'package:flutter/material.dart';

@immutable
class LunioTokens extends ThemeExtension<LunioTokens> {
  const LunioTokens({
    required this.background,
    required this.surface,
    required this.surface2,
    required this.surface3,
    required this.ink,
    required this.muted,
    required this.subtle,
    required this.line,
    required this.primary,
    required this.primaryStrong,
    required this.primarySoft,
    required this.secondary,
    required this.secondarySoft,
    required this.warning,
    required this.warningSoft,
    required this.danger,
    required this.dangerSoft,
    required this.radiusSmall,
    required this.radiusMedium,
    required this.radiusLarge,
    required this.radiusXl,
  });

  final Color background;
  final Color surface;
  final Color surface2;
  final Color surface3;
  final Color ink;
  final Color muted;
  final Color subtle;
  final Color line;
  final Color primary;
  final Color primaryStrong;
  final Color primarySoft;
  final Color secondary;
  final Color secondarySoft;
  final Color warning;
  final Color warningSoft;
  final Color danger;
  final Color dangerSoft;
  final double radiusSmall;
  final double radiusMedium;
  final double radiusLarge;
  final double radiusXl;

  static const light = LunioTokens(
    background: Color(0xfff6f7f4),
    surface: Color(0xffffffff),
    surface2: Color(0xfff0f4ef),
    surface3: Color(0xffe8eee8),
    ink: Color(0xff18201b),
    muted: Color(0xff667165),
    subtle: Color(0xff8c9689),
    line: Color(0xffdce3dc),
    primary: Color(0xff166c4c),
    primaryStrong: Color(0xff0f563b),
    primarySoft: Color(0xffddefd9),
    secondary: Color(0xff2459a6),
    secondarySoft: Color(0xffe0eaf8),
    warning: Color(0xffc6821b),
    warningSoft: Color(0xfffff1d8),
    danger: Color(0xffb73b35),
    dangerSoft: Color(0xffffe4df),
    radiusSmall: 10,
    radiusMedium: 14,
    radiusLarge: 20,
    radiusXl: 28,
  );

  @override
  LunioTokens copyWith({
    Color? background,
    Color? surface,
    Color? surface2,
    Color? surface3,
    Color? ink,
    Color? muted,
    Color? subtle,
    Color? line,
    Color? primary,
    Color? primaryStrong,
    Color? primarySoft,
    Color? secondary,
    Color? secondarySoft,
    Color? warning,
    Color? warningSoft,
    Color? danger,
    Color? dangerSoft,
    double? radiusSmall,
    double? radiusMedium,
    double? radiusLarge,
    double? radiusXl,
  }) {
    return LunioTokens(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surface2: surface2 ?? this.surface2,
      surface3: surface3 ?? this.surface3,
      ink: ink ?? this.ink,
      muted: muted ?? this.muted,
      subtle: subtle ?? this.subtle,
      line: line ?? this.line,
      primary: primary ?? this.primary,
      primaryStrong: primaryStrong ?? this.primaryStrong,
      primarySoft: primarySoft ?? this.primarySoft,
      secondary: secondary ?? this.secondary,
      secondarySoft: secondarySoft ?? this.secondarySoft,
      warning: warning ?? this.warning,
      warningSoft: warningSoft ?? this.warningSoft,
      danger: danger ?? this.danger,
      dangerSoft: dangerSoft ?? this.dangerSoft,
      radiusSmall: radiusSmall ?? this.radiusSmall,
      radiusMedium: radiusMedium ?? this.radiusMedium,
      radiusLarge: radiusLarge ?? this.radiusLarge,
      radiusXl: radiusXl ?? this.radiusXl,
    );
  }

  @override
  LunioTokens lerp(ThemeExtension<LunioTokens>? other, double t) {
    if (other is! LunioTokens) {
      return this;
    }
    return LunioTokens(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surface2: Color.lerp(surface2, other.surface2, t)!,
      surface3: Color.lerp(surface3, other.surface3, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      subtle: Color.lerp(subtle, other.subtle, t)!,
      line: Color.lerp(line, other.line, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      primaryStrong: Color.lerp(primaryStrong, other.primaryStrong, t)!,
      primarySoft: Color.lerp(primarySoft, other.primarySoft, t)!,
      secondary: Color.lerp(secondary, other.secondary, t)!,
      secondarySoft: Color.lerp(secondarySoft, other.secondarySoft, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningSoft: Color.lerp(warningSoft, other.warningSoft, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerSoft: Color.lerp(dangerSoft, other.dangerSoft, t)!,
      radiusSmall: lerpDouble(radiusSmall, other.radiusSmall, t),
      radiusMedium: lerpDouble(radiusMedium, other.radiusMedium, t),
      radiusLarge: lerpDouble(radiusLarge, other.radiusLarge, t),
      radiusXl: lerpDouble(radiusXl, other.radiusXl, t),
    );
  }
}

double lerpDouble(double a, double b, double t) => a + (b - a) * t;
