import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hugosugar/app/theme/app_theme.dart';
import 'package:hugosugar/features/ai/chat_markdown.dart';

/// AI 回复的 Markdown 渲染。
///
/// 用户原始反馈：「模型返回的 md 格式没有解析，而是直接输出成了文字」。
/// 所以核心断言是**标记符必须消失**：只要 `**`、反引号、`#` 还留在
/// 可见文本里，就说明没渲染。
///
/// 注意收集方式：渲染器把正文放在 `SelectableText`（行内富文本）和
/// `Text`（列表符号、代码语言标签）两种 widget 里。**不能**只统计
/// `RichText` —— `Text` 内部也会生成 `RichText`，会重复计数；而
/// `SelectableText` 不是 `RichText` 的子类，只统计 `RichText` 会漏掉正文。
/// 这里统一从 `SelectableText.data / textSpan` 和 `Text.data` 取。
void main() {
  Widget wrap(String md) => MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: SingleChildScrollView(child: ChatMarkdown(md))),
      );

  /// 收集所有可见文本（去重来源，避免重复计数）
  String visibleText(WidgetTester tester) {
    final buf = StringBuffer();
    for (final w in tester.widgetList<SelectableText>(find.byType(SelectableText))) {
      buf.write(w.data ?? w.textSpan?.toPlainText() ?? '');
    }
    for (final w in tester.widgetList<Text>(find.byType(Text))) {
      buf.write(w.data ?? w.textSpan?.toPlainText() ?? '');
    }
    return buf.toString();
  }

  /// 找出「包含某段文字、且该样式生效」的 TextSpan。
  ///
  /// 不能只匹配 `span.text == piece`：`**粗体**` 解析出来的外层
  /// `strong` span 的 `text` 是 null、真正的文字挂在子 span 上，
  /// 样式在**父** span 里。所以要自顶向下继承样式再比对文字。
  TextStyle? styleOf(WidgetTester tester, String piece) {
    TextStyle? hit;

    void walk(InlineSpan span, TextStyle? inherited) {
      if (hit != null) return;
      final merged = inherited?.merge(span.style) ?? span.style;

      if (span is TextSpan) {
        // 命中最内层：文字完全等于目标，且当前有效样式带特征
        if (span.text == piece && merged != null) {
          // 只要找到一个「样式确实生效在这个 span 上」的即可
          hit = merged;
          return;
        }
        for (final child in span.children ?? const <InlineSpan>[]) {
          walk(child, merged);
        }
      }
    }

    for (final w in tester.widgetList<SelectableText>(
      find.byType(SelectableText),
    )) {
      final root = w.textSpan;
      if (root != null) walk(root, null);
      if (hit != null) break;
    }
    return hit;
  }

  testWidgets('粗体：标记消失且实际加粗', (tester) async {
    await tester.pumpWidget(wrap('这是 **粗体文字** 结尾'));
    await tester.pump();

    final text = visibleText(tester);
    expect(text, contains('粗体文字'));
    expect(text, isNot(contains('**')), reason: '星号必须被吃掉');
    expect(styleOf(tester, '粗体文字')?.fontWeight, FontWeight.w700);
  });

  testWidgets('标题：井号消失', (tester) async {
    await tester.pumpWidget(wrap('# 一级标题\n\n正文内容'));
    await tester.pump();

    final text = visibleText(tester);
    expect(text, contains('一级标题'));
    expect(text, contains('正文内容'));
    expect(text, isNot(contains('#')), reason: '井号必须被吃掉');

    // 标题字号要大于正文 14
    final style = styleOf(tester, '一级标题');
    expect(style?.fontSize, isNotNull);
    expect(style!.fontSize! > 14, isTrue, reason: '标题字号应大于正文');
  });

  testWidgets('代码：行内与围栏都不留反引号', (tester) async {
    await tester.pumpWidget(wrap(
      '行内 `code_here` 结束\n\n```dart\nvoid main() {}\n```\n',
    ));
    await tester.pump();

    final text = visibleText(tester);
    expect(text, contains('code_here'));
    expect(text, contains('void main() {}'));
    expect(text, isNot(contains('```')), reason: '三反引号必须被吃掉');
    expect(find.text('dart'), findsOneWidget, reason: '语言标签应显示');
  });

  testWidgets('无序列表：渲染成圆点', (tester) async {
    await tester.pumpWidget(wrap('- 第一项\n- 第二项\n'));
    await tester.pump();

    final text = visibleText(tester);
    expect(text, contains('第一项'));
    expect(text, contains('第二项'));
    expect(find.text('•'), findsNWidgets(2));
  });

  testWidgets('有序列表：序号递增', (tester) async {
    await tester.pumpWidget(wrap('1. 甲\n2. 乙\n3. 丙\n'));
    await tester.pump();

    expect(find.text('1.'), findsOneWidget);
    expect(find.text('2.'), findsOneWidget);
    expect(find.text('3.'), findsOneWidget);
    expect(visibleText(tester), contains('丙'));
  });

  testWidgets('引用：大于号消失', (tester) async {
    await tester.pumpWidget(wrap('> 被引用的一句话'));
    await tester.pump();

    final text = visibleText(tester);
    expect(text, contains('被引用的一句话'));
    expect(text, isNot(contains('>')));
  });

  testWidgets('斜体与删除线标记消失', (tester) async {
    await tester.pumpWidget(wrap('*斜体* 和 ~~删掉~~'));
    await tester.pump();

    final text = visibleText(tester);
    expect(text, contains('斜体'));
    expect(text, contains('删掉'));
    expect(text, isNot(contains('~~')));
    expect(styleOf(tester, '斜体')?.fontStyle, FontStyle.italic);
  });

  testWidgets('空内容不崩', (tester) async {
    await tester.pumpWidget(wrap(''));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('裸文本正常显示', (tester) async {
    await tester.pumpWidget(wrap('就这样一句话，没有任何 Markdown。'));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(visibleText(tester), contains('就这样一句话'));
  });

  testWidgets('泛型尖括号不被转义', (tester) async {
    // encodeHtml 若为 true，会变成 List&lt;String&gt;
    await tester.pumpWidget(wrap('用 `List<String>` 声明'));
    await tester.pump();

    final text = visibleText(tester);
    expect(text, contains('<String>'));
    expect(text, isNot(contains('&lt;')));
  });

  testWidgets('流式中间态：未闭合代码块不崩', (tester) async {
    // 流式输出过程中必然出现半截文本
    await tester.pumpWidget(wrap('看这段：\n\n```dart\nvoid main() {'));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(visibleText(tester), contains('void main() {'));
  });

  testWidgets('混合长回复整体正确', (tester) async {
    await tester.pumpWidget(wrap('''
# 标题

第一段有 **粗体**、*斜体*、`代码` 和 [链接](https://example.com)。

## 二级

- 项目一
- 项目二
  - 嵌套项

1. 步骤一
2. 步骤二

> 引用内容

```python
def f(x):
    return x + 1
```

---
结尾。
'''));
    await tester.pump();

    expect(tester.takeException(), isNull);
    final text = visibleText(tester);
    expect(text, contains('粗体'));
    expect(text, contains('斜体'));
    expect(text, contains('项目二'));
    expect(text, contains('嵌套项'));
    expect(text, contains('步骤二'));
    expect(text, contains('引用内容'));
    expect(text, contains('return x + 1'));
    expect(text, contains('结尾'));
    // 所有标记符都该消失
    expect(text, isNot(contains('**')));
    expect(text, isNot(contains('```')));
    expect(text, isNot(contains('##')));
  });
}