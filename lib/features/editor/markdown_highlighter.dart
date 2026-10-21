import 'package:flutter/material.dart';

/// Markdown 语法高亮的着色结果。
///
/// 为什么不用 TextSpan 树而要算区间：编辑器的文字是用户在敲的，
/// 每次按键都要重算。用「区间 + 合并」比构造嵌套 span 树便宜得多，
/// 而且不用担心手势识别被 span 打断。
class MdHighlight {
  const MdHighlight(this.start, this.end, this.style);

  final int start;
  final int end;
  final TextStyle style;
}

/// Markdown 高亮器。
///
/// 设计取舍：
/// - **只做行内正则扫描，不建 AST**。编辑器要的是响应速度，不是准确性。
///   真正的 Markdown 解析留给预览页。
/// - **优先级从高到低**：代码块 > 行内代码 > 标题 > 引用 >
///   粗体/斜体/删除线 > 链接 > 列表符号。
///   高优先级的区间先占坑，低优先级的遇到已占区间就跳过，
///   避免同一段文字被反复染色。
class MarkdownHighlighter {
  MarkdownHighlighter._();

  /// 扫描全文，返回按 start 升序、互不重叠的着色区间
  static List<MdHighlight> scan(
    String text, {
    required Color base,
    required Color accent,
    required Color dim,
    required Color codeBg,
    TextStyle? baseStyle,
  }) {
    if (text.isEmpty) return const [];

    final out = <MdHighlight>[];
    // 已占用的区间，用于跳过重叠
    final taken = <(int, int)>[];

    bool overlaps(int s, int e) {
      for (final (ts, te) in taken) {
        if (s < te && e > ts) return true;
      }
      return false;
    }

    void add(int s, int e, TextStyle style) {
      if (s >= e) return;
      if (overlaps(s, e)) return;
      taken.add((s, e));
      out.add(MdHighlight(s, e, style));
    }

    final baseT = baseStyle ?? const TextStyle();

    // ── 1) 围栏代码块 ``` ... ```（最高优先级）──
    final fence = RegExp(r'```[^\n]*\n[\s\S]*?(\n```|$)');
    for (final m in fence.allMatches(text)) {
      add(
        m.start,
        m.end,
        baseT.copyWith(
          color: accent.withValues(alpha: 0.75),
          backgroundColor: codeBg,
          fontFamily: 'monospace',
          fontFamilyFallback: const ['Menlo', 'Courier'],
        ),
      );
    }

    // ── 2) 行内代码 `code` ──
    for (final m in RegExp(r'`[^`\n]+`').allMatches(text)) {
      add(
        m.start,
        m.end,
        baseT.copyWith(
          color: accent,
          backgroundColor: codeBg,
          fontFamily: 'monospace',
          fontFamilyFallback: const ['Menlo', 'Courier'],
        ),
      );
    }

    // ── 3) 标题 # ## ### ──
    final heading = RegExp(r'^(#{1,6})[ \t]+.*$', multiLine: true);
    for (final m in heading.allMatches(text)) {
      final level = m.group(1)!.length;
      add(
        m.start,
        m.end,
        baseT.copyWith(
          color: accent,
          fontWeight: level <= 2 ? FontWeight.w700 : FontWeight.w600,
          fontSize: _headingSize(level, baseStyle?.fontSize ?? 17),
        ),
      );
    }

    // ── 4) 引用 > ──
    for (final m in RegExp(r'^[ \t]*>.*$', multiLine: true).allMatches(text)) {
      add(
        m.start,
        m.end,
        baseT.copyWith(color: dim, fontStyle: FontStyle.italic),
      );
    }

    // ── 5) 列表符号 - * + 1. ──
    for (final m in RegExp(
      r'^[ \t]*([-*+]|\d+\.)[ \t]',
      multiLine: true,
    ).allMatches(text)) {
      add(m.start, m.end, baseT.copyWith(color: accent.withValues(alpha: 0.8)));
    }

    // ── 6) 粗体 **x** / __x__ ──
    for (final m in RegExp(
      r'(\*\*|__)(?=\S)[\s\S]*?(?<=\S)\1',
    ).allMatches(text)) {
      add(
        m.start,
        m.end,
        baseT.copyWith(color: base, fontWeight: FontWeight.w700),
      );
    }

    // ── 7) 斜体 *x* / _x_（注意不能吃掉粗体的星号）──
    for (final m in RegExp(
      r'(?<![*_])([*_])(?=\S)[^*_\n]*?(?<=\S)\1(?![*_])',
    ).allMatches(text)) {
      add(
        m.start,
        m.end,
        baseT.copyWith(color: base, fontStyle: FontStyle.italic),
      );
    }

    // ── 8) 删除线 ~~x~~ ──
    for (final m in RegExp(r'~~(?=\S).*?(?<=\S)~~').allMatches(text)) {
      add(
        m.start,
        m.end,
        baseT.copyWith(color: dim, decoration: TextDecoration.lineThrough),
      );
    }

    // ── 9) 链接 [text](url) 与图片 ![alt](url) ──
    for (final m in RegExp(r'!?\[[^\]]*\]\([^)]*\)').allMatches(text)) {
      add(m.start, m.end, baseT.copyWith(color: accent));
    }

    // ── 10) 水平线 --- ──
    for (final m in RegExp(
      r'^[ \t]*([-*_])([ \t]*\1){2,}[ \t]*$',
      multiLine: true,
    ).allMatches(text)) {
      add(m.start, m.end, baseT.copyWith(color: dim));
    }

    out.sort((a, b) => a.start.compareTo(b.start));
    return out;
  }

