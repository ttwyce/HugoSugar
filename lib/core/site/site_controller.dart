import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../fs/site_storage.dart';
import 'git_service.dart';
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

/// 站点控制器：负责 clone、识别文章目录、存配置。
///
/// 用 ChangeNotifier 而不是引入状态管理库 —— M1 阶段只有一个页面关心它，
/// 等 M2 文章列表接入时再看要不要上 Provider/Riverpod。
class SiteController extends ChangeNotifier {
  SiteController();

  static const _configFileName = 'site.json';
  static const _storageId = 'default';

  SiteStage _stage = SiteStage.empty;
  SiteConfig? _config;
  SiteStorage? _storage;
  String? _error;

  // clone 进度
  int _received = 0;
  int _total = 0;

  /// 文章目录下的文件列表
  List<String> _posts = const [];

  SiteStage get stage => _stage;
  SiteConfig? get config => _config;
  SiteStorage? get storage => _storage;
  String? get error => _error;
  List<String> get posts => _posts;

  double? get progress => _total > 0 ? _received / _total : null;

  /// 本地仓库绝对路径
  String? get repoPath => _storage?.root.path;

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

      final json = jsonDecode(await cfgFile.readAsString()) as Map<String, Object?>;
      _config = SiteConfig.fromJson(json);

      // 配置在但仓库没了（比如手动清了缓存），退回到 empty
      final hasGit = Directory(p.join(_storage!.root.path, '.git')).existsSync();
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

  /// 接入一个新站点：clone + 识别目录 + 落配置
  Future<bool> connect({
    required String repoUrl,
    required String pat,
    required String displayName,
    String branch = 'main',
    String postsDir = 'content/posts',
  }) async {
    final urlError = GitService.validateRepoUrl(repoUrl);
    if (urlError != null) {
      _error = urlError;
      _stage = SiteStage.failed;
      notifyListeners();
      return false;
    }

    _stage = SiteStage.cloning;
    _error = null;
    _received = 0;
    _total = 0;
    notifyListeners();

    try {
      _storage ??= await AppPrivateStorage.open(_storageId);
      final target = _storage!.root.path;

      // 目标目录里已经有 .git 就先清掉，避免 clone 报「目录非空」
      if (Directory(p.join(target, '.git')).existsSync()) {
        await _storage!.delete('.git', recursive: true);
      }

      var lastNotified = 0;
      await GitService.clone(
        repoUrl: repoUrl.trim(),
        localPath: target,
        pat: pat.trim(),
        branch: branch,
        onProgress: (prog) {
          _received = prog.receivedObjects;
          _total = prog.totalObjects;
          // 进度回调非常频繁，每 300ms 才刷新一次 UI
          final now = DateTime.now().millisecondsSinceEpoch;
          if (now - lastNotified > 300) {
            lastNotified = now;
            notifyListeners();
          }
        },
      );

      // 自动识别文章目录：配置的不存在就挨个试常见路径
      final detected = await _detectPostsDir(postsDir);

      _config = SiteConfig(
        id: _storageId,
        displayName: displayName.trim().isEmpty ? '我的站点' : displayName.trim(),
        repoUrl: repoUrl.trim(),
        branch: branch,
        postsDir: detected,
        lastSyncedAt: DateTime.now(),
      );

      await File(p.join(target, _configFileName))
          .writeAsString(jsonEncode(_config!.toJson()));

      await _refreshPosts();
      _stage = SiteStage.ready;
      notifyListeners();
      return true;
    } catch (e) {
      _error = _friendlyError('$e');
      _stage = SiteStage.failed;
      notifyListeners();
      return false;
    }
  }

  /// 重新读文章列表
  Future<void> refresh() async {
    if (_stage != SiteStage.ready) return;
    await _refreshPosts();
    notifyListeners();
  }

  /// 解绑站点：删掉本地仓库和配置
  Future<void> disconnect() async {
    try {
      _storage ??= await AppPrivateStorage.open(_storageId);
      final dir = _storage!.root;
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {
      // 删不掉就算了，下次 open 会重建
    }
    _config = null;
    _posts = const [];
    _stage = SiteStage.empty;
    _error = null;
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
    // 一个都没有就返回配置值，让上层提示用户
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

  /// 把 git2dart 的原始报错翻译成人话
  String _friendlyError(String raw) {
    final s = raw.toLowerCase();
    if (s.contains('authentication') || s.contains('401')) {
      return '认证失败：请检查访问令牌是否有效、是否勾选了 repo 权限';
    }
    if (s.contains('not found') || s.contains('404')) {
      return '仓库不存在：请检查地址是否正确、仓库是否为私有但令牌无权限';
    }
    if (s.contains('certificate') || s.contains('ssl')) {
      return 'TLS 连接失败：可能是网络问题，稍后重试';
    }
    if (s.contains('exists') && s.contains('not empty')) {
      return '目标目录非空，请先解绑再重新连接';
    }
    return raw;
  }
}