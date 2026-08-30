// 全局视觉 token（设计变量表）：颜色、圆角的唯一定义处。
//
// ThemeExtension 是 Flutter 的"自定义主题扩展点"——把 Material 主题
// 没有的自定义颜色（surface2/soft 系列等）挂进 ThemeData，页面里通过
// `Theme.of(context).extension<LunioTokens>()!` 取用。
// Java 对照：≈ 一个 @ConfigurationProperties 绑定的全局配置 Bean。
//
// 改视觉优先改这里 + DESIGN.md，不要在页面里散落硬编码颜色。
// 浅色/深色两套常量（light/dark），深色主题的主色换成了青色系。
import 'package:flutter/material.dart';

/// 不可变 token 集。lerp 支持浅深色切换时的颜色渐变动画。
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
    required this.success,
    required this.successSoft,
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

  // ---- 背景与表面（由远及近的层级灰阶）----
  final Color background; // 页面底色
  final Color surface; // 卡片表面
  final Color surface2; // 输入框/次级表面
  final Color surface3; // 更深一档（开关轨道等）

  // ---- 文本三级 ----
  final Color ink; // 主文本
  final Color muted; // 次要文本
  final Color subtle; // 占位/禁用文本

  /// 分割线。
  final Color line;

  // ---- 语义色（正常/到期/超期提醒共用 success/warning/danger 三态）----
  final Color primary; // 主操作色（浅色=蓝，深色=青）
  final Color primaryStrong; // 主色按压/强调态
  final Color primarySoft; // 主色弱底（chip、软背景）
  final Color success; // 正常（绿）
  final Color successSoft;
  final Color secondary; // 次强调色（深色主题下是浅蓝）
  final Color secondarySoft;
  final Color warning; // 到期提醒（黄）
  final Color warningSoft;
  final Color danger; // 超期/删除（红）
  final Color dangerSoft;

  // ---- 圆角（逻辑像素）----
  final double radiusSmall; // 10
  final double radiusMedium; // 14
  final double radiusLarge; // 20
  final double radiusXl; // 28（底部 sheet 顶部圆角）

  /// 浅色主题 token。
  static const light = LunioTokens(
    background: Color(0xfff6f7f9),
    surface: Color(0xffffffff),
    surface2: Color(0xfff1f5f9),
    surface3: Color(0xffe2e8f0),
    ink: Color(0xff111827),
    muted: Color(0xff64748b),
    subtle: Color(0xff94a3b8),
    line: Color(0xffe2e8f0),
    primary: Color(0xff2563eb),
    primaryStrong: Color(0xff1d4ed8),
    primarySoft: Color(0xffdbeafe),
    success: Color(0xff22c55e),
    successSoft: Color(0xffdcfce7),
    secondary: Color(0xff475569),
    secondarySoft: Color(0xffe2e8f0),
    warning: Color(0xfff59e0b),
    warningSoft: Color(0xfffef3c7),
    danger: Color(0xffef4444),
    dangerSoft: Color(0xffffe2e2),
    radiusSmall: 10,
    radiusMedium: 14,
    radiusLarge: 20,
    radiusXl: 28,
  );

  /// 深色主题 token（primary 换青色系，保证深底上的对比度）。
  static const dark = LunioTokens(
    background: Color(0xff111417),
    surface: Color(0xff1a1f25),
    surface2: Color(0xff232a32),
    surface3: Color(0xff2d3540),
    ink: Color(0xfff3f4f6),
    muted: Color(0xffa8b0bb),
    subtle: Color(0xff798391),
    line: Color(0xff303845),
    primary: Color(0xff0e7490),
    primaryStrong: Color(0xff155e75),
    primarySoft: Color(0xff0b2c38),
    success: Color(0xff22c55e),
    successSoft: Color(0xff12331f),
    secondary: Color(0xff38bdf8),
    secondarySoft: Color(0xff102f3b),
    warning: Color(0xfff59e0b),
    warningSoft: Color(0xff3d2b12),
    danger: Color(0xffef4444),
    dangerSoft: Color(0xff3f1d22),
    radiusSmall: 10,
    radiusMedium: 14,
    radiusLarge: 20,
    radiusXl: 28,
  );

  /// 复制并替换部分 token（ThemeExtension 协议要求）。
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
    Color? success,
    Color? successSoft,
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
      success: success ?? this.success,
      successSoft: successSoft ?? this.successSoft,
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

  /// 线性插值：浅深色主题切换动画时 Flutter 逐帧调用。
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
      success: Color.lerp(success, other.success, t)!,
      successSoft: Color.lerp(successSoft, other.successSoft, t)!,
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

/// double 插值（Color.lerp 的数值版）。
double lerpDouble(double a, double b, double t) => a + (b - a) * t;
