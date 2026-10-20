import 'package:yaml/yaml.dart';

/// 一篇文章的元信息 + 正文。
///
/// Hugo 的 Front Matter 有三种写法，都出现在真实站点里：
/// ```yaml
/// ---
/// title: 标题
/// ---
/// ```
/// ```toml
/// +++
/// title = "标题"
/// +++
/// ```
/// 以及 JSON（少见）。这里覆盖 YAML 和 TOML 两种主流格式。
class PostDocument {
  const PostDocument({
    required this.relativePath,
    required this.fileName,
    required this.title,
    required this.frontMatter,
    required this.body,
    required this.rawFrontMatter,
    required this.format,
    this.date,
    this.draft = false,
    this.categories = const [],
    this.tags = const [],
    this.description = '',
    this.slug,
    this.weight,
  });

  /// 相对站点根目录的路径，如 content/posts/hello.md
  final String relativePath;

  /// 含扩展名的文件名
  final String fileName;

  /// 展示用标题。Front Matter 没写 title 时回退到文件名。
  final String title;

  /// 解析出的 Front Matter 键值
  final Map<String, Object?> frontMatter;

  /// 正文（不含 Front Matter）
  final String body;

  /// 原始 Front Matter 文本（不含分隔符），便于原样写回
  final String rawFrontMatter;

  /// 'yaml' / 'toml' / 'none'
  final String format;

  final DateTime? date;
  final bool draft;
  final List<String> categories;
  final List<String> tags;
  final String description;
  final String? slug;
  final int? weight;

  /// 文章状态文案
  String get statusLabel => draft ? '草稿' : '已发布';

  /// 目录层级：content/posts/tech/a.md → tech
  /// 用于在没写 categories 时兜底展示
  String? get folderName {
    final parts = relativePath.split('/');
    return parts.length > 1 ? parts[parts.length - 2] : null;
  }

  /// 从正文里取一小段纯文本作为摘要
  String get excerpt {
    if (description.isNotEmpty) return description;
    // 去掉常见 Markdown 标记，取前若干字符
    var s = body
        .replaceAll(RegExp(r'```[\s\S]*?```'), ' ') // 代码块
        .replaceAll(RegExp(r'<!--[\s\S]*?-->'), ' ') // 注释
        .replaceAll(RegExp(r'^\s{0,3}#{1,6}\s*', multiLine: true), ' ') // 标题
        .replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), ' ') // 图片
        // 链接只保留文字。注意：Dart 的 replaceAll 不支持 $1 反向引用，
        // 必须用 replaceAllMapped 手动取 group(1)。
        .replaceAllMapped(
          RegExp(r'\[([^\]]*)\]\([^)]*\)'),
          (m) => m.group(1) ?? '',
        )
        .replaceAll(RegExp(r'^\s*[-*+]\s+', multiLine: true), ' ') // 列表符号
        .replaceAll(RegExp(r'^\s*>\s?', multiLine: true), ' ') // 引用
        .replaceAll(RegExp(r'[*_~`]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (s.length <= 80) return s;
    return '${s.substring(0, 80)}…';
  }

  /// 日期展示：2024-05-01
  String get dateLabel {
    final d = date;
    if (d == null) return '';
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }
}

/// Front Matter 解析器。
///
/// 设计原则：**解析失败不能丢文章**。任何异常都退化成「没 Front Matter」，
/// 标题回退文件名，正文保留全文。宁可显示得朴素，也不能让列表变空。
class FrontMatter {
  FrontMatter._();

  /// 从文件名得到兜底标题
  ///
  /// `my-first-post.md` → `my first post`
  /// `2024-05-01-hello.md` → `hello`（去掉日期前缀，Hugo 常见命名）
  static String titleFromFileName(String fileName) {
    var s = fileName;
    final dot = s.lastIndexOf('.');
    if (dot > 0) s = s.substring(0, dot);

    // 去掉常见的日期前缀 2024-05-01- / 20240501-
    s = s.replaceFirst(RegExp(r'^\d{4}-\d{2}-\d{2}[-_]?'), '');
    s = s.replaceFirst(RegExp(r'^\d{8}[-_]?'), '');

    // 连字符/下划线转空格
    s = s.replaceAll(RegExp(r'[-_]+'), ' ').trim();
    if (s.isEmpty) return fileName;
    // 首字母大写（只处理 ASCII）
    return s[0].toUpperCase() + s.substring(1);
  }

