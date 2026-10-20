import '../../core/site/github_api.dart';
import '../../core/site/token_store.dart';

/// 自动推断出的账号资料。
///
/// 单独定义而不直接用 GitHubProfile，是因为这里允许查询失败
/// （无令牌、403、超时都可能），失败时整体就是 null。
class AuthorSuggestion {
  const AuthorSuggestion({required this.name, this.email});

  final String name;
  final String? email;

  /// 名称和邮箱都有，才算一条**可用**的建议。
  ///
  /// 只有名称不算可用：没有邮箱的提交不会被 GitHub 关联到账号，
  /// 用户会看到「提交者是陌生名字、贡献格子不亮」。
  bool get isComplete =>
      name.trim().isNotEmpty && (email ?? '').trim().isNotEmpty;
}

/// 查询令牌对应的账号资料，**任何失败都返回 null**。
///
/// 抽成顶层函数供两处复用：
/// 1. 设置页「提交作者」弹窗的占位提示
/// 2. 首次登录时判断能否自动填好提交身份
///
/// 两处需求不同但数据来源一致 —— 复制两份实现会导致其中一处改了
/// 另一处忘记改（比如超时时间）。
///
/// [token] 传了就优先用它；不传则读本地已保存的令牌。
Future<AuthorSuggestion?> fetchAuthorSuggestion({String? token}) async {
  try {
    final t = token ?? await (await TokenStore.open()).read();
    if (t == null || t.trim().isEmpty) return null;

    final api = GitHubApi();
    try {
      final p = await api.fetchProfile(t);
      return AuthorSuggestion(
        name: p.commitName,
        email: p.email.isEmpty ? null : p.email,
      );
    } finally {
      api.dispose();
    }
  } catch (_) {
    // 无令牌 / 403 / 超时 / 网络失败 —— 一律当作「没拿到」
    return null;
  }
}