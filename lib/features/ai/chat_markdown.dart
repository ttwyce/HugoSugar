import 'package:flutter/material.dart';
import 'package:hugosugar/app/i18n/l10n_scope.dart';
import 'package:markdown/markdown.dart' as md;

import '../../app/theme/app_colors.dart';

/// AI 回复的 Markdown 渲染。
///
/// ## 为什么不复用 `MarkdownHighlighter`
///
/// `lib/features/editor/markdown_highlighter.dart` 是给**编辑器**用的：
/// 它保留 `#`、`**`、反引号这些标记，只给源码着色，让作者看清结构。
/// AI 回复要的是**渲染结果**：`#` 应该变成大标题、`**粗**` 应该变粗、
/// 反引号应该消失。两者目的相反，不能共用。
///
/// ## 为什么选 `markdown` 包
///
/// 纯 Dart 实现，不带原生插件，不会在 ARM64 proot 里引入构建风险
/// （对比 `flutter_markdown` 会拖进一堆渲染层依赖）。这里只取它的
/// **AST**（`Element` / `Text` 树），自己画成 Flutter Widget，
/// 所以主题色、字号、暗色模式全部可控。
///
/// ## 增量渲染
///
/// 流式输出时每来一个分片都会重建这个 widget。`markdown` 的解析
/// 是纯函数、开销很小（几 KB 文本），不需要额外缓存；真要优化也是
/// 在 [ChatPage] 层按「是否仍在流式」决定，而不是在这里藏状态。
class ChatMarkdown extends StatelessWidget {
  const ChatMarkdown(this.markup, {super.key, this.baseFontSize = 14});

  final String markup;

  /// 正文字号。默认 14 是 AI 对话用的；编辑器预览可传入读者字号，
  /// 让预览所见即读者所得。
  final double baseFontSize;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;

    final text = markup.trim();
    if (text.isEmpty) {
      return Text('…', style: TextStyle(fontSize: baseFontSize, color: c.textTertiary));
    }

    // 只解析不渲染 HTML：encodeHtml 反而会把 < > 变成实体，
    // 模型输出里偶尔出现的泛型 `<T>` 会被显示成 `&lt;T&gt;`。
    final doc = md.Document(
      extensionSet: md.ExtensionSet.gitHubFlavored,
      encodeHtml: false,
    );

    final nodes = doc.parse(text);
    final blocks = _MdRenderer(
      context: context,
      colors: c,
      baseFontSize: baseFontSize,
    ).renderBlocks(nodes);

    if (blocks.isEmpty) {
      return Text(text, style: TextStyle(fontSize: baseFontSize, color: c.textPrimary));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: blocks,
    );
  }
}

/// 把 AST 画成 Widget。
///
/// 块级元素（段落 / 标题 / 列表 / 引用 / 代码块）用独立 Widget，
/// 行内元素（粗体 / 斜体 / 链接 / 行内代码）合并成一段 [TextSpan]。
///
/// 这样做的原因：块与块之间需要真实间距和外框（比如代码块的背景），
/// 而行内元素如果各自成 Widget 就无法正确换行。
class _MdRenderer {
  _MdRenderer({required this.context, required this.colors, this.baseFontSize = 14});

  final BuildContext context;
  final AppColors colors;
  final double baseFontSize;

  double get _baseFontSize => baseFontSize;
  static const double _baseline = 1.7;

  TextStyle get _base => TextStyle(
    fontSize: _baseFontSize,
    height: _baseline,
    color: colors.textPrimary,
  );

  TextStyle get _mono => _base.copyWith(
    fontFamily: 'monospace',
    fontFamilyFallback: const ['Menlo', 'Courier', 'Courier New'],
    fontSize: 13,
    height: 1.5,
  );

  // ── 块级 ────────────────────────────────────────────

