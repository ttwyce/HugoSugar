import '../settings/app_settings.dart';

/// 新建文章时，按设置生成文件名主干（不含扩展名）。
///
/// 抽成独立函数而不是留在 SiteController 里，有两个原因：
/// 1. 这是纯粹字符串处理，可以脱离站点/原生库单独测试
///    （flutter test 跑在宿主机上，加载不了 libgit2）；
/// 2. 命名规则是用户可见的承诺，值得被单独锁定住。
String buildFileSlug({
  required String title,
  required FileNameStyle style,
  DateTime? now,
}) {
  final t = now ?? DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  final datePart = '${t.year}${two(t.month)}${two(t.day)}';
  final timePart = '${two(t.hour)}${two(t.minute)}${two(t.second)}';

  switch (style) {
    case FileNameStyle.timestamp:
      return 'post-$datePart-$timePart';

    case FileNameStyle.dateAndTitle:
      // 日期 + 标题：标题能 ASCII 化就用，否则只剩日期，
      // 避免出现 `20240501-.md` 这种残缺名。
      final s = asciiSlug(title);
      return s.isEmpty ? datePart : '$datePart-$s';

    case FileNameStyle.fromTitle:
      return titleSlug(title);
  }
}

/// 「跟随标题」：文件名就是标题。
///
/// **故意不做 ASCII 化。** 中文标题保留中文 —— 用户选这条规则，
/// 要的就是「文件名和标题一样」，能一眼在仓库里找到对应文章。
/// 早期版本把它回退成 `post-20260521-...` 时间戳，等于这个选项没生效。
///
/// 只处理真正会出问题的字符：
/// - 文件系统非法字符 `\ / : * ? " < > |` → 空格
/// - 连续空白压缩成一个
/// - 去掉首尾的点和空格（跨平台 + 别让 URL 太难读）
/// - 限长，避免超长标题撞文件系统上限
String titleSlug(String title, {int maxLength = 60}) {
  var s = title
      .trim()
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceAll(RegExp(r'^[.\s]+|[.\s]+$'), '');

  if (s.length > maxLength) {
    s = s.substring(0, maxLength).trim();
  }
  if (s.isEmpty) {
    // 标题全是非法字符（极端情况）—— 只能兜底，但用可读的失败标识
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return 'untitled-${now.year}${two(now.month)}${two(now.day)}'
        '-${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }
  return s;
}

/// 标题 → 纯 ASCII slug。失败返回空串（由调用方决定怎么兜底）。
String asciiSlug(String title) {
  return title
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^\w\s-]'), '')
      .replaceAll(RegExp(r'[\s_]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
}