  /// 解析一篇 Markdown 全文
  static PostDocument parse({
    required String relativePath,
    required String fileName,
    required String content,
  }) {
    final fallbackTitle = titleFromFileName(fileName);

    try {
      final stripped = content.startsWith('\uFEFF')
          ? content.substring(1)
          : content; // 去 BOM

      // ── YAML：--- 开头，--- 或 ... 结尾 ──
      if (stripped.startsWith('---')) {
        final end = _findYamlEnd(stripped);
        if (end != null) {
          final rawFm = stripped.substring(3, end.start).trim();
          final body = stripped.substring(end.end);
          final map = _parseYaml(rawFm);
          return _build(
            relativePath: relativePath,
            fileName: fileName,
            fallbackTitle: fallbackTitle,
            fm: map,
            rawFm: rawFm,
            body: body,
            format: 'yaml',
          );
        }
      }

      // ── TOML：+++ 开头，+++ 结尾 ──
      if (stripped.startsWith('+++')) {
        final end = stripped.indexOf('\n+++', 3);
        if (end != -1) {
          final rawFm = stripped.substring(3, end).trim();
          final body = stripped.substring(end + 4);
          final map = _parseToml(rawFm);
          return _build(
            relativePath: relativePath,
            fileName: fileName,
            fallbackTitle: fallbackTitle,
            fm: map,
            rawFm: rawFm,
            body: body,
            format: 'toml',
          );
        }
      }

      // 没有 Front Matter，整篇都是正文
      return PostDocument(
        relativePath: relativePath,
        fileName: fileName,
        title: fallbackTitle,
        frontMatter: const {},
        body: content,
        rawFrontMatter: '',
        format: 'none',
      );
    } catch (_) {
      // 解析炸了也不丢文章
      return PostDocument(
        relativePath: relativePath,
        fileName: fileName,
        title: fallbackTitle,
        frontMatter: const {},
        body: content,
        rawFrontMatter: '',
        format: 'none',
      );
    }
  }

  /// 找 YAML Front Matter 的结束位置。
  ///
  /// 起始的 `---` 之后，结束标记可能写成 `---` 或 `...`。
  /// 必须单独成行 —— 正文里的水平分割线也会是 `---`，
  /// 但那些出现在结束标记之后，不会被误判。
  static ({int start, int end})? _findYamlEnd(String s) {
    // 从第 3 个字符后开始找
    final re = RegExp(r'(^|\n)(---|\.\.\.)[ \t]*(\r?\n|$)');
    final m = re.firstMatch(s.substring(3));
    if (m == null) return null;
    final start = 3 + m.start;
    return (start: start, end: 3 + m.end);
  }

  static Map<String, Object?> _parseYaml(String raw) {
    if (raw.isEmpty) return const {};
    try {
      final doc = loadYaml(raw);
      if (doc is YamlMap) {
        return _normalize(doc);
      }
      return const {};
    } catch (_) {
      // YAML 写坏了：退化成逐行 key: value，能救多少算多少
      return _lenientKeyValue(raw, ':');
    }
  }

  static Map<String, Object?> _normalize(Map<dynamic, dynamic> m) {
    final out = <String, Object?>{};
    m.forEach((k, v) {
      if (k == null) return;
      out['$k'] = _toPlain(v);
    });
    return out;
  }

  static Object? _toPlain(Object? v) {
    if (v is YamlList) return v.map(_toPlain).toList();
    if (v is YamlMap) {
      final m = <String, Object?>{};
      v.forEach((k, val) => m['$k'] = _toPlain(val));
      return m;
    }
    return v;
  }

  /// TOML 只处理 Front Matter 常用的那几种形态：
  /// - `key = "str"`
  /// - `key = 123`
  /// - `key = true`
  /// - `key = ["a", "b"]`
  static Map<String, Object?> _parseToml(String raw) {
    final out = <String, Object?>{};
    for (final line in raw.split('\n')) {
      final t = line.trim();
      if (t.isEmpty || t.startsWith('#')) continue;
      final eq = t.indexOf('=');
      if (eq <= 0) continue;
      final key = t.substring(0, eq).trim();
      final value = t.substring(eq + 1).trim();
      if (key.isEmpty) continue;
      out[key] = _tomlValue(value);
    }
    return out;
  }

