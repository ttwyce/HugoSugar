/// 自动推断出的账号资料，仅用于输入框的占位提示。
///
/// 单独定义而不直接用 GitHubProfile，是因为这里允许查询失败
/// （无令牌、403、超时都可能），失败时整体就是 null。
class AuthorSuggestion {
  const AuthorSuggestion({required this.name, this.email});

  final String name;
  final String? email;
}