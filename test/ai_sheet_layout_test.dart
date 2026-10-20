import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hugosugar/app/theme/app_theme.dart';
import 'package:hugosugar/core/ai/ai_controller.dart';
import 'package:hugosugar/features/ai/ai_endpoints_page.dart';
import 'package:hugosugar/features/ai/chat_page.dart';

/// 弹窗布局回归测试。
///
/// 背景：真机上点「添加端点」只看到遮罩、内容空白。
/// 根因是 showModalBottomSheet 的 builder 拿到**无界横向约束**，
/// OutlinedButton 内部的 ConstrainedBox 把 minWidth 算成 Infinity，
/// 布局阶段抛断言 → 渲染中断 → 只剩遮罩。
///
/// 这类问题 analyze 查不出来、纯逻辑测试也查不出来，
/// 只有真正把它 pump 出来看实际尺寸才能发现。
void main() {
  group('端点弹窗', () {
    testWidgets('点添加后必须渲染出内容，不能只有遮罩', (tester) async {
      final ctrl = AiController();
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: AiEndpointsPage(controller: ctrl),
      ));
      await tester.pump();

      await tester.tap(find.text('添加端点'));
      await tester.pumpAndSettle();

      // 关键断言：不能有未捕获异常
      expect(tester.takeException(), isNull);

      expect(find.byType(TextField), findsNWidgets(4));

      // 输入框必须有真实宽度（不是被压成 0 或被推成无限）
      final tf = tester.getSize(find.byType(TextField).first);
      expect(tf.width, greaterThan(100));
      expect(tf.width.isFinite, isTrue);
      expect(tf.height, greaterThan(20));
    });

    testWidgets('「获取列表」按钮宽度必须有限', (tester) async {
      final ctrl = AiController();
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: AiEndpointsPage(controller: ctrl),
      ));
      await tester.pump();

      await tester.tap(find.text('添加端点'));
      await tester.pumpAndSettle();

      final btn = find.widgetWithText(OutlinedButton, '获取列表');
      expect(btn, findsOneWidget);

      final size = tester.getSize(btn);
      // 这条就是崩溃的直接触发点
      expect(size.width.isFinite, isTrue);
      expect(size.width, greaterThan(20));
      expect(size.height.isFinite, isTrue);
    });

    testWidgets('保存按钮可见可点', (tester) async {
      final ctrl = AiController();
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: AiEndpointsPage(controller: ctrl),
      ));
      await tester.pump();

      await tester.tap(find.text('添加端点'));
      await tester.pumpAndSettle();

      final save = find.widgetWithText(FilledButton, '保存');
      expect(save, findsOneWidget);
      expect(tester.getSize(save).width.isFinite, isTrue);
    });

    testWidgets('必填校验：地址为空时保存被拦下', (tester) async {
      final ctrl = AiController();
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: AiEndpointsPage(controller: ctrl),
      ));
      await tester.pump();

      await tester.tap(find.text('添加端点'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();

      expect(find.text('请填写接口地址'), findsOneWidget);
    });
  });

  group('历史弹窗', () {
    testWidgets('空列表时不崩且能看到提示', (tester) async {
      final ctrl = AiController();
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: ChatPage(controller: ctrl),
      ));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.history));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('历史对话'), findsOneWidget);
      expect(find.text('还没有历史对话'), findsOneWidget);
    });

    testWidgets('弹窗高度受限，不超出屏幕', (tester) async {
      final ctrl = AiController();
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: ChatPage(controller: ctrl),
      ));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.history));
      await tester.pumpAndSettle();

      final sheet = find.byType(BottomSheet);
      expect(sheet, findsOneWidget);

      final size = tester.getSize(sheet);
      final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
      expect(size.height, lessThanOrEqualTo(screen.height));
      expect(size.width.isFinite, isTrue);
    });
  });
}