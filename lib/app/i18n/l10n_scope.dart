import 'package:flutter/material.dart';

import 'strings.dart';

/// 把当前语言放进 widget 树。
///
/// 为什么不用 flutter_localizations + .arb：
/// 那套要求把每条文案改成符号 key 并跑代码生成，
/// 本项目 1100 多处中文文案改造成本极高，而且它主要解决
/// 复数、性别、日期格式等我们暂时用不到的复杂度。
/// 这里用更直接的方式：语言存 AppSettings，通过 InheritedWidget 下发。
class L10nScope extends InheritedWidget {
  const L10nScope({
    super.key,
    required this.locale,
    required super.child,
  });

  final AppLocale locale;

  static AppLocale of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<L10nScope>();
    // 没有 scope 时回落中文：测试里直接 pump 单个 widget 也能跑
    return scope?.locale ?? AppLocale.zh;
  }

  @override
  bool updateShouldNotify(L10nScope oldWidget) => locale != oldWidget.locale;
}

/// 取文案的便捷入口：`context.tr('取消')`
extension L10nContext on BuildContext {
  String tr(String key) => stringsTr(key, L10nScope.of(this));

  AppLocale get appLocale => L10nScope.of(this);
}

/// 顶层函数，避免和 strings.dart 里的 tr 重名造成歧义。
String stringsTr(String key, AppLocale locale) => tr(key, locale);