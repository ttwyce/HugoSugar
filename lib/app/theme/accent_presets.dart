import 'package:flutter/material.dart';

/// 可选的强调色预设。
///
/// 每个预设给亮/暗两套值。为什么不是「一个颜色同时用于亮暗」：
/// 同一个色号在白底和黑底上的对比度天差地别——深墨绿在暗色主题里
/// 几乎看不见，浅薄荷绿在白底上又发飘。所以暗色版一律提亮。
class AccentPreset {
  const AccentPreset({
    required this.name,
    required this.light,
    required this.lightSoft,
    required this.dark,
    required this.darkSoft,
  });

  final String name;
  final Color light;

  /// 亮色主题下 accent 的浅色底（用于选中态背景）
  final Color lightSoft;

  final Color dark;
  final Color darkSoft;

  Color accent(bool isDark) => isDark ? dark : light;
  Color soft(bool isDark) => isDark ? darkSoft : lightSoft;
}

/// 第一个是当前默认的墨绿，保持老用户视觉不变。
const List<AccentPreset> kAccentPresets = [
  AccentPreset(
    name: '墨绿',
    light: Color(0xFF3A6B5C),
    lightSoft: Color(0xFFEAF2EF),
    dark: Color(0xFF7FBFA8),
    darkSoft: Color(0xFF1E2E29),
  ),
  AccentPreset(
    name: '靛蓝',
    light: Color(0xFF33538A),
    lightSoft: Color(0xFFE8EDF7),
    dark: Color(0xFF8FAEE0),
    darkSoft: Color(0xFF1C2434),
  ),
  AccentPreset(
    name: '赭石',
    light: Color(0xFF8A4B2A),
    lightSoft: Color(0xFFF6EBE3),
    dark: Color(0xFFD89A72),
    darkSoft: Color(0xFF33231A),
  ),
  AccentPreset(
    name: '紫岩',
    light: Color(0xFF5B3F7A),
    lightSoft: Color(0xFFF0EAF6),
    dark: Color(0xFFB49BD4),
    darkSoft: Color(0xFF271F31),
  ),
  AccentPreset(
    name: '青灰',
    light: Color(0xFF3C5A5E),
    lightSoft: Color(0xFFE9F0F1),
    dark: Color(0xFF8FB6BA),
    darkSoft: Color(0xFF1E2829),
  ),
  AccentPreset(
    name: '纯墨',
    light: Color(0xFF2B2B2E),
    lightSoft: Color(0xFFEFEFF1),
    dark: Color(0xFFB8B8BE),
    darkSoft: Color(0xFF26262A),
  ),
];

/// 索引越界时的兜底。
AccentPreset accentPresetAt(int index) {
  if (index < 0 || index >= kAccentPresets.length) return kAccentPresets.first;
  return kAccentPresets[index];
}