  List<Widget> renderBlocks(List<md.Node> nodes) {
    final out = <Widget>[];
    for (final n in nodes) {
      final w = renderBlock(n);
      if (w != null) {
        out.add(w);
        // 块后统一留一点间距；标题自己已经有上下边距就不再重复
        if (!_isHeading(n)) {
          out.add(const SizedBox(height: 8));
        }
      }
    }
    // 去掉末尾多余的间距
    if (out.isNotEmpty && out.last is SizedBox) {
      out.removeLast();
    }
    return out;
  }

  bool _isHeading(md.Node n) =>
      n is md.Element && RegExp(r'^h[1-6]$').hasMatch(n.tag);

  Widget? renderBlock(md.Node node) {
    if (node is md.Text) {
      final t = node.text.trim();
      if (t.isEmpty) return null;
      return Text(t, style: _base);
    }

    if (node is! md.Element) return null;

    switch (node.tag) {
      case 'p':
        return _richText(node.children ?? const []);

      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        final level = int.parse(node.tag.substring(1));
        // 手机上正文只有 14，标题层级拉开太多会显得很挤：
        // 1 级给 1.42 倍，每级递减，最低不小于正文
        final scale = switch (level) {
          1 => 1.42,
          2 => 1.28,
          3 => 1.16,
          4 => 1.0,
          _ => 1.0,
        };
        return Padding(
          padding: EdgeInsets.only(top: level <= 2 ? 14 : 8, bottom: 6),
          child: _richText(
            node.children ?? const [],
            base: _base.copyWith(
              fontSize: _baseFontSize * scale,
              height: 1.4,
              fontWeight: level <= 3 ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        );

      case 'ul':
      case 'ol':
        return _list(node);

      case 'blockquote':
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 2, bottom: 2),
          padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
          decoration: BoxDecoration(
            color: colors.surfaceHigh,
            border: Border(
              left: BorderSide(
                color: colors.accent.withValues(alpha: 0.5),
                width: 3,
              ),
            ),
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(4),
              bottomRight: Radius.circular(4),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: renderBlocks(node.children ?? const []),
          ),
        );

      case 'pre':
        return _codeBlock(node);

      case 'hr':
        return Container(
          height: 1,
          margin: const EdgeInsets.symmetric(vertical: 8),
          color: colors.divider,
        );

      case 'table':
        // 表格暂不渲染成网格：手机上横向滚动体验差，
        // 这里退化成纯文本，保证内容不丢。
        return Text(
          node.textContent.trim(),
          style: _base.copyWith(color: colors.textSecondary),
        );

      default:
        // 未知块级元素：展开子节点，内容不丢
        final kids = renderBlocks(node.children ?? const []);
        if (kids.isEmpty) {
          final t = node.textContent.trim();
          return t.isEmpty ? null : Text(t, style: _base);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: kids,
        );
    }
  }

