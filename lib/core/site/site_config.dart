/// 站点配置（当前只有一个站点，字段已经按多站点预留）
class SiteConfig {
  const SiteConfig({
    required this.id,
    required this.displayName,
    required this.repoUrl,
    required this.branch,
    required this.postsDir,
    this.lastSyncedAt,
    this.deployHookUrl,
  });

  /// 内部标识，也是本地目录名
  final String id;

  /// 展示名
  final String displayName;

  /// 完整 clone 地址，形如 https://github.com/user/repo.git
  final String repoUrl;

  /// 主分支
  final String branch;

  /// 文章目录（相对仓库根）
  final String postsDir;

  /// 上次同步时间
  final DateTime? lastSyncedAt;

  /// Vercel / Netlify 等平台的 Deploy Hook 地址。
  /// 为空表示不触发。放在站点配置里而不是全局设置，因为不同站点
  /// 对应不同项目的 hook。
  final String? deployHookUrl;

  /// 从 URL 推导 `owner/repo`，用于展示
  String get repoSlug {
    var s = repoUrl.trim();
    if (s.endsWith('.git')) s = s.substring(0, s.length - 4);
    s = s.replaceFirst('https://', '').replaceFirst('http://', '');
    s = s.replaceFirst('github.com/', '');
    return s;
  }

  SiteConfig copyWith({
    String? displayName,
    String? repoUrl,
    String? branch,
    String? postsDir,
    DateTime? lastSyncedAt,
    String? deployHookUrl,
  }) {
    return SiteConfig(
      id: id,
      displayName: displayName ?? this.displayName,
      repoUrl: repoUrl ?? this.repoUrl,
      branch: branch ?? this.branch,
      postsDir: postsDir ?? this.postsDir,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      deployHookUrl: deployHookUrl ?? this.deployHookUrl,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'displayName': displayName,
        'repoUrl': repoUrl,
        'branch': branch,
        'postsDir': postsDir,
        'lastSyncedAt': lastSyncedAt?.toIso8601String(),
        'deployHookUrl': deployHookUrl,
      };

  static SiteConfig fromJson(Map<String, Object?> json) {
    return SiteConfig(
      id: json['id'] as String? ?? 'default',
      displayName: json['displayName'] as String? ?? '我的站点',
      repoUrl: json['repoUrl'] as String? ?? '',
      branch: json['branch'] as String? ?? 'main',
      postsDir: json['postsDir'] as String? ?? 'content/posts',
      lastSyncedAt: json['lastSyncedAt'] == null
          ? null
          : DateTime.tryParse(json['lastSyncedAt'] as String),
      deployHookUrl: json['deployHookUrl'] as String?,
    );
  }
}
