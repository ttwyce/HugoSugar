import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hugosugar/features/editor/markdown_highlighter.dart';

const _accent = Color(0xFF2E6B4F);
const _dim = Color(0xFF9E9E9E);
const _code = Color(0xFFF0F0F0);
const _base = Color(0xFF000000);

List<MdHighlight> scan(String text) => MarkdownHighlighter.scan(
      text,
      base: _base,
      accent: _accent,
      dim: _dim,
      codeBg: _code,
    );

/// 取某段文字对应的样式
TextStyle? styleAt(String text, int offset) {
  final spans = scan(text);
  for (final h in spans) {
    if (offset >= h.start && offset < h.end) return h.style;
  }
  return null;
}

void main() {
  group('基本结构', () {
    test('空文本没有区间', () {
      expect(scan(''), isEmpty);
    });

    test('纯文本没有区间', () {
      expect(scan('就是普通的一段话。'), isEmpty);
    });

    test('区间按 start 升序且互不重叠', () {
      final text = '# 标题\n\n**粗体** 和 *斜体* 还有 `code`\n';
      final spans = scan(text);
      var last = 0;
      for (final h in spans) {
        expect(h.start, greaterThanOrEqualTo(last),
            reason: '区间重叠或乱序：$spans');
        expect(h.end, greaterThan(h.start));
        expect(h.end, lessThanOrEqualTo(text.length));
        last = h.end;
      }
    });
  });

  group('标题', () {
    test('H1 用 accent 色且字重加粗', () {
      const text = '# 一级标题';
      final s = styleAt(text, 2);
      expect(s, isNotNull);
      expect(s!.color, _accent);
      expect(s.fontWeight, FontWeight.w700);
    });

    test('H3 字号小于 H1', () {
      final h1 = styleAt('# 标题', 2)!;
      final h3 = styleAt('### 标题', 4)!;
      expect(h3.fontSize! < h1.fontSize!, isTrue);
    });

    test('#后面没有空格不算标题', () {
      expect(styleAt('#不是标题', 2), isNull);
    });
  });

  group('代码', () {
    test('行内代码有等宽字体和底色', () {
      const text = '这是 `code` 行内代码';
      final s = styleAt(text, 5);
      expect(s, isNotNull);
      expect(s!.fontFamily, 'monospace');
      expect(s.backgroundColor, _code);
    });

    test('围栏代码块整体着色', () {
      const text = '```dart\nvoid main() {}\n```';
      // 代码块内部
      expect(styleAt(text, 10), isNotNull);
    });

    test('代码块内的 # 不被当作标题', () {
      const text = '```\n# 这是代码不是标题\n```';
      // 位置 5 落在代码块内
      final s = styleAt(text, 5);
      expect(s, isNotNull);
      // 应该是代码样式（等宽字体），不是标题样式
      expect(s!.fontFamily, 'monospace');
    });
  });

  group('强调', () {
    test('粗体', () {
      const text = '这是 **加粗** 文字';
      final s = styleAt(text, 5);
      expect(s, isNotNull);
      expect(s!.fontWeight, FontWeight.w700);
    });

    test('斜体', () {
      const text = '这是 *斜体* 文字';
      final s = styleAt(text, 4);
      expect(s, isNotNull);
      expect(s!.fontStyle, FontStyle.italic);
    });

    test('粗体不会被斜体规则吃掉', () {
      const text = '**粗体**';
      final s = styleAt(text, 2);
      expect(s!.fontWeight, FontWeight.w700);
      // 粗体区间应覆盖整段
      final spans = scan(text);
      expect(spans.length, 1);
    });

    test('删除线', () {
      const text = '这是 ~~删掉~~ 文字';
      final s = styleAt(text, 4);
      expect(s, isNotNull);
      expect(s!.decoration, TextDecoration.lineThrough);
    });
  });

  group('其它结构', () {
    test('引用', () {
      const text = '> 引用的一段话';
      final s = styleAt(text, 3);
      expect(s, isNotNull);
      expect(s!.fontStyle, FontStyle.italic);
    });

    test('无序列表符号着色', () {
      const text = '- 列表项';
      expect(styleAt(text, 0), isNotNull);
    });

    test('有序列表符号着色', () {
      const text = '1. 第一项';
      expect(styleAt(text, 0), isNotNull);
    });

    test('链接', () {
      const text = '见 [文档](http://a.com) 说明';
      final s = styleAt(text, 3);
      expect(s, isNotNull);
      expect(s!.color, _accent);
    });

    test('图片', () {
      const text = '![图](http://a.com/x.png)';
      expect(styleAt(text, 0), isNotNull);
    });

    test('水平线', () {
      const text = '---';
      expect(styleAt(text, 1), isNotNull);
    });
  });

  group('健壮性', () {
    test('未闭合的粗体不崩', () {
      expect(() => scan('**没闭合'), returnsNormally);
    });

    test('未闭合的代码块不崩', () {
      expect(() => scan('```dart\n代码没结束'), returnsNormally);
    });

    test('超长文本不崩', () {
      final long = '# 标题\n${'正文内容。' * 5000}';
      expect(() => scan(long), returnsNormally);
    });

    test('纯符号不崩', () {
      expect(() => scan('******'), returnsNormally);
      expect(() => scan('```'), returnsNormally);
      expect(() => scan('[]()'), returnsNormally);
    });
  });

  group('TextSpan 合成', () {
    test('拼接结果文本完整不丢字', () {
      const text = '# 标题\n正文 **粗体** 结尾';
      final spans = scan(text);
      final span = MarkdownHighlighter.build(
        text: text,
        spans: spans,
        base: const TextStyle(),
      );
      expect(span.toPlainText(), text);
    });

    test('没有区间时返回单 span', () {
      final span = MarkdownHighlighter.build(
        text: '纯文本',
        spans: const [],
        base: const TextStyle(),
      );
      expect(span.toPlainText(), '纯文本');
    });
  });
}