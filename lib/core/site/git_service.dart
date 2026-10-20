import 'dart:io';

import 'package:git2dart/git2dart.dart';
import 'package:path/path.dart' as p;

import 'git_change.dart';

/// 一次 clone / fetch 的进度
class GitProgress {
  const GitProgress({
    required this.phase,
    this.receivedObjects = 0,
    this.totalObjects = 0,
  });

  final String phase;
  final int receivedObjects;
  final int totalObjects;

  double? get fraction =>
      totalObjects > 0 ? receivedObjects / totalObjects : null;
}

/// 仓库状态摘要
class GitStatusSummary {
  const GitStatusSummary({
    required this.changedFiles,
    required this.insertions,
    this.branch,
  });

  final int changedFiles;
  final int insertions;
  final String? branch;

  bool get isClean => changedFiles == 0;

  /// 给 UI 用的一句话描述
  String get label {
    if (changedFiles == 0) return '无变更';
    var s = '$changedFiles 个文件已修改';
    if (insertions > 0) s += '，+$insertions';
    return s;
  }
}

/// Git 操作失败。
///
/// 保留 libgit2 的原始错误码和文本 —— 不要在这一层把错误「翻译」成
/// 单一结论，因为 libgit2 对「认证失败」和「仓库不存在」可能给同一句
/// "not found"。真正的定性交给上层结合 REST API 判断。
class GitOperationError implements Exception {
  GitOperationError({
    required this.step,
    required this.rawMessage,
  });

  /// 出错步骤：clone / push / status
  final String step;

  /// libgit2 原文，原样保留便于排查
  final String rawMessage;

  /// 是否是「认证 / 找不到仓库」这一类
  bool get looksLikeAuthOrMissing {
    final s = rawMessage.toLowerCase();
    return s.contains('authentication') ||
        s.contains('too many redirects') ||
        s.contains('not found') ||
        s.contains('404') ||
        s.contains('401') ||
        s.contains('403') ||
        s.contains('unable to access');
  }

  /// 是否是网络层问题
  bool get looksLikeNetwork {
    final s = rawMessage.toLowerCase();
    return s.contains('could not resolve') ||
        s.contains('failed to connect') ||
        s.contains('timed out') ||
        s.contains('timeout') ||
        s.contains('ssl') ||
        s.contains('tls') ||
        s.contains('certificate') ||
        s.contains('network is unreachable');
  }

  @override
  String toString() => '[$step] $rawMessage';
}

/// Git 操作封装。
///
/// 调用方式都经过 M0 真机验证，改的时候注意：
/// - `Repository.clone` 是**命名构造**
/// - `Repository.open` 打开已有仓库
/// - `repo.status` 返回 `Map<String, Set<GitStatus>>`
/// - 原生对象用完必须 `free()`
class GitService {
  GitService._();

  /// clone 到 [localPath]。
  ///
  /// 目录处理规则（这是实测出来的，别改）：
  /// libgit2 要求目标路径要么不存在，要么是**空目录**。若目录里已有
  /// 别的东西（比如上一次失败留下的内容），clone 会报 "exists"。
  static Future<void> clone({
    required String repoUrl,
    required String localPath,
    required String pat,
    String? branch,
    void Function(GitProgress)? onProgress,
  }) async {
    // libgit2 会自己创建最后一级目录，父目录必须存在
    final parent = Directory(p.dirname(localPath));
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }

    // 目标目录存在但非空 → 先清空，否则 clone 必失败
    final target = Directory(localPath);
    if (await target.exists()) {
      final hasContent = await target.list().isEmpty == false;
      if (hasContent) {
        await target.delete(recursive: true);
      }
    }

