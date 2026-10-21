import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hugosugar/app/theme/app_theme.dart';
import 'package:hugosugar/features/ai/chat_markdown.dart';
import 'package:hugosugar/features/editor/editor_page.dart';

/// 编辑器「预览」是真·就地切换：正文区从可编辑源码变成富文本渲染，
/// 不弹底部面板、不遮正文。
void main() {
  Widget host() => MaterialApp(
    theme: AppTheme.light(accentIndex: 0),
    home: const EditorPage(title: '测试文章'),
  );

  testWidgets('点预览把正文 TextField 换成 ChatMarkdown，再点回编辑', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    // 初始是编辑模式：正文区存在可编辑 TextField（带 '正文…' 提示那个）
    expect(find.byType(ChatMarkdown), findsNothing);

    // 输入一点正文
    final bodyField = find.byType(TextField).last;
    await tester.enterText(bodyField, '# 标题\n\n这是**正文**。');
    await tester.pumpAndSettle();

    // 点「预览」
    await tester.tap(find.text('预览'));
    await tester.pumpAndSettle();

    // 现在应出现 ChatMarkdown（就地渲染），且原正文 TextField 不再显示
    expect(find.byType(ChatMarkdown), findsOneWidget);
    // 按钮文案变成「编辑」
    expect(find.text('编辑'), findsOneWidget);

    // 再点「编辑」切回
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    expect(find.byType(ChatMarkdown), findsNothing);
    expect(find.text('预览'), findsOneWidget);
  });

  testWidgets('编辑器不再有 AI 按钮', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.text('AI'), findsNothing);
  });
}