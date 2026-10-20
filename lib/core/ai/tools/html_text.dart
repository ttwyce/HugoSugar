/// 极简 HTML → 纯文本。
///
/// ## 为什么不用 package:html
///
/// 它的 DOM 解析在几百 KB 的页面上会占几十 MB 内存，而且我们只需要
/// 「去掉标签、保留段落结构」。手写一个流式扫描器足够，还能顺带
/// 处理「<script> 里恰好包含 `<`」这类用正则切会出错的情况。
///
/// 目标不是完美的 HTML 解析，而是**给模型一份读得懂的正文**。
String htmlToText(String html) {
  final buf = StringBuffer();

  // 1) 先切掉整块不需要的内容。
  //    必须整块切，不能只删标签 —— <script>xxx</script> 去掉标签后
  //    里面的 JS 代码会变成正文，那是纯污染。
  var s = html;
  for (final tag in const [
    'script',
    'style',
    'noscript',
    'svg',
    'iframe',
    'form',
    'nav',
    'footer',
    'aside',
  ]) {
    s = _stripBlock(s, tag);
  }

  // 2) 逐字符扫描
  var i = 0;
  while (i < s.length) {
    final ch = s[i];

    if (ch == '<') {
      final end = s.indexOf('>', i);
      if (end == -1) {
        // 没有闭合的 `<`：当作普通文本，避免吞掉后面全部内容
        buf.write(s.substring(i));
        break;
      }
      final tag = s.substring(i + 1, end).toLowerCase();

      // 注意顺序：li 必须先于通用的块级判断处理。
      // 早期把 li 放在 _isBlock 后面，导致 li 只加了换行、丢了 "- " 前缀，
      // 列表在模型眼里变成了平铺段落。
      if (tag.startsWith('li')) {
        _newline(buf);
        buf.write('- ');
      } else if (tag.startsWith('br')) {
        _newline(buf);
      } else if (_isBlock(tag)) {
        _newline(buf);
        // h1~h6 前加 #
        final h = RegExp(r'^h([1-6])').firstMatch(tag);
        if (h != null) {
          final level = int.parse(h.group(1)!);
          buf.write('${'#' * level} ');
        }
      } else if (tag.startsWith('/')) {
        // 关闭标签：块级也换行
        if (_isBlock(tag.substring(1))) _newline(buf);
      }

      i = end + 1;
      continue;
    }

    if (ch == '&') {
      final semi = s.indexOf(';', i);
      // 只处理短的实体，避免把一大段文本当成实体
      if (semi != -1 && semi - i <= 10) {
        final entity = s.substring(i, semi + 1);
        final decoded = _decodeEntity(entity);
        if (decoded != null) {
          buf.write(decoded);
          i = semi + 1;
          continue;
        }
      }
      buf.write(ch);
      i++;
      continue;
    }

    buf.write(ch);
    i++;
  }

  return _tidy(buf.toString());
}

bool _isBlock(String tag) {
  // 去掉 `/` 和属性部分再判断
  var t = tag.startsWith('/') ? tag.substring(1) : tag;
  final space = t.indexOf(RegExp(r'[\s/]'));
  if (space != -1) t = t.substring(0, space);
  const blocks = {
    'p', 'div', 'section', 'article', 'main', 'header',
    'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
    'ul', 'ol', 'li', 'blockquote', 'pre', 'table', 'tr',
    'figure', 'figcaption', 'br', 'hr',
  };
  return blocks.contains(t);
}

void _newline(StringBuffer buf) {
  if (buf.isEmpty) return;
  final s = buf.toString();
  if (s.endsWith('\n')) return;
  buf.write('\n');
}

/// 移除整个 `<tag>...</tag>` 块（含内容）
String _stripBlock(String src, String tag) {
  final lower = src.toLowerCase();
  var out = src;
  var from = 0;
  while (true) {
    final open = lower.indexOf('<$tag', from);
    if (open == -1) break;
    final close = lower.indexOf('</$tag>', open);
    if (close == -1) {
      // 没闭合：截到结尾（HTML 里常见，比如只开不闭的 script）
      out = out.substring(0, open);
      break;
    }
    final after = close + tag.length + 3;
    out = out.substring(0, open) + out.substring(after);
    // 注意：out 变了，lower 也要跟着变，否则后续下标错位。
    // 这里直接重来一次，页面大小在几百 KB 级别，代价可接受。
    return _stripBlock(out, tag);
  }
  return out;
}

String? _decodeEntity(String e) {
  const map = {
    '&amp;': '&',
    '&lt;': '<',
    '&gt;': '>',
    '&quot;': '"',
    '&apos;': "'",
    '&#39;': "'",
    '&nbsp;': ' ',
    '&mdash;': '—',
    '&ndash;': '–',
    '&hellip;': '…',
    '&ldquo;': '“',
    '&rdquo;': '”',
    '&lsquo;': '‘',
    '&rsquo;': '’',
  };
  final hit = map[e.toLowerCase()];
  if (hit != null) return hit;

  // 数字实体 &#123; / &#x1F600;
  final num = RegExp(r'^&#(x?)([0-9a-fA-F]+);$').firstMatch(e);
  if (num != null) {
    final isHex = num.group(1) == 'x';
    final code = int.tryParse(num.group(2)!, radix: isHex ? 16 : 10);
    if (code != null && code > 0 && code <= 0x10FFFF) {
      try {
        return String.fromCharCode(code);
      } catch (_) {
        return null;
      }
    }
  }
  return null;
}

/// 压缩空白：连续空行折叠成一个，去掉行尾空格
String _tidy(String s) {
  final lines = s.split('\n').map((l) => l.replaceAll(RegExp(r'[ \t]+$'), ''));
  final out = <String>[];
  var blank = 0;
  for (final l in lines) {
    final trimmed = l.replaceAll(RegExp(r'^[ \t]+'), '');
    if (trimmed.isEmpty) {
      blank++;
      // 最多保留一个空行
      if (blank == 1 && out.isNotEmpty) out.add('');
    } else {
      blank = 0;
      out.add(trimmed);
    }
  }
  while (out.isNotEmpty && out.last.isEmpty) {
    out.removeLast();
  }
  return out.join('\n');
}

/// 从 HTML 里猜出标题（`<title>` 或第一个 h1）
String guessTitle(String html) {
  final t = RegExp(r'<title[^>]*>([\s\S]*?)</title>', caseSensitive: false)
      .firstMatch(html);
  if (t != null) {
    final s = _tidy(htmlToText(t.group(1)!));
    if (s.isNotEmpty) return s;
  }
  final h1 = RegExp(r'<h1[^>]*>([\s\S]*?)</h1>', caseSensitive: false)
      .firstMatch(html);
  if (h1 != null) {
    final s = _tidy(htmlToText(h1.group(1)!));
    if (s.isNotEmpty) return s;
  }
  return '';
}