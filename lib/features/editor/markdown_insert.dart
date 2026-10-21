import 'package:flutter/material.dart';
import 'package:hugosugar/app/i18n/l10n_scope.dart';

/// Markdown 语法插入。
///
/// 单独抽出来是因为「插入 + 光标落点」这套计算很容易写错，
/// 而且必须在纯函数层面可测 —— UI 里带着 TextField 很难断言。
///
/// 三条规则：
/// 1. **有选中**：把选区内容包起来，如选中「你好」点粗体 → `**你好**`
/// 2. **无选中**：插入标记并把光标放中间，如点粗体 → `**|**`，
///    这样用户接着打字就是粗体，不用先删占位符
/// 3. **行级标记**（标题、引用、列表）：作用在光标所在**整行**开头，
///    不在光标处乱插
class MarkdownInsert {
  /// 包裹型：粗体、斜体、删除线、行内代码
  static TextEditingValue wrap(
    TextEditingValue value, {
    required String marker,
    String? placeholder,
  }) {
    final sel = _safeSelection(value);
    final text = value.text;
    final selected = text.substring(sel.start, sel.end);

    if (sel.isCollapsed) {
      final word = placeholder ?? '';
      final insert = '$marker$word$marker';
      final newText = text.replaceRange(sel.start, sel.start, insert);
      // 有占位符就选中它（直接打字可替换）；否则光标落在两个标记中间
      final newSel = word.isEmpty
          ? TextSelection.collapsed(offset: sel.start + marker.length)
          : TextSelection(
              baseOffset: sel.start + marker.length,
              extentOffset: sel.start + marker.length + word.length,
            );
      return TextEditingValue(text: newText, selection: newSel);
    }

    final newText = text.replaceRange(
      sel.start,
      sel.end,
      '$marker$selected$marker',
    );
    // 保持选中原来那段内容，方便继续加别的格式
    return TextEditingValue(
      text: newText,
      selection: TextSelection(
        baseOffset: sel.start + marker.length,
        extentOffset: sel.end + marker.length,
      ),
    );
  }

  /// 行前缀型：`# `、`> `、`- `、`1. `
  ///
  /// 已存在同样前缀时再点一次就**取消**，这是工具栏按钮该有的手感。
  ///
  /// 光标要逐行精确跟踪：在行中间加 `> ` 后光标必须跟着后移 2 位，
  /// 否则用户会发现光标莫名其妙偏了。
  static TextEditingValue prefixLine(
    TextEditingValue value, {
    required String prefix,
  }) {
    final text = value.text;
    final sel = _safeSelection(value);
    final lineStart = _lineStartAt(text, sel.start);
    final lineEnd = _lineEndAt(text, sel.end);

    final block = text.substring(lineStart, lineEnd);
    final lines = block.split('\n');
    final allHave = lines.every((l) => l.trimLeft().startsWith(prefix));

    final buf = StringBuffer();
    int? newCaret;
    int? newExtent;

    for (var i = 0; i < lines.length; i++) {
      if (i > 0) buf.write('\n');
      final line = lines[i];
      final lineOutStart = buf.length;

      final trimmed = line.trimLeft();
      final indent = line.substring(0, line.length - trimmed.length);
      final prefixAt = line.indexOf(prefix);

      String out;
      if (allHave) {
        out = prefixAt < 0
            ? line
            : line.replaceRange(prefixAt, prefixAt + prefix.length, '');
      } else if (trimmed.isEmpty) {
        // 空行不加前缀，否则按一次就多一堆 `> ` 空行
        out = line;
      } else {
        out = '$indent$prefix$trimmed';
      }
      buf.write(out);

      // 把原选区端点映射到新位置
      final lineOrigStart = lineStart + _offsetInBlock(lines, i);
      final lineOrigEnd = lineOrigStart + line.length;
      if (newCaret == null &&
          sel.start >= lineOrigStart &&
          sel.start <= lineOrigEnd) {
        newCaret =
            lineOutStart + _mapOffset(line, out, sel.start - lineOrigStart);
      }
      if (newExtent == null &&
          sel.end >= lineOrigStart &&
          sel.end <= lineOrigEnd) {
        newExtent =
            lineOutStart + _mapOffset(line, out, sel.end - lineOrigStart);
      }
    }

    final out = buf.toString();
    final newText = text.replaceRange(lineStart, lineEnd, out);
    final delta = out.length - block.length;
    final base = newCaret ?? (sel.start + delta);
    final extent = newExtent ?? (sel.end + delta);

    return TextEditingValue(
      text: newText,
      selection: TextSelection(
        baseOffset: base.clamp(0, newText.length),
        extentOffset: extent.clamp(0, newText.length),
      ),
    );
  }

