import 'package:flutter/material.dart';

/// 阅读排版偏好：正文字号 + 正文字体。
///
/// 为什么单独做成 ThemeExtension，而不是塞进 AppSettings 让编辑器直接读：
/// 编辑器页面拿不到 SettingsController（它是 core 层），而 ThemeData 是
/// 每个 Widget 都能 `Theme.of(context)` 取到的。把「用户偏好」翻译成
/// 「主题里的一种字体样式」，界面层就不需要认识 settings 了。
@immutable
class ReadingPrefs extends ThemeExtension<ReadingPrefs> {
  const ReadingPrefs({
    required this.fontSize,
    required this.fontFamily,
  });

  /// 正文字号（px）。档位 0..4 对应 15/16/17/18/20。
  final double fontSize;

  /// 正文字体族名。空串表示跟随系统默认字体。
  final String fontFamily;

  static const _sizes = <double>[15, 16, 17, 18, 20];

  static double sizeForIndex(int index) =>
      _sizes[index.clamp(0, _sizes.length - 1)];

  /// 当前档位对应的字号，用于设置页显示。
  static String labelForIndex(int index) {
    final i = index.clamp(0, _sizes.length - 1);
    return _sizes[i].toStringAsFixed(0);
  }

  @override
  ReadingPrefs copyWith({double? fontSize, String? fontFamily}) =>
      ReadingPrefs(
        fontSize: fontSize ?? this.fontSize,
        fontFamily: fontFamily ?? this.fontFamily,
      );

  // 必须实现 ==/hashCode：ThemeData 用它判断主题有没有变。若缺省走
  // identity 比较，每次新建实例都不相等，虽然能触发重建，但在 lerp /
  // 主题过渡里会反复判为「变了」造成多余重建；更重要的是部分调用链
  // 会先做 `oldTheme == newTheme` 短路，正确实现后行为可预期。
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReadingPrefs &&
          other.fontSize == fontSize &&
          other.fontFamily == fontFamily;

  @override
  int get hashCode => Object.hash(fontSize, fontFamily);

  @override
  ReadingPrefs lerp(ThemeExtension<ReadingPrefs>? other, double t) {
    if (other is! ReadingPrefs) return this;
    return ReadingPrefs(
      fontSize: fontSize + (other.fontSize - fontSize) * t,
      // 字体族名不能插值，直接取目标值
      fontFamily: t < 0.5 ? fontFamily : other.fontFamily,
    );
  }

  /// 把「字号 + 字体」套到一个基础 TextStyle 上。
  ///
  /// 传空字体族时不要写 fontFamily: null —— 那会让 TextStyle 显式
  /// 继承到 null 从而在部分平台回落异常；直接返回不带该字段的副本。
  TextStyle apply(TextStyle base) {
    final size = fontSize;
    if (fontFamily.isEmpty) {
      return base.copyWith(fontSize: size);
    }
    return base.copyWith(fontSize: size, fontFamily: fontFamily);
  }
}

/// `context.reading` 便捷入口。
extension ReadingContext on BuildContext {
  ReadingPrefs get reading =>
      Theme.of(this).extension<ReadingPrefs>() ??
      const ReadingPrefs(fontSize: 17, fontFamily: '');
}
