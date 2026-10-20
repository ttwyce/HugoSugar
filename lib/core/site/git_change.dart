/// 单个文件在工作区/暂存区的变更类型。
///
/// libgit2 的 [GitStatus] 是按位组合的，同一个文件可能同时
/// `wtModified | indexModified`。这里的 [GitChangeKind] 是做给 UI 看的
/// 单一结论 —— 用户不需要知道「工作区和暂存区都有改动」这种细节。
enum GitChangeKind {
  /// 新文件（工作区或暂存区都算）
  added('新增', '+'),

  /// 内容被修改
  modified('修改', 'M'),

  /// 文件被删除
  deleted('删除', '-'),

  /// 重命名
  renamed('重命名', 'R'),

  /// 有未解决的合并冲突
  conflicted('冲突', '!');

  const GitChangeKind(this.label, this.badge);

  final String label;

  /// 列表左侧的单字符标记，类似 `git status --short`
  final String badge;
}

/// 一个文件的变更记录
class GitChange {
  const GitChange({
    required this.path,
    required this.kind,
    required this.staged,
  });

  /// 相对仓库根的路径
  final String path;

  final GitChangeKind kind;

  /// 是否已经在暂存区（index 里）。false 表示只在工作区。
  final bool staged;

  bool get isConflict => kind == GitChangeKind.conflicted;
}
