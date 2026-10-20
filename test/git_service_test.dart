import 'package:flutter_test/flutter_test.dart';
import 'package:hugosugar/core/site/git_service.dart';

void main() {
  group('normalizeRepoUrl', () {
    test('标准的 https + .git 保持不变', () {
      expect(
        GitService.normalizeRepoUrl('https://github.com/octocat/Hello-World.git'),
        'https://github.com/octocat/Hello-World.git',
      );
    });

    test('缺 .git 会自动补上', () {
      expect(
        GitService.normalizeRepoUrl('https://github.com/octocat/Hello-World'),
        'https://github.com/octocat/Hello-World.git',
      );
    });

    test('缺协议头会补 https', () {
      expect(
        GitService.normalizeRepoUrl('github.com/octocat/Hello-World'),
        'https://github.com/octocat/Hello-World.git',
      );
    });

    test('owner/repo 简写可展开', () {
      expect(
        GitService.normalizeRepoUrl('octocat/Hello-World'),
        'https://github.com/octocat/Hello-World.git',
      );
    });

    test('SSH 形式转 https', () {
      expect(
        GitService.normalizeRepoUrl('git@github.com:octocat/Hello-World.git'),
        'https://github.com/octocat/Hello-World.git',
      );
    });

    test('去掉尾部多余斜杠', () {
      expect(
        GitService.normalizeRepoUrl('https://github.com/octocat/Hello-World///'),
        'https://github.com/octocat/Hello-World.git',
      );
    });

    test('中文空白会被 trim', () {
      expect(
        GitService.normalizeRepoUrl('  https://github.com/a/b.git  '),
        'https://github.com/a/b.git',
      );
    });

    test('空字符串报错', () {
      expect(
        () => GitService.normalizeRepoUrl('   '),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('非 github 域名报错', () {
      expect(
        () => GitService.normalizeRepoUrl('https://gitlab.com/a/b.git'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('只有仓库名、没有 owner 时报错', () {
      expect(
        () => GitService.normalizeRepoUrl('Hello-World'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('splitRepoUrl', () {
    test('解析出 owner 和 repo', () {
      final r = GitService.splitRepoUrl(
        'https://github.com/octocat/Hello-World.git',
      );
      expect(r, ('octocat', 'Hello-World'));
    });

    test('无 .git 也能解析', () {
      final r = GitService.splitRepoUrl('https://github.com/a/b');
      expect(r, ('a', 'b'));
    });

    test('路径不足返回 null', () {
      expect(GitService.splitRepoUrl('https://github.com/onlyowner'), isNull);
    });
  });

  group('GitOperationError 分类', () {
    test('not found 归为认证/缺失类', () {
      final e = GitOperationError(
        step: 'clone',
        rawMessage: 'remote authentication required but no callback set',
      );
      expect(e.looksLikeAuthOrMissing, isTrue);
      expect(e.looksLikeNetwork, isFalse);
    });

    test('TLS 失败归为网络类', () {
      final e = GitOperationError(
        step: 'clone',
        rawMessage: 'SSL error: tls handshake failed',
      );
      expect(e.looksLikeNetwork, isTrue);
    });

    test('DNS 失败归为网络类', () {
      final e = GitOperationError(
        step: 'clone',
        rawMessage: 'failed to connect: Could not resolve host',
      );
      expect(e.looksLikeNetwork, isTrue);
    });
  });
}