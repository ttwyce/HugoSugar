p = 'lib/features/settings/settings_page.dart'
s = open(p, encoding='utf-8').read()

old = """  /// 查询账号资料，仅用于对话框里的占位提示。
  ///
  /// 任何失败（无令牌、403、超时）都返回 null，让占位提示保持通用文案。
  /// 这个值永远不该影响用户能否填写和保存。
  Future<AuthorSuggestion?> _fetchAuthorSuggestions() async {
    try {
      final store = await TokenStore.open();
      final token = await store.read();
      if (token == null || token.isEmpty) return null;
      final api = GitHubApi();
      try {
        final p = await api.fetchProfile(token);
        return AuthorSuggestion(
          name: p.commitName,
          email: p.email.isEmpty ? null : p.email,
        );
      } finally {
        api.dispose();
}
    } catch (_) {
      return null;
    }
  }"""

new = """  /// 查询账号资料，仅用于对话框里的占位提示。
  ///
  /// 实现已抽到 author_suggestion.dart，和「首次登录自动填作者」共用，
  /// 避免两处各写一份、超时配置改了一处忘了另一处。
  Future<AuthorSuggestion?> _fetchAuthorSuggestions() =>
      fetchAuthorSuggestion();"""

assert old in s, '没找到 _fetchAuthorSuggestions 原实现'
s = s.replace(old, new)
open(p, 'w', encoding='utf-8').write(s)
print('ok')