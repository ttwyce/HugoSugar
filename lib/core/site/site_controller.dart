import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../fs/site_storage.dart';
import 'git_service.dart';
import 'github_api.dart';
import 'site_config.dart';

/// 站点接入的整体状态
enum SiteStage {
  /// 还没有配置站点
  empty,

  /// 正在 clone
  cloning,

  /// 已就绪
  ready,

  /// 出错
  failed,
}

/// clone 失败的原因归类（给出可操作建议，而不是丢一段 libgit2 原文）
enum CloneFailureKind {
  /// token 无效 / 过期
  badToken,

  /// token 有效但看不到这个仓库（私有仓库没给权限）
  noAccess,

  /// 仓库名确实不存在
  repoMissing,

  /// 网络问题
  network,

  /// 其他
  unknown,
}

class CloneFailure {
  CloneFailure({
    required this.kind,
    required this.title,
    required this.detail,
    this.raw,
  });

  final CloneFailureKind kind;
  final String title;
  final String detail;

  /// libgit2 原文，折叠展示，方便排查
  final String? raw;
}

/// 站点控制器：负责拉仓库列表、clone、识别文章目录、存配置。
class SiteController extends ChangeNotifier {
  SiteController({GitHubApi? api}) : _api = api ?? GitHubApi();

  static const _configFileName = 'site.json';
  static const _storageId = 'default';

  final GitHubApi _api;

  SiteStage _stage = SiteStage.empty;
  SiteConfig? _config;
  SiteStorage? _storage;
  String? _error;
  CloneFailure? _failure;

  // clone 进度
  int _received = 0;
  int _total = 0;

  List<String> _posts = const [];

  SiteStage get stage => _stage;
  SiteConfig? get config => _config;
  SiteStorage? get storage => _storage;
  String? get error => _error;
  CloneFailure? get failure => _failure;
  List<String> get posts => _posts;

  double? get progress => _total > 0 ? _received / _total : null;

  String? get repoPath => _storage?.root.path;

  // ── GitHub 相关 ────────────────────────────────────

  /// 最近一次校验通过的登录名
  String? _login;
  String? get login => _login;

  /// 校验 token，返回登录名
  Future<String> verifyToken(String token) async {
    final name = await _api.validateToken(token);
    _login = name;
    notifyListeners();
    return name;
  }

  /// 列出该 token 可见的仓库
  Future<List<GitHubRepo>> listRepos(
    String token, {
    void Function(int loaded)? onProgress,
  }) {
    return _api.listRepos(token, onProgress: onProgress);
  }

  // ── 站点生命周期 ────────────────────────────────────

  /// 启动时恢复已有站点
  Future<void> load() async {
    try {
      _storage = await AppPrivateStorage.open(_storageId);
      final cfgFile = File(p.join(_storage!.root.path, _configFileName));
      if (!await cfgFile.exists()) {
        _stage = SiteStage.empty;
        notifyListeners();
        return;
      }

      final json =
          jsonDecode(await cfgFile.readAsString()) as Map<String, Object?>;
      _config = SiteConfig.fromJson(json);

      final hasGit =
          Directory(p.join(_storage!.root.path, '.git')).existsSync();
      if (!hasGit) {
        _stage = SiteStage.empty;
        notifyListeners();
        return;
      }

      await _refreshPosts();
      _stage = SiteStage.ready;
    } catch (e) {
      _error = '$e';
      _stage = SiteStage.failed;
    }
    notifyListeners();
  }

  /// 接入站点：clone + 识别目录 + 落配置。
  ///
  /// [pat] 用来 clone；如果传了 [repo]，会优先使用它的 cloneUrl 和默认分支。
  Future<bool> connect({
    required String repoUrl,
    required String pat,
    required String displayName,
    String? branch,
    String postsDir = 'content/posts',
    GitHubRepo? repo,
  }) async {
    _stage = SiteStage.cloning;
    _error = null;
    _failure = null;
    _received = 0;
    _total = 0;
    notifyListeners();

    // 1) 规范化 URL（支持用户手输各种形式）
    String url;
    try {
      url = repo?.cloneUrl ??
          GitService.normalizeRepoUrl(repoUrl, fallbackOwner: _login);
    } on ArgumentError catch (e) {
      _failWith(
        CloneFailure(
          kind: CloneFailureKind.repoMissing,
          title: '仓库地址不对',
          detail: e.message,
        ),
      );
      return false;
    }

    final targetBranch = branch ?? repo?.defaultBranch;

    try {
      _storage ??= await AppPrivateStorage.open(_storageId);
      final target = _storage!.root.path;

      var lastNotified = 0;
      await GitService.clone(
        repoUrl: url,
        localPath: target,
        pat: pat.trim(),
        branch: targetBranch,
        onProgress: (prog) {
          _received = prog.receivedObjects;
          _total = prog.totalObjects;
          final now = DateTime.now().millisecondsSinceEpoch;
          if (now - lastNotified > 300) {
            lastNotified = now;
            notifyListeners();
          }
        },
      );

      final detected = await _detectPostsDir(postsDir);

      _config = SiteConfig(
        id: _storageId,
        displayName: displayName.trim().isEmpty
            ? (repo?.name ?? '我的站点')
            : displayName.trim(),
        repoUrl: url,
        branch: targetBranch ?? 'main',
        postsDir: detected,
        lastSyncedAt: DateTime.now(),
      );

      await File(p.join(target, _configFileName))
          .writeAsString(jsonEncode(_config!.toJson()));

      await _refreshPosts();
      _stage = SiteStage.ready;
      notifyListeners();
      return true;
    } on GitOperationError catch (e) {
      // 关键一步：clone 失败时用 REST API 复核，把真正的死因找出来
      final diagnosed = await _diagnose(e, url, pat);
      _failWith(diagnosed);
      return false;
    } catch (e) {
      _failWith(
        CloneFailure(
          kind: CloneFailureKind.unknown,
          title: '克隆失败',
          detail: '$e',
        ),
      );
      return false;
    }
  }

