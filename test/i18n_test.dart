import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hugosugar/app/i18n/l10n_scope.dart';
import 'package:hugosugar/app/i18n/strings.dart';
import 'package:hugosugar/core/settings/app_settings.dart';

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
        expect(e.key, e.value.zh,
            reason: 'key 必须等于中文原文，否则回落会失效');
      }
    });

    test('英文里不应残留中文', () {
      final cjk = RegExp(r'[\u4e00-\u9fff]');
      for (final e in kStrings.entries) {
        expect(cjk.hasMatch(e.value.en), isFalse,
            reason: '${e.key} 的英文里混入了中文：${e.value.en}');
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
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (ctx) {
          text = ctx.tr('取消');
          return const SizedBox();
        }),
      ));
      expect(text, '取消');
    });

    testWidgets('有 scope 时用 scope 的语言', (tester) async {
      late String text;
      await tester.pumpWidget(MaterialApp(
        builder: (ctx, child) => L10nScope(
          locale: AppLocale.en,
          child: child ?? const SizedBox(),
        ),
        home: Builder(builder: (ctx) {
          text = ctx.tr('取消');
          return const SizedBox();
        }),
      ));
      expect(text, 'Cancel');
    });

    testWidgets('语言变化会通知依赖者重建', (tester) async {
      var seen = <String>[];
      Widget build(AppLocale loc) => MaterialApp(
            builder: (ctx, child) => L10nScope(
              locale: loc,
              child: child ?? const SizedBox(),
            ),
            home: Builder(builder: (ctx) {
              seen.add(ctx.tr('保存'));
              return const SizedBox();
            }),
          );

      await tester.pumpWidget(build(AppLocale.zh));
      await tester.pumpWidget(build(AppLocale.en));
      expect(seen, containsAll(['保存', 'Save']));
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