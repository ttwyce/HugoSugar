import 'front_matter.dart';

/// 文章搜索的匹配与摘要截取。
///
/// 抽成纯函数而不是留在 `_PostsPageState` 里，是为了能脱离 Widget 测试：
/// 列表页要搭一整个 [SiteController] 才能 pump，而匹配规则本身
/// （大小写、覆盖哪些字段、截多长）是最容易写错、也最值得回归保护的部分。
class PostSearch {
  const PostSearch(this.query);

  /// 已 trim + 小写归一化的搜索词
  final String query;

  bool get isEmpty => query.isEmpty;

  /// 是否命中。
  ///
  /// 覆盖范围按「用户会记得的线索」排序：标题 → 路径 → 简介 → 正文 →
  /// 分类 → 标签。正文也算命中，因为「我记得那篇里提过 xxx」比
  /// 「我记得标题」常见得多。
  ///
  /// 大小写不敏感：英文标签 `Flutter` 和 `flutter` 在 Hugo 里是两个
  /// taxonomy，但用户搜索时不该被这种区分绊住。
  bool matches(PostDocument p) {
    if (query.isEmpty) return true;
    if (p.title.toLowerCase().contains(query)) return true;
    if (p.relativePath.toLowerCase().contains(query)) return true;
    if (p.description.toLowerCase().contains(query)) return true;
    if (p.body.toLowerCase().contains(query)) return true;
    for (final c in p.categories) {
      if (c.toLowerCase().contains(query)) return true;
    }
    for (final t in p.tags) {
      if (t.toLowerCase().contains(query)) return true;
    }
    return false;
  }

  /// 命中正文时截一段上下文，未命中正文返回 null。
  ///
  /// 纯正文命中时列表上看不出任何高亮，用户会疑惑「这篇为什么被搜出来」，
  /// 所以给一行片段。空白（含换行）压缩成单空格：Markdown 正文换行密集，
  /// 原样截取会得到一堆空行。
  ///
  /// [before] / [after] 是按字符数算的近似窗口，不追求对齐到词边界——
  /// 中文没有空格，对齐反而会切出更怪的片段。
  String? snippet(PostDocument p, {int before = 16, int after = 48}) {
    if (query.isEmpty) return null;
    final body = p.body.replaceAll(RegExp(r'\s+'), ' ');
    final i = body.toLowerCase().indexOf(query);
    if (i < 0) return null;

    final start = i - before < 0 ? 0 : i - before;
    var end = i + query.length + after;
    if (end > body.length) end = body.length;

    final head = start > 0 ? '…' : '';
    final tail = end < body.length ? '…' : '';
    return '$head${body.substring(start, end)}$tail';
  }
}
