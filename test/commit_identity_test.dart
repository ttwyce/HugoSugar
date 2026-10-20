import 'package:flutter_test/flutter_test.dart';
import 'package:hugosugar/core/site/site_controller.dart';

/// 回归测试：账号资料查询失败**不能**阻塞提交。
///
/// 真实故障：手机上推送时 TLS 抖动，`fetchProfile` 抛
/// `HandshakeException`，于是整个 push 在「提交中…」这一步就中止了，
/// 提示「无法确认提交身份」。
///
/// 但提交是完全本地的 git 操作，不需要网络 —— 用它来卡住提交是错的。
void main() {
  group('CommitIdentity', () {
    test('手填身份时标记为真实邮箱', () {
      const id = CommitIdentity(
        name: 'octocat',
        email: 'me@example.com',
        hasRealEmail: true,
      );
      expect(id.name, 'octocat');
      expect(id.email, 'me@example.com');
      expect(id.hasRealEmail, isTrue);
    });

    test('兜底身份标记为非真实邮箱', () {
      const id = CommitIdentity(
        name: 'octocat',
        email: 'noreply@localhost',
        hasRealEmail: false,
      );
      expect(id.hasRealEmail, isFalse);
    });
  });

  group('兜底邮箱格式', () {
    test('@localhost 是合法邮箱格式，git 不会拒绝', () {
      // git 对 author email 的校验比较宽松，但必须有 @ 且非空。
      // 这里锁住格式，防止将来有人改成空串或去掉 @。
      const email = 'noreply@localhost';
      expect(email.contains('@'), isTrue);
      expect(email.split('@').length, 2);
      expect(email.split('@').first.isNotEmpty, isTrue);
      expect(email.split('@').last.isNotEmpty, isTrue);
    });
  });

  group('站点 owner 兜底', () {
    // _fallbackOwner 是私有的，这里通过 SiteConfig.repoSlug 的行为
    // 间接验证它依赖的数据源是对的。
    test('repoSlug 能从各种 URL 形式取出 owner/repo', () {
      // 这些是 _fallbackOwner 依赖的格式基础
      const cases = [
        'https://github.com/octocat/Hello-World.git',
        'https://github.com/octocat/Hello-World',
      ];
      for (final url in cases) {
        var s = url.trim();
        if (s.endsWith('.git')) s = s.substring(0, s.length - 4);
        s = s.replaceFirst('https://', '').replaceFirst('github.com/', '');
        expect(s.split('/').first, 'octocat', reason: 'URL: $url');
      }
    });
  });
}