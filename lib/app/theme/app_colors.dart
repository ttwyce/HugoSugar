import 'package:flutter/material.dart';

/// 全局设计 token。
///
/// 用法：`context.appColors.accent`
///
/// 纪律：Widget 里禁止写 `Color(0xFF...)`，一律从这里取。
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.background,
    required this.surface,
    required this.surfaceHigh,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.divider,
    required this.accent,
    required this.accentSoft,
    required this.danger,
    required this.warning,
  });

  final Color background;
  final Color surface;
  final Color surfaceHigh;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color divider;
  final Color accent;
  final Color accentSoft;
  final Color danger;
  final Color warning;

  // ── 亮色 ──────────────────────────────────────────────
  static const light = AppColors(
    background: Color(0xFFFFFFFF),
    surface: Color(0xFFF7F7F8),
    surfaceHigh: Color(0xFFEFEFF2),
    textPrimary: Color(0xFF1A1A1A),
    textSecondary: Color(0xFF6B6B70),
    textTertiary: Color(0xFFA0A0A6),
    divider: Color(0xFFEAEAEC),
    accent: Color(0xFF3A6B5C),
    accentSoft: Color(0xFFEAF2EF),
    danger: Color(0xFFC4443C),
    warning: Color(0xFFB07C21),
  );

  // ── 暗色（独立设计，不是反色）────────────────────────
  static const dark = AppColors(
    background: Color(0xFF121212),
    surface: Color(0xFF1A1A1C),
    surfaceHigh: Color(0xFF242427),
    textPrimary: Color(0xFFE8E8EA),
    textSecondary: Color(0xFF9A9AA0),
    textTertiary: Color(0xFF6B6B72),
    divider: Color(0xFF2A2A2E),
    accent: Color(0xFF7FBFA8),
    accentSoft: Color(0xFF1E2A26),
    danger: Color(0xFFE5736B),
    warning: Color(0xFFD9A84E),
  );

  @override
  AppColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceHigh,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? divider,
    Color? accent,
    Color? accentSoft,
    Color? danger,
    Color? warning,
  }) {
    return AppColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceHigh: surfaceHigh ?? this.surfaceHigh,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      divider: divider ?? this.divider,
      accent: accent ?? this.accent,
      accentSoft: accentSoft ?? this.accentSoft,
      danger: danger ?? this.danger,
      warning: warning ?? this.warning,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceHigh: Color.lerp(surfaceHigh, other.surfaceHigh, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
    );
  }
}

/// 语义化取色：`context.appColors.accent`
extension AppColorsX on BuildContext {
  AppColors get appColors => Theme.of(this).extension<AppColors>()!;
}

/// 间距与圆角常量（避免各处魔法数字）
abstract final class AppSpace {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 20.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

abstract final class AppRadius {
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const pill = 999.0;
}
