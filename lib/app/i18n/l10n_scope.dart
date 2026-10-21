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
  const L10nScope({super.key, required this.locale, required super.child});

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

/// 当前界面语言的全局镜像。
///
/// ## 为什么需要它
///
/// `context.tr()` 依赖 BuildContext 能找到 [L10nScope]。但项目里大量
/// 文案出现在**拿不到 context 的位置**：State 的辅助方法、纯函数、
/// 模型 getter（如 [Note.updatedLabel] 返回「刚刚」）。这些地方若强行
/// 走 context，会编译不过或要一路透传 BuildContext，污染签名。
///
/// 于是提供一个**无 context 的取词入口** [T]：它读这个全局值。
/// 全局值由 [setCurrentAppLocale] 在顶层 build 时写入 —— 而顶层已经
/// 订阅了 SettingsController，切语言会重建并刷新它，所以不会过期。
///
/// 纪律：**只在拿不到 context 的地方用 [T]**；能拿到 context 时优先用
/// `context.tr()`，因为那是响应式的、可测试的。
AppLocale _currentAppLocale = AppLocale.zh;

AppLocale get currentAppLocale => _currentAppLocale;

void setCurrentAppLocale(AppLocale locale) => _currentAppLocale = locale;

/// 无 context 取文案。详见 [_currentAppLocale] 的说明。
String T(String key) => tr(key, _currentAppLocale);

/// 带参数的插值文案。
///
/// 为什么需要它：像「已记住 $n 条」这种句子，中文和英文的词序往往不同
/// （"Remembered $n items" vs "已记住 $n 条"），不能用 `'前缀 $x 后缀'`
/// 直接拼接 —— 那样一旦翻译，变量就会卡在错误的位置。
///
/// 用 `{}` 占位：源文案 '已记住 {} 条'，译文 'Remembered {} items'，
/// 再把实参按顺序填进去。这样每种语言都能自由调整语序。
///
/// 用法：`TP('已记住 {} 条', [n])`
// ignore: non_constant_identifier_names
String TP(String key, List<Object?> args) {
  var s = tr(key, _currentAppLocale);
  for (final a in args) {
    final i = s.indexOf('{}');
    if (i < 0) break;
    s = s.replaceRange(i, i + 2, '${a ?? ''}');
  }
  return s;
}
