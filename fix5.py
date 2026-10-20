p = 'lib/core/ai/ai_controller.dart'
s = open(p, encoding='utf-8').read()

old = """  ChatEntry _stripBackup(ChatEntry e) => ChatEntry(
        role: e.role,
        text: e.text,
        at: e.at,
        toolCalls: e.toolCalls,
        isError: e.isError,
        promptTokens: e.promptTokens,
        completionTokens: e.completionTokens,
      );
  ChatEntry _attachBackups(ChatSession s, List<WriteBackup> backups) {
    if (s.entries.isEmpty) return s;
    final last = s.entries.last;
    final merged = ChatEntry(
      role: last.role,
      text: last.text,
      at: last.at,
      toolCalls: last.toolCalls,
      isError: last.isError,
      backup: backups.first,
      promptTokens: last.promptTokens,
      completionTokens: last.completionTokens,
    );
    final list = [...s.entries]..[s.entries.length - 1] = merged;
    return s.copyWith(entries: list);
  }
  List<WriteBackup> _backupsOf(ChatEntry e) {
final b = e.backup;
    return b == null ? const [] : [b];
  }"""

new = """  /// 复制一条 entry 并清空 backups（用它表示「已撤销」）
  ChatEntry _stripBackup(ChatEntry e) => ChatEntry(
        role: e.role,
        text: e.text,
        at: e.at,
        toolCalls: e.toolCalls,
        isError: e.isError,
        promptTokens: e.promptTokens,
        completionTokens: e.completionTokens,
      );

  /// 把本轮产生的备份挂到最后一条 entry 上，供 UI 显示「撤销」。
  ///
  /// 会**追加**而不是覆盖：一次回答里模型可能写好几次文件，
  /// 覆盖会让之前那几次写入变得无法回滚。
  ChatSession _attachBackups(ChatSession s, List<WriteBackup> backups) {
    if (s.entries.isEmpty) return s;
    final last = s.entries.last;
    final merged = ChatEntry(
      role: last.role,
      text: last.text,
      at: last.at,
      toolCalls: last.toolCalls,
      isError: last.isError,
      backups: [...last.backups, ...backups],
      promptTokens: last.promptTokens,
      completionTokens: last.completionTokens,
    );
    final list = [...s.entries]..[s.entries.length - 1] = merged;
    return s.copyWith(entries: list);
  }"""

assert old in s
s = s.replace(old, new)

# 回滚：直接用 entry.backups
s = s.replace(
    """    final backups = _backupsOf(entry);
    if (backups.isEmpty) return false;""",
    """    final backups = entry.backups;
    if (backups.isEmpty) return false;""",
)

open(p, 'w', encoding='utf-8').write(s)
print('ok')