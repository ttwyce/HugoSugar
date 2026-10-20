import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// GitHub 上的一个仓库（只保留选仓库需要的字段）
class GitHubRepo {
  const GitHubRepo({
    required this.fullName,
    required this.name,
    required this.owner,
    required this.private,
    required this.defaultBranch,
    required this.cloneUrl,
    this.description = '',
    this.pushedAt,
    this.archived = false,
    this.isEmpty = false,
  });

  /// `owner/name`
  final String fullName;
  final String name;
  final String owner;
  final bool private;
  final String defaultBranch;
  final String cloneUrl;
  final String description;
  final DateTime? pushedAt;
  final bool archived;

  /// 空仓库（一个提交都没有）不能 clone，得先 init
  final bool isEmpty;

  static GitHubRepo fromJson(Map<String, dynamic> j) {
    final owner = (j['owner'] as Map<String, dynamic>?)?['login'] as String? ?? '';
    return GitHubRepo(
      fullName: j['full_name'] as String? ?? '',
      name: j['name'] as String? ?? '',
      owner: owner,
      private: j['private'] as bool? ?? false,
      defaultBranch: j['default_branch'] as String? ?? 'main',
      cloneUrl: j['clone_url'] as String? ?? '',
      description: j['description'] as String? ?? '',
      pushedAt: DateTime.tryParse(j['pushed_at'] as String? ?? ''),
      archived: j['archived'] as bool? ?? false,
      isEmpty: (j['size'] as num?)?.toInt() == 0,
    );
  }

  /// 本地展示用的相对时间，避免引入 intl 依赖
  String get pushedLabel {
    final t = pushedAt;
    if (t == null) return '';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return '刚刚';
    if (d.inHours < 1) return '${d.inMinutes} 分钟前';
    if (d.inDays < 1) return '${d.inHours} 小时前';
    if (d.inDays < 30) return '${d.inDays} 天前';
    if (d.inDays < 365) return '${d.inDays ~/ 30} 个月前';
    return '${d.inDays ~/ 365} 年前';
  }
}

/// GitHub API 调用失败的原因分类。
///
/// 分开建模的原因：clone 失败时 libgit2 只给一句「not found」，
/// 分不清是 token 错、仓库不存在、还是没权限。先用 REST API 探一次，
/// 才能给用户准确的提示。
enum GitHubErrorKind {
  /// 401：token 无效或已过期
  badToken,

  /// 403：权限不足 / 触发限流
  forbidden,

  /// 404：仓库不存在，或 token 看不到这个私有仓库
  notFound,

  /// 网络层失败（DNS / TLS / 超时）
  network,

  /// 其他
  unknown,
}

class GitHubException implements Exception {
  GitHubException(this.kind, this.message, {this.hint});

  final GitHubErrorKind kind;
  final String message;

  /// 给用户的可操作建议
  final String? hint;

  @override
  String toString() => message;
}

/// GitHub 账号资料，用于填写 git 提交作者。
///
/// 提交作者和「是谁推的」是两件事：push 用令牌鉴权（令牌属于谁，
/// 就是谁推的），但 commit 里的 author 字段是**字符串**，GitHub 靠
/// 其中的邮箱把提交关联到用户。所以这两个值必须取自真实账号，
/// 不能写死 —— 早先硬编码了一个应用名 + 拼出来的 noreply 邮箱，
/// 结果用户在 GitHub 上看到的提交作者是一个陌生名字，而不是自己。
class GitHubProfile {
  const GitHubProfile({
    required this.login,
    required this.displayName,
    required this.email,
  });

  /// 账号登录名，如 `octocat`
  final String login;

  /// 展示名（GitHub 的 Name 字段，没填就回落到 login）
  final String displayName;

  /// 主邮箱或 noreply 邮箱，用于 commit 的 author/committer.email
  final String email;

  /// 提交时该用的作者名。
  ///
  /// 用 login 而不是 displayName：GitHub 在提交列表里优先显示
  /// 与账号关联的名字，但用 login 更稳定 —— 用户改了显示名也不会
  /// 让历史提交看起来像另一个人的。
  String get commitName => login.isNotEmpty ? login : displayName;
}

/// GitHub REST API 封装。
///
/// 只做 M1 需要的三件事：验 token、列仓库、查单个仓库是否存在。
class GitHubApi {
  GitHubApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _base = 'https://api.github.com';

  /// 常规请求超时。列仓库这类用户明确在等的操作可以用满 20 秒。
  static const _timeout = Duration(seconds: 20);

  /// 「顺带查一下」类请求的超时。
  ///
  /// 用于 `/user` 这类只为补默认值的调用：结果缺失有兜底，不值得让
  /// 用户干等 20 秒。手机上 TLS 握手失败通常在前 5 秒内就能确定，
  /// 拖到 20 秒只会让「推送」和「登录」显得像卡死。
  static const _quickTimeout = Duration(seconds: 6);

