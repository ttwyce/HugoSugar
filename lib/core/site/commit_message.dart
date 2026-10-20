/// 生成默认的 commit message。
///
/// 格式：`更新文章：标题1、标题2` 或 `更新 3 个文件`。
/// 比 `update` 这种无意义 message 好 —— 以后在 GitHub 网页上翻历史时
/// 能一眼看出这次改了什么。
class CommitMessage {
  CommitMessage._();

  static String suggest(List<String> changedPaths) {
    if (changedPaths.isEmpty) return '更新站点内容';

    // 优先从 md 文件名推标题
    final titles = <String>[];
    for (final path in changedPaths) {
      final name = path.split('/').last;
      if (!name.endsWith('.md')) continue;
      var t = name.substring(0, name.length - 3);
      // 去掉常见的日期前缀，如 20240501-hello
      t = t.replaceFirst(RegExp(r'^\d{8}-'), '');
      if (t.isNotEmpty) titles.add(t);
    }

    if (titles.isEmpty) {
      final n = changedPaths.length;
      return n == 1 ? '更新 ${changedPaths.first}' : '更新 $n 个文件';
    }
    if (titles.length == 1) return '更新文章：${titles.first}';
    if (titles.length <= 3) {
      return '更新文章：${titles.join('、')}';
    }
    return '更新文章：${titles.take(2).join('、')} 等 ${titles.length} 篇';
  }
}