    Repository? repo;
    try {
      repo = Repository.clone(
        url: repoUrl,
        localPath: localPath,
        checkoutBranch: branch,
        callbacks: Callbacks(
          credentials: UserPass(username: 'x-access-token', password: pat),
          transferProgress: (prog) {
            onProgress?.call(GitProgress(
              phase: 'clone',
              receivedObjects: prog.receivedObjects,
              totalObjects: prog.totalObjects,
            ));
          },
        ),
      );
    } on Git2DartError catch (e) {
      // 注意：git2dart 只暴露 message，没有结构化错误码。
      // 所以这里的判断只能基于文本，这也是为什么要用 REST API 复核。
      throw GitOperationError(step: 'clone', rawMessage: e.message);
    } catch (e) {
      throw GitOperationError(step: 'clone', rawMessage: '$e');
    } finally {
      repo?.free();
    }
  }

  /// 读取仓库状态。读不到返回 null，不抛异常。
  static GitStatusSummary? readStatus(String repoPath) {
    Repository? repo;
    try {
      if (!Directory(p.join(repoPath, '.git')).existsSync()) return null;
      repo = Repository.open(repoPath);

      final status = repo.status;
      var files = 0;
      for (final entry in status.entries) {
        final flags = entry.value;
        if (flags.contains(GitStatus.ignored)) continue;
        if (flags.contains(GitStatus.current)) continue;
        files++;
      }

      final branchName = repo.head.name.replaceFirst('refs/heads/', '');

      return GitStatusSummary(
        changedFiles: files,
        insertions: 0,
        branch: branchName,
      );
    } catch (_) {
      return null;
    } finally {
      repo?.free();
    }
  }

  /// 校验并规范化仓库地址。
  ///
  /// 返回规范化后的 URL；不合法时抛 [ArgumentError]。
  ///
  /// 接受这些写法，统一成 https + .git：
  /// - `https://github.com/u/r`
  /// - `https://github.com/u/r.git`
  /// - `github.com/u/r`
  /// - `u/r`（配合已知的登录用户展开）
  static String normalizeRepoUrl(String input, {String? fallbackOwner}) {
    var s = input.trim();
    if (s.isEmpty) {
      throw ArgumentError('请填写仓库地址');
    }

    // 去掉误粘贴的尾部空白与斜杠
    s = s.replaceAll(RegExp(r'/+$'), '');

    // SSH 形式转 https（仅 github）
    if (s.startsWith('git@github.com:')) {
      s = 'https://github.com/${s.substring('git@github.com:'.length)}';
    }

    // 补协议头：github.com/u/r → https://github.com/u/r
    if (!s.startsWith('http://') && !s.startsWith('https://')) {
      if (s.startsWith('github.com/')) {
        s = 'https://$s';
      }
    }

    if (!s.contains('github.com/')) {
      if (s.startsWith('http')) {
        throw ArgumentError('目前只支持 github.com 的仓库');
      }
      // 形如 owner/repo
      final parts = s.split('/');
      if (parts.length == 2 && parts.every((e) => e.isNotEmpty)) {
        s = 'https://github.com/${parts[0]}/${parts[1]}';
      } else if (fallbackOwner != null && parts.length == 1) {
        s = 'https://github.com/$fallbackOwner/${parts[0]}';
      } else {
        throw ArgumentError('地址格式不对，应为 https://github.com/用户/仓库.git');
      }
    }

    if (!s.endsWith('.git')) s = '$s.git';

    final uri = Uri.tryParse(s);
    if (uri == null || uri.host != 'github.com') {
      throw ArgumentError('地址格式不对，应为 https://github.com/用户/仓库.git');
    }
    // 至少要有 owner/repo 两段
    final segs = uri.pathSegments.where((e) => e.isNotEmpty).toList();
    final repoName = segs.isNotEmpty ? segs.last : '';
    if (segs.length < 2 || repoName.replaceAll('.git', '').isEmpty) {
      throw ArgumentError('地址里缺少用户名或仓库名');
    }
    return s;
  }

  // ── M4：变更 / 提交 / 推送 ───────────────────────────

  /// 读取工作区与暂存区的变更明细。
  ///
  /// 返回空列表表示干净，读不到仓库时返回 null（区别于「没有变更」）。
  static List<GitChange>? readChanges(String repoPath) {
    Repository? repo;
    try {
      if (!Directory(p.join(repoPath, '.git')).existsSync()) return null;
      repo = Repository.open(repoPath);

      final status = repo.status;
      final out = <GitChange>[];

      for (final entry in status.entries) {
        final path = entry.key;
        final flags = entry.value;
        if (flags.contains(GitStatus.ignored)) continue;

        // App 自己的状态文件不该出现在「待推送变更」里。
        // 用户看到会困惑（"这是什么？我要不要提交它？"），而它确实
        // 也不属于站点内容。旧版本残留的副本一并在这里隐藏。
        if (path == 'site.json') continue;

        final change = _classify(path, flags);
        if (change != null) out.add(change);
      }

      // 按路径排序，让两个平台的列表顺序一致，便于对比与测试
      out.sort((a, b) => a.path.compareTo(b.path));
      return out;
    } catch (_) {
      return null;
    } finally {
      repo?.free();
    }
  }

  /// 把 libgit2 的位标志翻译成单一结论。
  ///
  /// 顺序很重要：冲突优先级最高，其次是删除，再到新增，最后修改。
  /// 例如一个文件同时 `wtNew | indexNew`，用户希望看到「新增」。
  static GitChange? _classify(String path, Set<GitStatus> flags) {
    if (flags.isEmpty || flags.contains(GitStatus.current)) return null;

    bool has(GitStatus s) => flags.contains(s);

    // 冲突先判断：libgit2 可能对冲突文件同时给出 wtModified
    if (has(GitStatus.conflicted)) {
      return GitChange(
        path: path,
        kind: GitChangeKind.conflicted,
        staged: false,
      );
    }

    final staged = has(GitStatus.indexNew) ||
        has(GitStatus.indexModified) ||
        has(GitStatus.indexDeleted) ||
        has(GitStatus.indexRenamed);

    if (has(GitStatus.wtDeleted) || has(GitStatus.indexDeleted)) {
      return GitChange(
        path: path,
        kind: GitChangeKind.deleted,
        staged: has(GitStatus.indexDeleted),
      );
    }
    if (has(GitStatus.wtRenamed) || has(GitStatus.indexRenamed)) {
      return GitChange(
        path: path,
        kind: GitChangeKind.renamed,
        staged: has(GitStatus.indexRenamed),
      );
    }
    if (has(GitStatus.wtNew) || has(GitStatus.indexNew)) {
      return GitChange(path: path, kind: GitChangeKind.added, staged: staged);
    }
    if (has(GitStatus.wtModified) ||
        has(GitStatus.indexModified) ||
        has(GitStatus.wtTypeChange) ||
        has(GitStatus.indexTypeChange)) {
      return GitChange(path: path, kind: GitChangeKind.modified, staged: staged);
    }

    // 其余（wtUnreadable 等）按修改处理，至少让用户知道它不干净
    return GitChange(path: path, kind: GitChangeKind.modified, staged: staged);
  }

  /// 暂存全部变更并创建一次提交。
  ///
  /// [authorName] / [authorEmail] 必须给，不给就用占位身份 ——
  /// clone 下来的仓库可能没配 user.name，`Signature.defaultSignature` 会抛异常。
  ///
  /// 返回新 commit 的短 SHA；没有可提交内容或失败时抛 [GitOperationError]。
  static String commitAll({
    required String repoPath,
    required String message,
    String authorName = 'HugoSugar',
    String authorEmail = 'hugosugar@users.noreply.github.com',
    required String branch,
  }) {
    Repository? repo;
    try {
      repo = Repository.open(repoPath);

      // 1) 全部加入暂存区
      final index = repo.index;
      try {
        // 显式排除 App 自己的状态文件。
        // 正常情况下 site.json 已经不在仓库目录里了（见 SiteController
        // ._configFileFor），但旧版本克隆的仓库可能还残留一份，
        // 这里兜底，避免它被 addAll 带进用户的提交。
        index.addAll(['*', ':(exclude)site.json']);
        if (index.hasConflicts) {
          throw GitOperationError(
            step: 'commit',
            rawMessage: '存在未解决的合并冲突，请先处理冲突文件再提交',
          );
        }
        index.write();

        // 2) 由 index 生成 tree
        final treeOid = index.writeTree(repo);
        final tree = Tree.lookup(repo: repo, oid: treeOid);

        // 3) 取 HEAD 作为父提交；空仓库（尚无 commit）时没有父
        final parents = <Commit>[];
        try {
          final headRef = repo.head;
          if (!repo.isEmpty) {
            parents.add(Commit.lookup(repo: repo, oid: headRef.target));
          }
        } catch (_) {
          // 空仓库或 detached HEAD 读不到父提交，忽略即可
        }

        // 4) 建签名。时间用当前时间，offset 用本地时区分钟数
        final now = DateTime.now();
        final sig = Signature.create(
          name: authorName,
          email: authorEmail,
          time: now.millisecondsSinceEpoch ~/ 1000,
          offset: now.timeZoneOffset.inMinutes,
        );

        final oid = Commit.create(
          repo: repo,
          updateRef: 'refs/heads/$branch',
          author: sig,
          committer: sig,
          message: message,
          tree: tree,
          parents: parents,
        );

        final sha = oid.toString();
        return sha.length > 7 ? sha.substring(0, 7) : sha;
      } finally {
        index.free();
      }
    } on GitOperationError {
      rethrow;
    } on Git2DartError catch (e) {
      throw GitOperationError(step: 'commit', rawMessage: e.message);
    } catch (e) {
      throw GitOperationError(step: 'commit', rawMessage: '$e');
    } finally {
      repo?.free();
    }
  }

  /// 推送到 origin。
  ///
  /// 用 `+refs/heads/x:refs/heads/x` 强制推是**刻意不做**的：
  /// 直接 push 若被拒（远端有别人的提交），让上层展示冲突提示，
  /// 由用户决定是拉取合并还是覆盖，绝不静默强推。
  static void push({
    required String repoPath,
    required String branch,
    required String pat,
    void Function(GitProgress)? onProgress,
  }) {
    Repository? repo;
    Remote? remote;
    try {
      repo = Repository.open(repoPath);
      remote = Remote.lookup(repo: repo, name: 'origin');
      remote.push(
        refspecs: ['refs/heads/$branch:refs/heads/$branch'],
        callbacks: Callbacks(
          credentials: UserPass(username: 'x-access-token', password: pat),
          transferProgress: (prog) {
            onProgress?.call(
              GitProgress(
                phase: 'push',
                receivedObjects: prog.receivedObjects,
                totalObjects: prog.totalObjects,
              ),
            );
          },
        ),
      );
    } on Git2DartError catch (e) {
      throw GitOperationError(step: 'push', rawMessage: e.message);
    } catch (e) {
      throw GitOperationError(step: 'push', rawMessage: '$e');
    } finally {
      remote?.free();
      repo?.free();
    }
  }

  /// 本地 HEAD 相对 origin 的领先/落后。
  ///
  /// 用来在推送前提示「你落后远端 N 个提交」——
  /// 这比等 push 被拒再解释要友好得多。
  static ({int ahead, int behind})? divergence(
    String repoPath,
    String branch,
  ) {
    Repository? repo;
    try {
      repo = Repository.open(repoPath);
      if (repo.isEmpty) return (ahead: 0, behind: 0);

      final local = repo.head.target;

      Oid remoteOid;
      try {
        final remoteRef = Reference.lookup(
          repo: repo,
          name: 'refs/remotes/origin/$branch',
        );
        remoteOid = remoteRef.target;
      } catch (_) {
        // 没有 origin 跟踪分支：还没 push 过，本地领先未知但肯定是 0 behind
        return (ahead: 0, behind: 0);
      }

      // 注意：这个 API 在 git2dart 里是 Repository 的方法，
      // 返回 [ahead, behind] 两元素列表，不是元组，也没有独立的 Graph 对象。
      final result = repo.aheadBehind(local: local, upstream: remoteOid);
      if (result.length < 2) return null;
      return (ahead: result[0], behind: result[1]);
    } catch (_) {
      return null;
    } finally {
      repo?.free();
    }
  }

  /// 从规范化 URL 中取出 owner / repo。
  static (String owner, String repo)? splitRepoUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    final segs = uri.pathSegments.where((e) => e.isNotEmpty).toList();
    if (segs.length < 2) return null;
    var name = segs[1];
    if (name.endsWith('.git')) name = name.substring(0, name.length - 4);
    return (segs[0], name);
  }
}