  /// 一行原文 -> 处理后，把行内偏移尽量映射过去。
  ///
  /// 前缀只会加在行首或从行首删掉，所以「行内已有内容」的偏移
  /// 只需按头部长度差平移；落在被增删前缀里的偏移则夹到边界。
  static int _mapOffset(String oldLine, String newLine, int offset) {
    if (offset <= 0) return 0;
    final oldTrim = oldLine.length - oldLine.trimLeft().length;
    final newTrim = newLine.length - newLine.trimLeft().length;

    if (offset <= oldTrim) {
      // 原光标在缩进里
      return offset.clamp(0, newTrim);
    }
    // 在正文部分：按前缀增删量平移
    final shift = newLine.trimLeft().length - oldLine.trimLeft().length;
    final mapped = offset + shift;
    if (mapped < 0) return 0;
    if (mapped > newLine.length) return newLine.length;
    return mapped;
  }

  /// 第 i 行在 block 内的起始偏移
  static int _offsetInBlock(List<String> lines, int i) {
    var n = 0;
    for (var k = 0; k < i; k++) {
      n += lines[k].length + 1; // +1 是换行符
    }
    return n;
  }

  /// 光标处插入一段固定文本（表格、分隔线、链接语法等）。
  static TextEditingValue insert(
    TextEditingValue value,
    String snippet, {
    int? caretOffsetFromStart,
  }) {
    final sel = _safeSelection(value);
    final text = value.text;
    final newText = text.replaceRange(sel.start, sel.end, snippet);
    final caret = sel.start + (caretOffsetFromStart ?? snippet.length);
    return TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: caret),
    );
  }

  /// 插入链接：有选中文本就用它当文字，否则给占位
  static TextEditingValue link(TextEditingValue value) {
    final sel = _safeSelection(value);
    final selected = value.text.substring(sel.start, sel.end);
    final label = selected.isEmpty ? T('链接文字') : selected;
    final snippet = '[$label](url)';
    final newText = value.text.replaceRange(sel.start, sel.end, snippet);
    // 光标选中 `url`，用户直接打字就能填地址
    final urlStart = sel.start + label.length + 3; // [label]( 之后
    return TextEditingValue(
      text: newText,
      selection: TextSelection(
        baseOffset: urlStart,
        extentOffset: urlStart + 3,
      ),
    );
  }

  /// 插入表格骨架
  static TextEditingValue table(TextEditingValue value) {
    const snippet =
        '\n'
        '| 列 1 | 列 2 |\n'
        '| --- | --- |\n'
        '| 内容 | 内容 |\n';
    return insert(value, snippet);
  }

  static TextSelection _safeSelection(TextEditingValue v) {
    final t = v.text;
    var s = v.selection.start;
    var e = v.selection.end;
    if (s < 0) s = 0;
    if (e < 0) e = 0;
    if (s > t.length) s = t.length;
    if (e > t.length) e = t.length;
    if (s > e) {
      final tmp = s;
      s = e;
      e = tmp;
    }
    return TextSelection(baseOffset: s, extentOffset: e);
  }

  static int _lineStartAt(String text, int offset) {
    if (offset <= 0) return 0;
    final i = text.lastIndexOf('\n', offset - 1);
    return i < 0 ? 0 : i + 1;
  }

  static int _lineEndAt(String text, int offset) {
    if (offset >= text.length) return text.length;
    final i = text.indexOf('\n', offset);
    return i < 0 ? text.length : i;
  }
}