  void dispose() => _client.close();

  Map<String, String> _headers(String token) => {
        'Authorization': 'Bearer ${token.trim()}',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      };

  /// 校验 token 并拿到登录名。
  ///
  /// 顺带检查 scopes —— 没有 `repo` 权限的话，私有仓库一律列出不来，
  /// 这是「明明有仓库却看不到」的最常见原因。
  Future<String> validateToken(String token) async {
    final profile = await fetchProfile(token);
    return profile.login;
  }

  /// 取当前令牌对应的账号资料，用于填写 git 提交作者。
  ///
  /// 为什么要单独取 profile 而不是只用 login：
  /// commit 的作者需要「名字 + 邮箱」两个值。名字用 login 就够，
  /// 但邮箱必须是账号的真实 noreply 邮箱，否则 GitHub 不会把这次
  /// 提交关联到用户主页（头像、贡献格子都不会出现）。
  ///
  /// `/user` 的 `email` 字段默认是 null（除非用户公开了邮箱），
  /// 所以还要问一次 `/user/emails`。
  Future<GitHubProfile> fetchProfile(String token) async {
    // 用短超时：这个调用的结果只用于「补默认作者名」，
    // 拿不到有兜底，不该让用户等满 20 秒。
    final res = await _request(
      () => _client.get(
        Uri.parse('$_base/user'),
        headers: _headers(token),
      ),
      timeout: _quickTimeout,
    );

    if (res.statusCode == 401) {
      throw GitHubException(
        GitHubErrorKind.badToken,
        '访问令牌无效或已过期',
        hint: '请到 GitHub → Settings → Developer settings → '
            'Personal access tokens 重新生成',
      );
    }
    final body = _decode(res);

    final scopes = res.headers['x-oauth-scopes'] ?? '';
    if (!_hasRepoScope(scopes)) {
      throw GitHubException(
        GitHubErrorKind.forbidden,
        '令牌缺少 repo 权限（当前：${scopes.isEmpty ? "无" : scopes}）',
        hint: '列不出私有仓库通常就是这个原因。'
            '请重新生成令牌并勾选 repo（或 fine-grained 的 Contents 读写权限）',
      );
    }

    final login = body['login'] as String? ?? '';
    final id = (body['id'] as num?)?.toInt();
    final displayName = body['name'] as String?;
    final publicEmail = body['email'] as String?;

    // 优先用公开邮箱；没有就问 /user/emails 找 noreply 或主邮箱。
    // 这两个接口都可能因为 fine-grained 令牌缺权限而失败，
    // 失败就用 GitHub 的 noreply 规则自己拼一个 —— 那个地址是
    // GitHub 官方推荐的、可直接用于 commit 的形式。
    var email = publicEmail;
    if (email == null || email.isEmpty) {
      email = await _fetchPrimaryEmail(token);
    }
    if ((email == null || email.isEmpty) && id != null && login.isNotEmpty) {
      email = '$id+$login@users.noreply.github.com';
    }

    return GitHubProfile(
      login: login,
      displayName: (displayName != null && displayName.trim().isNotEmpty)
          ? displayName.trim()
          : login,
      email: email ?? '',
    );
  }

  /// 从 `/user/emails` 取主邮箱；取不到返回 null。
  ///
  /// fine-grained 令牌可能没有 Email 权限，此时接口 403，
  /// 这里静默返回 null 由调用方兜底，不要因此打断整个流程。
  Future<String?> _fetchPrimaryEmail(String token) async {
    try {
      final res = await _request(() => _client.get(
            Uri.parse('$_base/user/emails'),
            headers: _headers(token),
          ));
      if (res.statusCode < 200 || res.statusCode >= 300) return null;
      final list = jsonDecode(utf8.decode(res.bodyBytes));
      if (list is! List) return null;

      // 优先 primary，其次第一个已验证的
      String? verifiedFallback;
      for (final e in list) {
        if (e is! Map) continue;
        final addr = e['email'] as String? ?? '';
        if (addr.isEmpty) continue;
        final primary = e['primary'] as bool? ?? false;
        final verified = e['verified'] as bool? ?? false;
        if (primary) return addr;
        if (verified) verifiedFallback ??= addr;
      }
      return verifiedFallback;
    } catch (_) {
      return null;
    }
  }

  /// fine-grained token 不返回 x-oauth-scopes 头，此时不能仅凭空值就判定无权限。
  /// 这里只在有值且明确不含 repo 时返回 false。
  bool _hasRepoScope(String scopes) {
    if (scopes.trim().isEmpty) return true; // fine-grained 或未返回
    final parts = scopes.split(',').map((e) => e.trim()).toSet();
    // classic token：repo 是总开关；public_repo 只覆盖公开仓库
    return parts.contains('repo') || parts.contains('public_repo');
  }

