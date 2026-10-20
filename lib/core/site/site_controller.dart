import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../fs/site_storage.dart';
import '../post/front_matter.dart';
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

  List<PostDocument> _posts = const [];

  SiteStage get stage => _stage;
  SiteConfig? get config => _config;
  SiteStorage? get storage => _storage;
  String? get error => _error;
  CloneFailure? get failure => _failure;

  /// 已解析的文章（含 Front Matter）
  List<PostDocument> get posts => _posts;

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

    // 递归：Hugo 的 content/posts 下经常再分目录
    final paths = await _storage!.listFilesRecursive(dir, extension: '.md');

    final parsed = <PostDocument>[];
    for (final rel in paths) {
      try {
        final content = await _storage!.readString(rel);
        parsed.add(
          FrontMatter.parse(
            relativePath: rel,
            fileName: p.basename(rel),
            content: content,
          ),
        );
      } catch (_) {
        // 单个文件读失败不能影响整张列表
      }
    }

    // 有日期的按日期倒序，没日期的排后面并按文件名
    parsed.sort((a, b) {
      final da = a.date;
      final db = b.date;
      if (da != null && db != null) return db.compareTo(da);
      if (da != null) return -1;
      if (db != null) return 1;
      return a.relativePath.compareTo(b.relativePath);
    });

    _posts = parsed;
  }

  // ── 派生统计 ────────────────────────────────────────

  /// 所有分类（按出现次数降序）
  List<String> get allCategories => _collect((p) => p.categories);

  /// 所有标签（按出现次数降序）
  List<String> get allTags => _collect((p) => p.tags);

  List<String> _collect(List<String> Function(PostDocument) pick) {
    final counter = <String, int>{};
    for (final p in _posts) {
      for (final v in pick(p)) {
        counter[v] = (counter[v] ?? 0) + 1;
      }
    }
    final keys = counter.keys.toList()
      ..sort((a, b) {
        final d = counter[b]!.compareTo(counter[a]!);
        return d != 0 ? d : a.compareTo(b);
      });
    return keys;
  }

  /// 某分类下的文章数
  int countInCategory(String name) =>
      _posts.where((p) => p.categories.contains(name)).length;

  /// 某标签下的文章数
  int countWithTag(String name) =>
      _posts.where((p) => p.tags.contains(name)).length;

  /// 草稿数
  int get draftCount => _posts.where((p) => p.draft).length;

  /// 已发布数
  int get publishedCount => _posts.where((p) => !p.draft).length;

  /// 读一整篇（编辑器用）
  Future<PostDocument?> readPost(String relativePath) async {
    if (_storage == null) return null;
    try {
      final content = await _storage!.readString(relativePath);
      return FrontMatter.parse(
        relativePath: relativePath,
        fileName: p.basename(relativePath),
        content: content,
      );
    } catch (_) {
      return null;
    }
  }

  // ── 写入 ────────────────────────────────────────────

  /// 保存一篇已有文章。
  ///
  /// 只传改动过的字段；[original] 传原文档，用于保留未知 Front Matter 键。
  Future<SaveResult> savePost({
    required String relativePath,
    required String title,
    required String body,
    PostDocument? original,
    bool? draft,
    List<String>? categories,
    List<String>? tags,
  }) async {
    if (_storage == null) {
      return SaveResult.failure('站点未就绪，无法保存');
    }
    try {
      final content = FrontMatterBuilder.build(
        original: original?.frontMatter ?? const {},
        format: original?.format ?? 'yaml',
        title: title,
        body: body,
        date: original?.date ?? DateTime.now(),
        draft: draft ?? original?.draft,
        categories: categories ?? original?.categories,
        tags: tags ?? original?.tags,
        description:
            (original?.description.isEmpty ?? true) ? null : original?.description,
        slug: original?.slug,
        weight: original?.weight,
      );

      await _storage!.writeString(relativePath, content);
      await _refreshPosts();
      notifyListeners();
      return SaveResult.success();
    } catch (e) {
      return SaveResult.failure('$e');
    }
  }

  /// 新建文章。
  ///
  /// 返回新文件的相对路径；失败返回 null 并把原因写进 [error]。
  Future<String?> createPost({
    required String title,
    List<String> categories = const [],
    List<String> tags = const [],
    String description = '',
    bool draft = true,
  }) async {
    if (_storage == null || _config == null) {
      _error = '站点未就绪';
      return null;
    }
    if (title.trim().isEmpty) {
      _error = '标题不能为空';
      return null;
    }

    final dir = _config!.postsDir;
    final slug = _slugify(title);
    var relativePath = p.posix.join(dir, '$slug.md');

    // 同名文件已存在 → 加后缀，绝不覆盖用户已有的文章
    var n = 2;
    while (await _storage!.existsPath(relativePath)) {
      relativePath = p.posix.join(dir, '$slug-$n.md');
      n++;
    }

    try {
      final content = FrontMatterBuilder.createNew(
        title: title.trim(),
        draft: draft,
        categories: categories,
        tags: tags,
        description: description,
        body: '',
      );
      await _storage!.writeString(relativePath, content);
      await _refreshPosts();
      notifyListeners();
      return relativePath;
    } catch (e) {
      _error = '$e';
      return null;
    }
  }

  /// 删除一篇文章
  Future<bool> deletePost(String relativePath) async {
    if (_storage == null) return false;
    try {
      await _storage!.delete(relativePath);
      await _refreshPosts();
      notifyListeners();
      return true;
    } catch (e) {
      _error = '$e';
      return false;
    }
  }

  /// 标题转 slug。
  ///
  /// 中文标题不能直接当文件名（Hugo 能认，但 URL 会变成百分号编码），
  /// 所以取「ASCII 化失败就用时间戳」的策略，保证文件名总是合法的。
  String _slugify(String title) {
    final s = title
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s-]'), '') // 去掉标点与非 ASCII
        .replaceAll(RegExp(r'[\s_]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');

    if (s.isNotEmpty) return s;
    // 纯中文标题：用时间戳兜底，避免出现空文件名
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return 'post-${now.year}${two(now.month)}${two(now.day)}'
        '-${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }

  @override
  void dispose() {
    _api.dispose();
    super.dispose();
  }
}

/// 保存结果
class SaveResult {
  const SaveResult._(this.ok, this.message);

  final bool ok;
  final String? message;

  static SaveResult success() => const SaveResult._(true, null);
  static SaveResult failure(String msg) => SaveResult._(false, msg);
}