  static Object? _tomlValue(String v) {
    // 数组
    if (v.startsWith('[') && v.endsWith(']')) {
      final inner = v.substring(1, v.length - 1).trim();
      if (inner.isEmpty) return const <String>[];
      return inner
          .split(',')
          .map((e) => _tomlValue(e.trim()))
          .where((e) => e != null)
          .toList();
    }
    // 字符串
    if ((v.startsWith('"') && v.endsWith('"')) ||
        (v.startsWith("'") && v.endsWith("'"))) {
      return v.substring(1, v.length - 1);
    }
    if (v == 'true') return true;
    if (v == 'false') return false;
    final n = int.tryParse(v);
    if (n != null) return n;
    final d = double.tryParse(v);
    if (d != null) return d;
    return v;
  }

  /// 宽松解析：YAML 语法错误时逐行提取 `key: value`
  static Map<String, Object?> _lenientKeyValue(String raw, String sep) {
    final out = <String, Object?>{};
    for (final line in raw.split('\n')) {
      if (line.trim().isEmpty) continue;
      // 跳过缩进行（属于上一层的嵌套结构）
      if (line.startsWith(' ') || line.startsWith('\t')) continue;
      final i = line.indexOf(sep);
      if (i <= 0) continue;
      final key = line.substring(0, i).trim();
      var value = line.substring(i + sep.length).trim();
      // 去掉包裹引号
      if (value.length >= 2 &&
          ((value.startsWith('"') && value.endsWith('"')) ||
              (value.startsWith("'") && value.endsWith("'")))) {
        value = value.substring(1, value.length - 1);
      }
      if (key.isNotEmpty && value.isNotEmpty) out[key] = value;
    }
    return out;
  }

  static PostDocument _build({
    required String relativePath,
    required String fileName,
    required String fallbackTitle,
    required Map<String, Object?> fm,
    required String rawFm,
    required String body,
    required String format,
  }) {
    final titleRaw = fm['title'];
    final title = (titleRaw is String && titleRaw.trim().isNotEmpty)
        ? titleRaw.trim()
        : fallbackTitle;

    return PostDocument(
      relativePath: relativePath,
      fileName: fileName,
      title: title,
      frontMatter: fm,
      body: _trimLeadingNewlines(body),
      rawFrontMatter: rawFm,
      format: format,
      date: _parseDate(fm['date'] ?? fm['publishDate'] ?? fm['pubDate']),
      draft: _parseDraft(fm['draft']),
      categories: _parseStringList(fm['categories'] ?? fm['category']),
      tags: _parseStringList(fm['tags'] ?? fm['tag']),
      description: _parseString(fm['description'] ?? fm['summary']),
      slug: _parseString(fm['slug']),
      weight: fm['weight'] is int ? fm['weight'] as int : null,
    );
  }

  static String _trimLeadingNewlines(String s) {
    var i = 0;
    while (i < s.length && (s[i] == '\n' || s[i] == '\r')) {
      i++;
    }
    return s.substring(i);
  }

  static String _parseString(Object? v) {
    if (v == null) return '';
    if (v is String) return v.trim();
    return '$v';
  }

  static bool _parseDraft(Object? v) {
    if (v is bool) return v;
    if (v is String) {
      final s = v.toLowerCase().trim();
      return s == 'true' || s == 'yes' || s == '1';
    }
    return false;
  }

  static List<String> _parseStringList(Object? v) {
    if (v == null) return const [];
    if (v is String) {
      final s = v.trim();
      if (s.isEmpty) return const [];
      // 有些站点写成 "a, b" 或 "a b"
      final parts = s.contains(',') ? s.split(',') : [s];
      return parts.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    }
    if (v is List) {
      return v
          .map((e) => _parseString(e))
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return const [];
  }

  static DateTime? _parseDate(Object? v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    final s = '$v'.trim();
    if (s.isEmpty) return null;
    // 处理 2024-05-01T10:20:30+08:00 / 2024-05-01 10:20:30 / 2024-05-01
    final direct = DateTime.tryParse(s);
    if (direct != null) return direct;

    // 补一个常见的「空格分隔 date time」情况
    final withT = s.replaceFirst(' ', 'T');
    final p = DateTime.tryParse(withT);
    if (p != null) return p;

    // 纯日期 + 时间但不带时区的 "2024-05-01 10:20"
    final m = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{2}):(\d{2})(?::(\d{2}))?)?',
    ).firstMatch(s);
    if (m != null) {
      return DateTime(
        int.parse(m.group(1)!),
        int.parse(m.group(2)!),
        int.parse(m.group(3)!),
        int.tryParse(m.group(4) ?? '0') ?? 0,
        int.tryParse(m.group(5) ?? '0') ?? 0,
        int.tryParse(m.group(6) ?? '0') ?? 0,
      );
    }
    return null;
  }
}