  Widget _list(md.Element el) {
    final ordered = el.tag == 'ol';
    final rows = <Widget>[];
    var index = 0;

    for (final item in el.children ?? const <md.Node>[]) {
      if (item is! md.Element || item.tag != 'li') continue;
      index++;

      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                // 固定宽度做悬挂缩进，"1." 和 "10." 才不会错位
                width: ordered ? 22 : 14,
                child: Text(
                  ordered ? '$index.' : '•',
                  style: _base.copyWith(color: colors.accent),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: _liContent(item),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: rows,
    );
  }

  /// 列表项内容：可能是纯行内，也可能嵌套了段落/子列表
  List<Widget> _liContent(md.Element li) {
    final kids = li.children ?? const <md.Node>[];
    final hasBlock = kids.any(
      (k) =>
          k is md.Element &&
          const {'p', 'ul', 'ol', 'pre', 'blockquote'}.contains(k.tag),
    );

    if (!hasBlock) return [_richText(kids)];

    final out = <Widget>[];
    for (final k in kids) {
      if (k is md.Element && k.tag == 'p') {
        out.add(_richText(k.children ?? const []));
      } else {
        final w = renderBlock(k);
        if (w != null) out.add(w);
      }
    }
    return out;
  }

  Widget _codeBlock(md.Element pre) {
    md.Element? codeEl;
    for (final k in pre.children ?? const <md.Node>[]) {
      if (k is md.Element && k.tag == 'code') {
        codeEl = k;
        break;
      }
    }

    // 语言标记形如 class="language-dart"
    final cls = codeEl?.attributes['class'] ?? '';
    final lang = cls.startsWith('language-')
        ? cls.substring('language-'.length)
        : (cls.isEmpty ? null : cls);

    final content = (codeEl?.textContent ?? pre.textContent).replaceAll(
      RegExp(r'\n$'),
      '',
    );

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 4, bottom: 2),
      decoration: BoxDecoration(
        color: colors.surfaceHigh,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.divider, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (lang != null && lang.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
              child: Text(
                lang,
                style: TextStyle(
                  fontSize: 10,
                  color: colors.textTertiary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          // 代码不换行，横向滚动 —— 长行换行会把缩进结构打乱
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
              child: SelectableText(
                content.isEmpty ? ' ' : content,
                style: _mono.copyWith(color: colors.textPrimary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 行内 ────────────────────────────────────────────

  Widget _richText(List<md.Node> nodes, {TextStyle? base}) {
    final style = base ?? _base;
    final spans = buildSpans(nodes, style);
    if (spans.isEmpty) return const SizedBox.shrink();
    return SelectableText.rich(
      TextSpan(style: style, children: spans),
      // 明确置空：SelectableText.rich 默认会加下划线样式
      strutStyle: StrutStyle(
        fontSize: style.fontSize,
        height: style.height,
        fontWeight: style.fontWeight,
      ),
    );
  }

  /// 把行内节点编译成 TextSpan 列表。
  ///
  /// 递归处理，因为 `**粗体里还有 *斜体***` 是合法写法。
  List<TextSpan> buildSpans(List<md.Node> nodes, TextStyle base) {
    final out = <TextSpan>[];

    for (final n in nodes) {
      if (n is md.Text) {
        if (n.text.isNotEmpty) out.add(TextSpan(text: n.text));
        continue;
      }
      if (n is! md.Element) continue;

      final kids = n.children ?? const <md.Node>[];

      switch (n.tag) {
        case 'strong':
        case 'b':
          out.add(
            TextSpan(
              style: base.copyWith(fontWeight: FontWeight.w700),
              children: buildSpans(kids, base),
            ),
          );

        case 'em':
        case 'i':
          out.add(
            TextSpan(
              style: base.copyWith(fontStyle: FontStyle.italic),
              children: buildSpans(kids, base),
            ),
          );

        case 'del':
        case 's':
          out.add(
            TextSpan(
              style: base.copyWith(decoration: TextDecoration.lineThrough),
              children: buildSpans(kids, base),
            ),
          );

        case 'code':
          out.add(
            TextSpan(
              text: n.textContent,
              style: _mono.copyWith(
                backgroundColor: colors.surfaceHigh,
                color: colors.accent,
              ),
            ),
          );

        case 'a':
          out.add(
            TextSpan(
              style: base.copyWith(
                color: colors.accent,
                decoration: TextDecoration.underline,
                decorationColor: colors.accent.withValues(alpha: 0.5),
              ),
              children: buildSpans(kids, base),
            ),
          );

        case 'br':
          out.add(const TextSpan(text: '\n'));

        case 'img':
          // 不加载网络图片：AI 回复里的图多为外链，
          // 加载既慢又可能失联。保留 alt 文本。
          final alt = n.attributes['alt'] ?? '';
          out.add(
            TextSpan(
              text: alt.isEmpty ? T('[图片]') : TP('[图片: {}]', [alt]),
              style: base.copyWith(color: colors.textTertiary),
            ),
          );

        default:
          out.add(TextSpan(children: buildSpans(kids, base)));
      }
    }

    return out;
  }
}
