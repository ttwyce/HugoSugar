import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hugosugar/app/i18n/l10n_scope.dart';
import 'package:hugosugar/app/i18n/strings.dart';
import 'package:hugosugar/core/settings/app_settings.dart';

/// 最小可用的语言设置，模拟 SettingsController 的 notify 行为。
class _FakeSettings extends ChangeNotifier {
  String _localeId = 'zh';
  String get localeId => _localeId;
  void setLocale(String id) {
    if (_localeId == id) return;
    _localeId = id;
    notifyListeners();
  }
}

/// 模拟 main.dart 的顶层 State：订阅 notifier，收到通知就重建。
class _Subscribed extends StatefulWidget {
  const _Subscribed({required this.notifier, required this.builder});
  final Listenable notifier;
  final Widget Function() builder;
  @override
  State<_Subscribed> createState() => _SubscribedState();
}

class _SubscribedState extends State<_Subscribed> {
  void _onChange() => setState(() {});

  @override
  void initState() {
    super.initState();
    widget.notifier.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.notifier.removeListener(_onChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder();
}

void main() {
  group('AppLocale', () {
    test('id 往返', () {
      expect(AppLocale.fromId('zh'), AppLocale.zh);
      expect(AppLocale.fromId('en'), AppLocale.en);
    });

    test('未知 id 回落中文', () {
      expect(AppLocale.fromId(null), AppLocale.zh);
      expect(AppLocale.fromId('fr'), AppLocale.zh);
      expect(AppLocale.fromId(''), AppLocale.zh);
    });

    test('系统语言映射：中文 -> zh，其他 -> en', () {
      expect(AppLocale.fromSystem(const Locale('zh')), AppLocale.zh);
      expect(AppLocale.fromSystem(const Locale('zh', 'CN')), AppLocale.zh);
      expect(AppLocale.fromSystem(const Locale('en')), AppLocale.en);
      expect(AppLocale.fromSystem(const Locale('ja')), AppLocale.en);
    });

    test('label 用各自语言书写', () {
      expect(AppLocale.zh.label, '中文');
      expect(AppLocale.en.label, 'English');
    });
  });

  group('文案表', () {
    test('每个条目 zh 和 en 都非空', () {
      for (final e in kStrings.entries) {
        expect(e.value.zh.trim(), isNotEmpty, reason: '${e.key} 的 zh 为空');
        expect(e.value.en.trim(), isNotEmpty, reason: '${e.key} 的 en 为空');
      }
    });

    test('key 与 zh 一致（中文原文当 key 的约定）', () {
      for (final e in kStrings.entries) {
        expect(e.key, e.value.zh, reason: 'key 必须等于中文原文，否则回落会失效');
      }
    });

    test('英文里不应残留中文', () {
      final cjk = RegExp(r'[\u4e00-\u9fff]');
      for (final e in kStrings.entries) {
        expect(
          cjk.hasMatch(e.value.en),
          isFalse,
          reason: '${e.key} 的英文里混入了中文：${e.value.en}',
        );
      }
    });
  });

  group('tr()', () {
    test('中文环境返回中文', () {
      expect(tr('取消', AppLocale.zh), '取消');
    });

    test('英文环境返回英文', () {
      expect(tr('取消', AppLocale.en), 'Cancel');
    });

    test('缺 key 时原样返回（等于优雅回落中文）', () {
      expect(tr('这条没翻译过', AppLocale.en), '这条没翻译过');
    });
  });

  group('L10nScope', () {
    testWidgets('没有 scope 时回落中文', (tester) async {
      late String text;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) {
              text = ctx.tr('取消');
              return const SizedBox();
            },
          ),
        ),
      );
      expect(text, '取消');
    });

    testWidgets('有 scope 时用 scope 的语言', (tester) async {
      late String text;
      await tester.pumpWidget(
        MaterialApp(
          builder: (ctx, child) =>
              L10nScope(locale: AppLocale.en, child: child ?? const SizedBox()),
          home: Builder(
            builder: (ctx) {
              text = ctx.tr('取消');
              return const SizedBox();
            },
          ),
        ),
      );
      expect(text, 'Cancel');
    });

    testWidgets('语言变化会通知依赖者重建', (tester) async {
      var seen = <String>[];
      Widget build(AppLocale loc) => MaterialApp(
        builder: (ctx, child) =>
            L10nScope(locale: loc, child: child ?? const SizedBox()),
        home: Builder(
          builder: (ctx) {
            seen.add(ctx.tr('保存'));
            return const SizedBox();
          },
        ),
      );

      await tester.pumpWidget(build(AppLocale.zh));
      await tester.pumpWidget(build(AppLocale.en));
      expect(seen, containsAll(['保存', 'Save']));
    });
  });

  group('切换语言立即生效（顶层订阅回归）', () {
    // 这条固定的是 main.dart 里那次修复：
    // L10nScope 挂在 MaterialApp.builder，locale 是构建时快照。
    // 若顶层 State 不 addListener(SettingsController)，切语言时
    // 只有设置页 setState，顶层不重建 → 文案停在旧语言，需重启。
    testWidgets('notifyListeners 后界面文案立刻变英文', (tester) async {
      final settings = _FakeSettings();
      var seen = <String>[];

      // 模拟 main.dart 的结构：顶层 State 订阅并 setState。
      Widget build() => MaterialApp(
        builder: (ctx, child) => L10nScope(
          locale: AppLocale.fromId(settings.localeId),
          child: child ?? const SizedBox(),
        ),
        home: Builder(
          builder: (ctx) {
            seen.add(ctx.tr('取消'));
            return const SizedBox();
          },
        ),
      );

      await tester.pumpWidget(_Subscribed(notifier: settings, builder: build));
      expect(seen.last, '取消');

      settings.setLocale('en');
      await tester.pump();
      expect(seen.last, 'Cancel');
    });
  });

  group('AppSettings.localeId', () {
    test('默认中文', () {
      expect(const AppSettings().localeId, 'zh');
    });

    test('序列化往返', () {
      const s = AppSettings(localeId: 'en');
      expect(AppSettings.fromJson(s.toJson()).localeId, 'en');
    });

    test('旧配置无此字段时回落中文', () {
      final s = AppSettings.fromJson(
        Map<String, Object?>.from({'dateFormat': 'iso'}),
      );
      expect(s.localeId, 'zh');
    });
  });
}
