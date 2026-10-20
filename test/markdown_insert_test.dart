import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hugosugar/features/editor/markdown_insert.dart';

/// 便捷构造
TextEditingValue v(String text, int start, [int? end]) => TextEditingValue(
      text: text,
      selection: TextSelection(
        baseOffset: start,
        extentOffset: end ?? start,
      ),
    );

void main() {
  group('wrap 包裹型', () {
    test('有选中时用标记包住选区', () {
      final r = MarkdownInsert.wrap(v('你好世界', 0, 2), marker: '**');
      expect(r.text, '**你好**世界');
    });

    test('包裹后仍选中原内容', () {
      final r = MarkdownInsert.wrap(v('你好世界', 0, 2), marker: '**');
      expect(r.selection.textInside(r.text), '你好');
    });

    test('无选中时插入占位符并选中它', () {
      final r = MarkdownInsert.wrap(
        v('开头结尾', 2),
        marker: '**',
        placeholder: '粗体',
      );
      expect(r.text, '开头**粗体**结尾');
      expect(r.selection.textInside(r.text), '粗体');
    });

    test('无占位符时光标落在标记中间', () {
      final r = MarkdownInsert.wrap(v('', 0), marker: '**');
      expect(r.text, '****');
      expect(r.selection.baseOffset, 2);
    });

    test('光标在文本末尾也不会越界', () {
      final r = MarkdownInsert.wrap(v('abc', 3), marker: '_');
      expect(r.text, 'abc__');
    });

    test('反向选区（从右往左选）也能正确处理', () {
      // baseOffset=3, extentOffset=0
      final r = MarkdownInsert.wrap(v('abcdef', 3, 0), marker: '~~');
      expect(r.text, '~~abc~~def');
    });
  });

  group('prefixLine 行前缀', () {
    test('给当前行加标题前缀', () {
      final r = MarkdownInsert.prefixLine(v('正文内容', 2), prefix: '# ');
      expect(r.text, '# 正文内容');
    });

    test('光标在行中间时随前缀后移', () {
      final r = MarkdownInsert.prefixLine(v('正文内容', 2), prefix: '# ');
      // offset 2 指向「内」（正0 文1 内2 容3），加 2 字符前缀后应仍指向「内」
      expect(r.selection.baseOffset, 4);
      expect(r.text[r.selection.baseOffset], '内');
    });

    test('再加一次相同前缀就取消', () {
      final once = MarkdownInsert.prefixLine(v('文字', 2), prefix: '> ');
      expect(once.text, '> 文字');
      final twice = MarkdownInsert.prefixLine(once, prefix: '> ');
      expect(twice.text, '文字');
    });

    test('多行选区逐行加前缀', () {
      const text = '第一行\n第二行\n第三行';
      final r = MarkdownInsert.prefixLine(
        v(text, 0, text.length),
        prefix: '- ',
      );
      expect(r.text, '- 第一行\n- 第二行\n- 第三行');
    });

    test('空行不加前缀', () {
      const text = '甲\n\n乙';
      final r = MarkdownInsert.prefixLine(
        v(text, 0, text.length),
        prefix: '> ',
      );
      expect(r.text, '> 甲\n\n> 乙');
    });

    test('保留原有缩进', () {
      final r = MarkdownInsert.prefixLine(
        v('  缩进文字', 5),
        prefix: '- ',
      );
      expect(r.text, '  - 缩进文字');
    });
  });

  group('insert 直接插入', () {
    test('在光标处插入并移动光标', () {
      final r = MarkdownInsert.insert(v('abc', 1), 'XY');
      expect(r.text, 'aXYbc');
      expect(r.selection.baseOffset, 3);
    });

    test('有选区时替换选区', () {
      final r = MarkdownInsert.insert(v('abcdef', 1, 3), 'X');
      expect(r.text, 'aXdef');
    });

    test('表格插入后光标在插入内容之后', () {
      final r = MarkdownInsert.table(v('段落', 2));
      expect(r.text.contains('| 列 1 | 列 2 |'), isTrue);
      expect(r.selection.baseOffset, r.text.length);
    });
  });

  group('link 链接', () {
    test('有选中文字时用它当链接文字', () {
      final r = MarkdownInsert.link(v('点这里', 0, 3));
      expect(r.text, '[点这里](url)');
    });

    test('无选中时用占位文字', () {
      final r = MarkdownInsert.link(v('', 0));
      expect(r.text, '[链接文字](url)');
    });

    test('插入后选中 url 方便直接替换', () {
      final r = MarkdownInsert.link(v('', 0));
      expect(r.selection.textInside(r.text), 'url');
    });
  });

  group('边界安全', () {
    test('选区越界会被夹紧而不是抛异常', () {
      final bad = const TextEditingValue(
        text: 'abc',
        selection: TextSelection(baseOffset: 99, extentOffset: 120),
      );
      final r = MarkdownInsert.wrap(bad, marker: '**');
      expect(r.text, 'abc****');
    });

    test('空文本加行前缀不报错', () {
      final r = MarkdownInsert.prefixLine(v('', 0), prefix: '# ');
      expect(r.text, isEmpty);
    });
  });
}