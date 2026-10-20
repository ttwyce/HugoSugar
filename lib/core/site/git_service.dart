import 'dart:io';

import 'package:git2dart/git2dart.dart';
import 'package:path/path.dart' as p;

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

/// Git 操作封装。
///
/// 这里的方法都是 M0 冒烟测试验证过的调用方式，改的时候注意：
/// - `Repository.clone` 是**命名构造**，不是静态方法
/// - `Repository.open` 打开已有仓库
/// - `repo.status` 返回 `Map<String, Set<GitStatus>>`
///
/// 原生对象用完必须 `free()`，否则会泄漏。
class GitService {
  GitService._();

  /// clone 到 [localPath]。
  ///
  /// PAT 走 `UserPass(username: 'x-access-token', password: pat)`，
  /// 这是 GitHub 对 token 认证的约定写法。
  static Future<void> clone({
    required String repoUrl,
    required String localPath,
    required String pat,
    String? branch,
    void Function(GitProgress)? onProgress,
  }) async {
    final parent = Directory(p.dirname(localPath));
    if (!await parent.exists()) {
      await parent.create(recursive: true);
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
    } finally {
      repo?.free();
    }
  }

  /// 读取仓库状态：变更文件数、插入行数、当前分支。
  ///
  /// 读不到就返回 null，不抛异常 —— 站点页用它做展示，不该因为
  /// git 状态异常而整页崩掉。
  static GitStatusSummary? readStatus(String repoPath) {
    Repository? repo;
    try {
      if (!Directory(p.join(repoPath, '.git')).existsSync()) return null;
      repo = Repository.open(repoPath);

      final status = repo.status;
      var files = 0;
      for (final entry in status.entries) {
        // 只统计真实的变更，忽略 ignored
        final flags = entry.value;
        if (flags.contains(GitStatus.ignored)) continue;
        if (flags.contains(GitStatus.current)) continue;
        files++;
      }

      final branchName = repo.head.name.replaceFirst('refs/heads/', '');

      return GitStatusSummary(
        changedFiles: files,
        insertions: 0, // 差异统计留到 M4 的变更列表里做
        branch: branchName,
      );
    } catch (_) {
      return null;
    } finally {
      repo?.free();
    }
  }

  /// 校验仓库 URL 形状，返回错误提示；合法则返回 null。
  ///
  /// 参数声明为可空，方便直接当 [FormFieldValidator] 用。
  /// 这里只做本地校验，不联网。
  static String? validateRepoUrl(String? url) {
    final s = (url ?? '').trim();
    if (s.isEmpty) return '请填写仓库地址';
    if (!s.startsWith('https://')) return '只支持 https:// 开头的地址';
    if (!s.endsWith('.git')) return '地址应以 .git 结尾';
    if (!s.contains('/')) return '地址格式不对，应为 https://github.com/用户/仓库.git';
    return null;
  }
}