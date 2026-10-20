import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hugosugar/app/theme/app_theme.dart';
import 'package:hugosugar/core/settings/settings_controller.dart';
import 'package:hugosugar/features/settings/author_identity_dialog.dart';
import 'package:hugosugar/features/settings/author_suggestion.dart';

/// 必填模式：首次登录拿不到账号资料时的兜底。
///
/// 背景：如果放任用户不填就继续，提交作者会落到
/// `noreply@localhost`，GitHub 上看到的是陌生名字、贡献格子不亮，
/// 而用户完全不知道原因。所以在登录流程里强制填清楚。
void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: child),
      );

  group('AuthorSuggestion.isComplete', () {
    test('名和邮箱都有 → 完整', () {
      const s = AuthorSuggestion(name: 'octocat', email: 'me@example.com');
      expect(s.isComplete, isTrue);
    });

    test('只有名字 → 不完整', () {
      const s = AuthorSuggestion(name: 'octocat');
      expect(s.isComplete, isFalse);
    });

    test('邮箱是空白串 → 不完整', () {
      const s = AuthorSuggestion(name: 'octocat', email: '   ');
      expect(s.isComplete, isFalse);
    });

    test('名字是空白串 → 不完整', () {
      const s = AuthorSuggestion(name: '  ', email: 'me@example.com');
      expect(s.isComplete, isFalse);
    });
  });

  group('必填模式对话框', () {
    testWidgets('名字为空时点继续会报错，不关闭', (tester) async {
      final sc = SettingsController();
      await tester.pumpWidget(
        wrap(AuthorIdentityDialog(controller: sc, required: true)),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(1), 'me@example.com');
      await tester.tap(find.text('继续'));
      await tester.pumpAndSettle();

      expect(find.text('请填写作者名'), findsOneWidget);
      // 面板仍在
      expect(find.text('提交作者'), findsOneWidget);
    });

    testWidgets('邮箱为空时点继续会报错，不关闭', (tester) async {
      final sc = SettingsController();
      await tester.pumpWidget(
        wrap(AuthorIdentityDialog(controller: sc, required: true)),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'octocat');
      await tester.tap(find.text('继续'));
      await tester.pumpAndSettle();

      expect(find.text('请填写作者邮箱'), findsOneWidget);
    });

    testWidgets('两个都填了才能保存', (tester) async {
      final sc = SettingsController();
      await tester.pumpWidget(
        wrap(AuthorIdentityDialog(controller: sc, required: true)),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'octocat');
      await tester.enterText(find.byType(TextField).at(1), 'me@example.com');
      await tester.tap(find.text('继续'));
      await tester.pumpAndSettle();

      expect(sc.authorName, 'octocat');
      expect(sc.authorEmail, 'me@example.com');
    });

    testWidgets('必填模式不显示「恢复自动」', (tester) async {
      final sc = SettingsController();
      await tester.pumpWidget(
        wrap(AuthorIdentityDialog(controller: sc, required: true)),
      );
      await tester.pumpAndSettle();

      expect(find.text('恢复自动'), findsNothing);
    });

    testWidgets('非必填模式仍显示「恢复自动」', (tester) async {
      final sc = SettingsController();
      await tester.pumpWidget(
        wrap(AuthorIdentityDialog(controller: sc)),
      );
      await tester.pumpAndSettle();

      expect(find.text('恢复自动'), findsOneWidget);
      expect(find.text('保存'), findsOneWidget);
    });

    testWidgets('邮箱格式不对会被拦下', (tester) async {
      final sc = SettingsController();
      await tester.pumpWidget(
        wrap(AuthorIdentityDialog(controller: sc, required: true)),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'octocat');
      await tester.enterText(find.byType(TextField).at(1), 'not-an-email');
      await tester.tap(find.text('继续'));
      await tester.pumpAndSettle();

      expect(find.text('邮箱格式不对'), findsOneWidget);
      expect(sc.authorEmail, isEmpty);
    });
  });
}