  /// 标题字号随层级递减，但不超过编辑器正文字号的 1.5 倍
  static double _headingSize(int level, double base) {
    switch (level) {
      case 1:
        return base * 1.5;
      case 2:
        return base * 1.32;
      case 3:
        return base * 1.18;
      case 4:
        return base * 1.08;
      default:
        return base;
    }
  }

  /// 把着色区间 + 基础文本合成 TextSpan 树。
  ///
  /// 用 TextEditingController.buildTextSpan 的 override 注入，
  /// 这样输入法、光标、选区都不受影响。
  static TextSpan build({
    required String text,
    required List<MdHighlight> spans,
    required TextStyle base,
    TextRange? composing,
  }) {
    if (spans.isEmpty) {
      return TextSpan(text: text, style: base);
    }

    final children = <TextSpan>[];
    var cursor = 0;

    for (final h in spans) {
      // 防御：区间越界或乱序时直接跳过，绝不让渲染崩
      if (h.start < cursor || h.end > text.length || h.start >= h.end) {
        continue;
      }
      if (h.start > cursor) {
        children.add(TextSpan(text: text.substring(cursor, h.start)));
      }
      children.add(
        TextSpan(text: text.substring(h.start, h.end), style: h.style),
      );
      cursor = h.end;
    }

    if (cursor < text.length) {
      children.add(TextSpan(text: text.substring(cursor)));
    }

    return TextSpan(style: base, children: children);
  }
}

/// 带 Markdown 高亮的 TextEditingController。
///
/// 关键在于**缓存**：Flutter 的 TextField 会在每次重建时调用
/// buildTextSpan，如果不缓存，长文每次按键都要重扫全文，会明显掉帧。
///
/// 颜色是可变字段（[applyTheme]），因为主题色要等 `didChangeDependencies`
/// 才能拿到。换色时清缓存重扫，但不替换控制器实例 —— 替换会丢焦点和选区。
class MarkdownEditingController extends TextEditingController {
  MarkdownEditingController({super.text});

  Color _accent = const Color(0xFF2E6B4F);
  Color _dim = const Color(0xFF9E9E9E);
  Color _codeBg = const Color(0xFFF0F0F0);

  Color get accent => _accent;
  Color get dim => _dim;
  Color get codeBg => _codeBg;

  List<MdHighlight>? _cache;
  String? _cacheFor;

  /// 超过这个长度就不实时高亮 —— 对应规范里「大文件关闭实时高亮」
  static const maxHighlightLength = 200 * 1024;

  /// 主题就绪或切换时调用。颜色变了才清缓存。
  void applyTheme({
    required Color accent,
    required Color dim,
    required Color codeBg,
  }) {
    if (_accent == accent && _dim == dim && _codeBg == codeBg) return;
    _accent = accent;
    _dim = dim;
    _codeBg = codeBg;
    _cache = null;
    _cacheFor = null;
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final baseStyle = style ?? const TextStyle();
    final t = text;

    if (t.length > maxHighlightLength) {
      return TextSpan(text: t, style: baseStyle);
    }

    // 文本没变就复用上次结果
    if (_cacheFor != t || _cache == null) {
      _cache = MarkdownHighlighter.scan(
        t,
        base: baseStyle.color ?? Colors.black,
        accent: _accent,
        dim: _dim,
        codeBg: _codeBg,
        baseStyle: baseStyle,
      );
      _cacheFor = t;
    }

    return MarkdownHighlighter.build(
      text: t,
      spans: _cache ?? const [],
      base: baseStyle,
    );
  }
}
