import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hugosugar/app/theme/app_theme.dart';
import 'package:hugosugar/core/settings/settings_controller.dart';
import 'package:hugosugar/features/settings/author_identity_dialog.dart';
import 'package:hugosugar/features/settings/author_suggestion.dart';

void main() {
  group('提交作者对话框', () {
    testWidgets('推断结果很慢时，对话框立即显示而不是干等', (tester) async {
      // 一个永远不完成的 Future，模拟网络卡死
      final never = Completer<AuthorSuggestion?>();

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: AuthorIdentityDialog(
            controller: SettingsController(),
            suggestions: never.future,
          ),
        ),
      ));
      // 只 pump 一帧：如果实现里 await 了这个 Future，这里什么都不会渲染
      await tester.pump();

      expect(find.text('提交作者'), findsOneWidget);
      expect(find.text('作者名'), findsOneWidget);
      expect(find.text('作者邮箱'), findsOneWidget);

      // 输入框可用 —— 这是关键，用户不等网络就能填
      await tester.enterText(find.byType(TextField).first, 'octocat');
      await tester.pump();
      expect(find.text('octocat'), findsOneWidget);
    });

    testWidgets('推断结果回来后占位提示更新', (tester) async {
      final ctrl = Completer<AuthorSuggestion?>();

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: AuthorIdentityDialog(
            controller: SettingsController(),
            suggestions: ctrl.future,
          ),
        ),
      ));
      await tester.pump();
      // 还没回来：用通用文案
      expect(find.text('留空则用 GitHub 登录名'), findsOneWidget);

      ctrl.complete(const AuthorSuggestion(
        name: 'octocat',
        email: 'me@example.com',
      ));
      // complete() 唤醒的是微任务，setState 要等这一轮微任务跑完才会标记
      // 元素为 dirty，所以需要**两次** pump：第一次跑微任务并标记，
      // 第二次才真正重建出新的 helperText。
      await tester.pump();
      await tester.pump();

      expect(find.text('留空则用 octocat'), findsOneWidget);
      expect(find.text('留空则用 me@example.com'), findsOneWidget);
    });

    testWidgets('推断失败（null）时保持通用占位，不崩', (tester) async {
      final ctrl = Completer<AuthorSuggestion?>();

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: AuthorIdentityDialog(
            controller: SettingsController(),
            suggestions: ctrl.future,
          ),
        ),
      ));
      await tester.pump();
      ctrl.complete(null);
      await tester.pump();
      await tester.pump();

      expect(find.text('留空则用 GitHub 登录名'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}