  /// clone 失败后，用 GitHub REST API 判断到底是哪种失败。
  ///
  /// 为什么需要这一步：libgit2 在认证失败和仓库不存在时给的都是
  /// "not found"，直接展示等于让用户自己猜。REST 能给出明确结论：
  /// - getRepo 404 → token 看不到这个仓库（权限或仓库名问题）
  /// - getRepo 200 → 仓库可达，那 clone 失败就是网络/URL 问题
  /// - token 本身 401 → token 有问题
  Future<CloneFailure> _diagnose(
    GitOperationError e,
    String url,
    String pat,
  ) async {
    // 网络类错误直接归类，不必再请求 API
    if (e.looksLikeNetwork) {
      return CloneFailure(
        kind: CloneFailureKind.network,
        title: '网络连接失败',
        detail: '无法连接 github.com。请检查网络后重试 —— '
            '这个网络环境访问 GitHub 偶发 TLS 握手失败，重试常常就好了。',
        raw: e.rawMessage,
      );
    }

    final parts = GitService.splitRepoUrl(url);
    if (parts == null) {
      return CloneFailure(
        kind: CloneFailureKind.repoMissing,
        title: '仓库地址不对',
        detail: '无法从地址中解析出用户名和仓库名：$url',
        raw: e.rawMessage,
      );
    }
    final (owner, repoName) = parts;

    // 用 REST 复核
    try {
      await _api.getRepo(pat.trim(), owner, repoName);
      // 能查到 → 仓库可达，失败多半是 libgit2 的网络/证书层问题
      return CloneFailure(
        kind: CloneFailureKind.network,
        title: '仓库可达，但克隆失败',
        detail: '已确认 $owner/$repoName 对当前令牌可见，'
            '失败更可能来自网络层或 TLS 握手。请重试一次。',
        raw: e.rawMessage,
      );
    } on GitHubException catch (gh) {
      switch (gh.kind) {
        case GitHubErrorKind.badToken:
          return CloneFailure(
            kind: CloneFailureKind.badToken,
            title: '访问令牌无效',
            detail: '${gh.message}${gh.hint == null ? "" : "\n${gh.hint}"}',
            raw: e.rawMessage,
          );
        case GitHubErrorKind.notFound:
          return CloneFailure(
            kind: CloneFailureKind.noAccess,
            title: '仓库不可访问',
            detail: '令牌看不到 $owner/$repoName。常见原因：\n'
                '· 私有仓库但令牌没勾 repo 权限\n'
                '· 仓库名大小写不一致\n'
                '· 仓库属于组织，需要授权',
            raw: e.rawMessage,
          );
        case GitHubErrorKind.network:
          return CloneFailure(
            kind: CloneFailureKind.network,
            title: '网络连接失败',
            detail: '无法访问 api.github.com，请检查网络。',
            raw: e.rawMessage,
          );
        case GitHubErrorKind.forbidden:
        case GitHubErrorKind.unknown:
          return CloneFailure(
            kind: CloneFailureKind.unknown,
            title: '克隆失败',
            detail: gh.message,
            raw: e.rawMessage,
          );
      }
    } catch (_) {
      // REST 也失败了，回落到原文
      return CloneFailure(
        kind: CloneFailureKind.unknown,
        title: '克隆失败',
        detail: '无法进一步诊断原因，请查看下方原始错误。',
        raw: e.rawMessage,
      );
    }
  }

  void _failWith(CloneFailure f) {
    _failure = f;
    _error = '${f.title}\n${f.detail}';
    _stage = SiteStage.failed;
    notifyListeners();
  }

  /// 清掉失败状态，回到表单
  void resetFailure() {
    _failure = null;
    _error = null;
    _stage = _config == null ? SiteStage.empty : SiteStage.failed;
    notifyListeners();
  }

  Future<void> refresh() async {
    if (_stage != SiteStage.ready) return;
    await _refreshPosts();
    notifyListeners();
  }

  Future<void> disconnect() async {
    try {
      _storage ??= await AppPrivateStorage.open(_storageId);
      final dir = _storage!.root;
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {}
    _config = null;
    _posts = const [];
    _stage = SiteStage.empty;
    _error = null;
    _failure = null;
    notifyListeners();
  }

  /// 依次尝试常见文章目录，返回第一个存在的
  Future<String> _detectPostsDir(String preferred) async {
    final candidates = <String>[
      preferred,
      'content/posts',
      'content/post',
      'content',
      'posts',
      'src/content/posts',
    ];
    for (final c in candidates) {
      if (c.isEmpty) continue;
      if (await _storage!.existsPath(c)) return c;
    }
    return preferred;
  }

  Future<void> _refreshPosts() async {
    final dir = _config?.postsDir;
    if (dir == null || _storage == null) {
      _posts = const [];
      return;
    }
    _posts = await _storage!.listFiles(dir, extension: '.md');
  }

  @override
  void dispose() {
    _api.dispose();
    super.dispose();
  }
}