  /// 列出当前 token 可见的全部仓库（按最近推送排序）。
  ///
  /// 用 `/user/repos` 而不是 `/users/{name}/repos`：前者包含
  /// 组织仓库和协作者仓库，后者只有个人仓库。
  Future<List<GitHubRepo>> listRepos(
    String token, {
    int perPage = 100,
    int maxPages = 5,
    void Function(int loaded)? onProgress,
  }) async {
    final all = <GitHubRepo>[];

    for (var page = 1; page <= maxPages; page++) {
      final uri = Uri.parse(
        '$_base/user/repos'
        '?per_page=$perPage&page=$page&sort=pushed&direction=desc'
        '&affiliation=owner,collaborator,organization_member',
      );
      final res = await _request(
        () => _client.get(uri, headers: _headers(token)),
      );

      if (res.statusCode == 401) {
        throw GitHubException(
          GitHubErrorKind.badToken,
          '访问令牌无效或已过期',
          hint: '请重新生成 token',
        );
      }
      if (res.statusCode == 403) {
        final remaining = res.headers['x-ratelimit-remaining'];
        if (remaining == '0') {
          throw GitHubException(
            GitHubErrorKind.forbidden,
            '触发 GitHub API 限流',
            hint: '未登录的请求每小时只有 60 次。'
                '稍等一会再试，或确认 token 已正确填写',
          );
        }
        throw GitHubException(
          GitHubErrorKind.forbidden,
          '权限不足，无法列出仓库',
          hint: '请确认 token 勾选了 repo 权限',
        );
      }
      if (res.statusCode != 200) {
        throw GitHubException(
          GitHubErrorKind.unknown,
          '获取仓库列表失败（HTTP ${res.statusCode}）',
        );
      }

      final list = jsonDecode(utf8.decode(res.bodyBytes));
      if (list is! List) break;

      final batch = list
          .whereType<Map<String, dynamic>>()
          .map(GitHubRepo.fromJson)
          .toList();
      all.addAll(batch);
      onProgress?.call(all.length);

      // 拿不满一页说明到底了
      if (batch.length < perPage) break;
    }

    return all;
  }

  /// 查某个仓库是否对当前 token 可见。
  ///
  /// 用于 clone 失败后定位原因：能查到说明 token 有权限，失败多半是
  /// URL 或网络问题；查不到说明是 token / 权限 / 仓库名的问题。
  Future<GitHubRepo> getRepo(String token, String owner, String name) async {
    final res = await _request(() => _client.get(
          Uri.parse('$_base/repos/$owner/$name'),
          headers: _headers(token),
        ));

    if (res.statusCode == 404) {
      throw GitHubException(
        GitHubErrorKind.notFound,
        '仓库 $owner/$name 不存在，或当前令牌无权访问',
        hint: '私有仓库需要在 token 中授予 repo 权限；'
            '也检查一下仓库名有没有打错（GitHub 区分大小写）',
      );
    }
    if (res.statusCode == 401) {
      throw GitHubException(GitHubErrorKind.badToken, '访问令牌无效或已过期');
    }
    if (res.statusCode != 200) {
      throw GitHubException(
        GitHubErrorKind.unknown,
        '查询仓库失败（HTTP ${res.statusCode}）',
      );
    }
    return GitHubRepo.fromJson(_decode(res));
  }

  /// 统一处理网络层异常，转成可读提示
  ///
  /// [timeout] 不传则用默认 20 秒。只为补默认值的调用传 [_quickTimeout]，
  /// 避免用户在一个不影响结果的操作上等待过久。
  Future<http.Response> _request(
    Future<http.Response> Function() send, {
    Duration? timeout,
  }) async {
    try {
      return await send().timeout(timeout ?? _timeout);
    } on TimeoutException {
      throw GitHubException(
        GitHubErrorKind.network,
        '连接 GitHub 超时',
        hint: '当前网络访问 api.github.com 不稳定，稍后重试',
      );
    } on http.ClientException catch (e) {
      throw GitHubException(
        GitHubErrorKind.network,
        '网络请求失败：${e.message}',
        hint: '检查网络连接后重试',
      );
    } catch (e) {
      throw GitHubException(GitHubErrorKind.network, '网络异常：$e');
    }
  }

  Map<String, dynamic> _decode(http.Response res) {
    try {
      final m = jsonDecode(utf8.decode(res.bodyBytes));
      if (m is Map<String, dynamic>) return m;
      return const {};
    } catch (_) {
      return const {};
    }
  }
}