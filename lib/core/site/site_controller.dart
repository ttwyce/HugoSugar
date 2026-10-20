import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../fs/site_storage.dart';
import '../post/front_matter.dart';
import '../settings/app_settings.dart';
import 'file_naming.dart';
import 'commit_message.dart';
import 'git_change.dart';
import 'git_service.dart';
import 'github_api.dart';
import 'post_trash_store.dart';
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
  SiteController({GitHubApi? api, this.settings}) : _api = api ?? GitHubApi();

  /// 偏好设置来源。为空时用各字段的默认格式（向后兼容测试里直接 new 的场景）。
  final SettingsControllerLike? settings;

  static const _configFileName = 'site.json';
  static const _storageId = 'default';

  /// 站点配置文件路径。
  ///
  /// **必须放在仓库目录之外。**
  /// 早先写成 `p.join(_storage.root.path, 'site.json')`，而 storage.root 就是
  /// 克隆下来的仓库根 —— 结果这个文件成了工作区里的未跟踪文件，
  /// `git addAll(['*'])` 会把它当成文章一起提交到用户的 GitHub 仓库，
  /// 而且 lastSyncedAt 每次变动都会产生无意义的 diff。
  ///
  /// 现在放到站点目录的同级：`<appSupport>/sites/default.json`，
  /// 既在仓库外，命名又能和站点 id 对上。
  File _configFileFor(SiteStorage storage) =>
      File(p.join(storage.root.parent.path, '$_storageId.json'));

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

  /// 文章回收站。仓库就绪后按站点 id 惰性打开。
  PostTrashStore? _trash;

  SiteStage get stage => _stage;
  SiteConfig? get config => _config;
  SiteStorage? get storage => _storage;
  String? get error => _error;
  CloneFailure? get failure => _failure;

  /// 已解析的文章（含 Front Matter）
  List<PostDocument> get posts => _posts;

  /// 回收站里的文章（已删除、可恢复）
  List<TrashedPost> get trashedPosts => _trash?.items ?? const [];
  int get trashCount => _trash?.count ?? 0;

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
      final cfgFile = _configFileFor(_storage!);

      // 兼容旧版本：配置曾误写在仓库目录里（<repo>/site.json）。
      // 读到就搬到外面并删掉旧文件，避免它继续被 git 视为未跟踪文件
      // 并随下一次推送提交上去。
      final legacy = File(p.join(_storage!.root.path, _configFileName));
      if (!await cfgFile.exists() && await legacy.exists()) {
        await legacy.copy(cfgFile.path);
        try {
          await legacy.delete();
        } catch (_) {
          // 删不掉也不影响；push 时还有一层排除
        }
      }

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

      await _configFileFor(_storage!)
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
  ///
  /// 注意 [date] 需要显式传：传 null 表示「沿用原文日期」，
  /// 但不能用 `date ?? original.date` 来区分「没改」和「清空」，
  /// 因为 Hugo 的日期是必填项，清空没有意义 —— 沿用即可。
  Future<SaveResult> savePost({
    required String relativePath,
    required String title,
    required String body,
    PostDocument? original,
    bool? draft,
    List<String>? categories,
    List<String>? tags,
    DateTime? date,
    String? description,
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
        date: date ?? original?.date ?? DateTime.now(),
        draft: draft ?? original?.draft,
        categories: categories ?? original?.categories,
        tags: tags ?? original?.tags,
        // 简介允许被清空，所以传空串时要写成「删除该键」而不是沿用旧值
        description: description ?? original?.description,
        slug: original?.slug,
        weight: original?.weight,
        dateFormat: settings?.dateFormat.id ?? 'space',
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
    final slug = _buildFileSlug(title);
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
        dateFormat: settings?.dateFormat.id ?? 'space',
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

  /// 打开（或重开）回收站。
  ///
  /// 站点 id 是回收站的隔离键 —— 换一个仓库就是另一个回收站，
  /// 不能在 A 仓库删的文章出现在 B 仓库的恢复列表里。
  Future<void> _ensureTrash() async {
    final id = _config?.id;
    if (id == null || _storage == null) {
      _trash = null;
      return;
    }
    if (_trash != null && _trashSiteId == id) return;
    _trash = await PostTrashStore.open(id);
    _trashSiteId = id;
  }

  String? _trashSiteId;

  /// 确保回收站已从磁盘加载。
  ///
  /// 站点就绪（clone / 打开）时不会主动读回收站 —— 大多数启动
  /// 根本用不到它，白读一次文件。UI 在真正要展示回收站时调用。
  Future<void> loadTrash() async {
    await _ensureTrash();
    notifyListeners();
  }

  /// 把一篇文章移入回收站（软删除）。
  ///
  /// 原文完整保存到仓库之外，然后从工作区删除文件。
  /// 之所以要保存**全文**而不是路径：恢复时必须能原样写回，
  /// 包括用户自己加的 Front Matter 键。
  Future<bool> trashPost(String relativePath) async {
    final storage = _storage;
    if (storage == null) return false;
    try {
      final doc = await readPost(relativePath);
      if (doc == null) {
        _error = '文章不存在：$relativePath';
        return false;
      }
      final raw = await storage.readString(relativePath);

      await _ensureTrash();
      if (_trash == null) {
        _error = '站点尚未就绪，无法移入回收站';
        return false;
      }

      // 先写回收站，再删文件。顺序反了的话，删完崩溃就永久丢失。
      await _trash!.add(
        TrashedPost(
          relativePath: relativePath,
          title: doc.title,
          content: raw,
          deletedAt: DateTime.now(),
        ),
      );
      await storage.delete(relativePath);
      await _refreshPosts();
      notifyListeners();
      return true;
    } catch (e) {
      _error = '$e';
      return false;
    }
  }

  /// 从回收站恢复一篇文章。
  ///
  /// 原路径若已被占用（用户又建了一篇同名的），不覆盖，
  /// 改为在文件名后加 `-restored` 避免静默丢数据。
  Future<bool> restorePost(String relativePath) async {
    final storage = _storage;
    if (storage == null) return false;
    try {
      await _ensureTrash();
      final item = await _trash?.remove(relativePath);
      if (item == null) {
        _error = '回收站里没有这篇文章';
        return false;
      }

      var target = item.relativePath;
      if (await storage.existsPath(target)) {
        final dot = target.lastIndexOf('.');
        final base = dot < 0 ? target : target.substring(0, dot);
        final ext = dot < 0 ? '' : target.substring(dot);
        target = '$base-restored$ext';
        var n = 2;
        while (await storage.existsPath(target)) {
          target = '$base-restored-$n$ext';
          n++;
        }
      }

      await storage.writeString(target, item.content);
      await _refreshPosts();
      notifyListeners();
      return true;
    } catch (e) {
      _error = '$e';
      return false;
    }
  }

  /// 永久删除回收站里的一篇
  Future<bool> purgePost(String relativePath) async {
    try {
      await _ensureTrash();
      final removed = await _trash?.remove(relativePath);
      if (removed == null) return false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = '$e';
      return false;
    }
  }

  /// 清空回收站，返回清掉的条数
  Future<int> purgeAllTrashedPosts() async {
    try {
      await _ensureTrash();
      final n = await _trash?.clear() ?? 0;
      notifyListeners();
      return n;
    } catch (e) {
      _error = '$e';
      return 0;
    }
  }

  /// 删除一篇文章（**硬删除**，不进回收站）
  ///
  /// 保留给「回收站里再永久删除」以及内部清理用。
  /// 用户在文章列表里点删除走的是 [trashPost]。
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

  // ── M4：推送 ────────────────────────────────────────

  /// 读取当前未提交的变更。
  List<GitChange> get changes {
    final root = repoPath;
    if (root == null) return const [];
    return GitService.readChanges(root) ?? const [];
  }

  /// 本地相对远端的领先/落后
  ({int ahead, int behind})? get divergence {
    final root = repoPath;
    final cfg = _config;
    if (root == null || cfg == null) return null;
    return GitService.divergence(root, cfg.branch);
  }

  /// 生成默认 commit message
  String suggestCommitMessage() =>
      CommitMessage.suggest(
        changes.map((e) => e.path).toList(),
      );

  /// 执行一次完整推送：commit → push。
  ///
  /// 只推 GitHub，不碰任何部署平台 —— 部署由平台监听仓库自行触发。
  ///
  /// [pat] 由调用方传入而不是这里读磁盘：token 存在
  /// flutter_secure_storage 里，属于 UI 层的职责，core 不碰密钥。
  ///
  /// 返回 null 表示成功，否则返回给用户看的错误文案。
  /// 每一步都会写进 [pushLog] 供 UI 展开查看。
  Future<PushOutcome> push({
    required String pat,
    required String commitMessage,
    void Function(String)? onStep,
  }) async {
    final root = repoPath;
    final cfg = _config;
    if (root == null || cfg == null) {
      return PushOutcome.failure('站点未就绪');
    }
    if (pat.trim().isEmpty) {
      return PushOutcome.failure('缺少 GitHub 访问令牌，请到站点页重新填写');
    }

    final log = <String>[];
    void step(String s) {
      log.add(s);
      onStep?.call(s);
    }

    // 1) 先看有没有东西可提交
    final pending = GitService.readChanges(root) ?? const [];
    if (pending.isEmpty) {
      step('没有需要提交的改动');
      return PushOutcome.failure('没有需要提交的改动', log: log);
    }
    if (pending.any((e) => e.isConflict)) {
      step('存在未解决的冲突');
      return PushOutcome.failure(
        '有 ${pending.where((e) => e.isConflict).length} 个文件存在合并冲突，'
        '需要先解决冲突再推送',
        log: log,
      );
    }

    // 2) 推送前先看是否落后远端 —— 早提示比等 push 被拒好
    final div = GitService.divergence(root, cfg.branch);
    if (div != null && div.behind > 0) {
      step('本地落后远端 ${div.behind} 个提交');
      return PushOutcome.failure(
        '远端有 ${div.behind} 个你本地没有的提交。'
        '为避免覆盖别人的改动，请先拉取同步（站点页 → 重新克隆）。',
        log: log,
        needsPull: true,
      );
    }

    // 3) commit
    String sha;
    try {
      step('提交中…');

      // 提交作者优先用用户在设置里填的身份，没填才回落到令牌对应的账号。
      //
      // 为什么允许手填：自动推断只能拿到 GitHub 公开邮箱或 noreply 地址。
      // `/user/emails` 需要 `user:email` 授权，多数 classic token 没勾，
      // 拿不到就只能拼一个 `<id>+<login>@users.noreply.github.com`。
      // 而用户想要的往往是自己的真实邮箱 —— 只有他自己知道。
      final profile = await _api.fetchProfile(pat);
      final name = (settings?.authorName ?? '').isNotEmpty
          ? settings!.authorName
          : profile.commitName;
      final email = (settings?.authorEmail ?? '').isNotEmpty
          ? settings!.authorEmail
          : profile.email;

      if (email.isEmpty) {
        step('警告：拿不到邮箱，提交不会关联到 GitHub 账号');
      }
      step('提交者：$name <$email>');

      final msg = commitMessage.trim().isEmpty
          ? CommitMessage.suggest(pending.map((e) => e.path).toList())
          : commitMessage.trim();
      sha = GitService.commitAll(
        repoPath: root,
        message: msg,
        authorName: name,
        authorEmail: email,
        branch: cfg.branch,
      );
      step('已提交 $sha（${pending.length} 个文件）');
    } on GitHubException catch (e) {
      step('读取账号资料失败：${e.message}');
      return PushOutcome.failure(
        '无法确认提交身份：${e.message}',
        log: log,
      );
    } on GitOperationError catch (e) {
      step('提交失败：${e.rawMessage}');
      return PushOutcome.failure(_humanize(e), log: log);
    }

    // 4) push
    try {
      step('推送中…');
      GitService.push(
        repoPath: root,
        branch: cfg.branch,
        pat: pat.trim(),
      );
      step('推送成功');
    } on GitOperationError catch (e) {
      step('推送失败：${e.rawMessage}');
      final hint = e.looksLikeNetwork
          ? '网络不稳定，可重试；提交已在本地，不会丢。'
          : '推送被拒绝时通常是远端有新提交。提交已在本地，可以稍后重试。';
      return PushOutcome.failure(
        '${_humanize(e)}\n$hint',
        log: log,
      );
    }

    // 5) 刷新站点（.git 变了但文章内容没变，这里主要是更新 lastSyncedAt）
    await _touchSynced();
    notifyListeners();

    return PushOutcome.success(commitSha: sha, log: log);
  }

  /// push 之后更新 lastSyncedAt 并落盘
  Future<void> _touchSynced() async {
    final cfg = _config;
    final storage = _storage;
    if (cfg == null || storage == null) return;
    final updated = cfg.copyWith(lastSyncedAt: DateTime.now());
    _config = updated;
    try {
      await _configFileFor(storage)
          .writeAsString(jsonEncode(updated.toJson()), flush: true);
    } catch (_) {
      // 时间戳写不进去不影响使用
    }
  }

  /// 把 libgit2 的原文翻译成用户能看懂的句子。
  ///
  /// 保留原文在日志里，但主提示必须是人话 ——
  /// "callback returned error" 这种对用户毫无意义。
  String _humanize(GitOperationError e) {
    final s = e.rawMessage.toLowerCase();
    if (s.contains('authentication') || s.contains('401')) {
      return '认证失败：GitHub 令牌可能已过期或权限不足';
    }
    if (s.contains('403') || s.contains('forbidden')) {
      return '权限不足：令牌需要 repo 权限';
    }
    if (s.contains('non-fast-forward') ||
        s.contains('rejected') ||
        s.contains('fetch first')) {
      return '推送被拒绝：远端有本地没有的提交';
    }
    if (e.looksLikeNetwork) {
      return '网络错误：${e.rawMessage}';
    }
    return e.rawMessage;
  }

  /// 按设置的命名规则生成文件名主干（不含扩展名）。
  ///
  /// 真正的实现在 [file_naming.dart]，那里可以脱离原生库单独测试。
  String _buildFileSlug(String title) => buildFileSlug(
        title: title,
        style: settings?.fileNameStyle ?? FileNameStyle.fromTitle,
      );

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

/// 一次推送的结果。
///
/// 不只是成功/失败两态：还要带上「要不要先拉取」这种可操作的提示，
/// 以及每一步的执行日志 —— 用户点推送失败时最想知道「到底卡在哪」。
class PushOutcome {
  const PushOutcome._({
    required this.ok,
    this.message,
    this.commitSha,
    this.log = const [],
    this.needsPull = false,
  });

  final bool ok;

  /// 失败时的用户可读原因（已 humanize）
  final String? message;

  /// 成功的短 SHA
  final String? commitSha;

  /// 执行过程日志，按顺序
  final List<String> log;

  /// 是否因为「落后远端」而失败，UI 可据此提示「先拉取」
  final bool needsPull;

  static PushOutcome success({
    required String commitSha,
    List<String> log = const [],
  }) =>
      PushOutcome._(
        ok: true,
        commitSha: commitSha,
        log: log,
      );

  static PushOutcome failure(
    String message, {
    List<String> log = const [],
    bool needsPull = false,
  }) =>
      PushOutcome._(
        ok: false,
        message: message,
        log: log,
        needsPull: needsPull,
      );
}