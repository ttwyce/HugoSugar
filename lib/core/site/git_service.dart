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