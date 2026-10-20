import 'package:flutter_test/flutter_test.dart';
import 'package:hugosugar/core/site/deploy_hook_service.dart';

void main() {
  group('DeployHook 校验', () {
    test('空地址被拒', () {
      expect(DeployHookService.validate(''), isNotNull);
      expect(DeployHookService.validate('   '), isNotNull);
    });

    test('http 被拒，只允许 https', () {
      final err = DeployHookService.validate('http://api.vercel.com/x');
      expect(err, contains('https'));
    });

    test('合法的 Vercel hook 通过', () {
      expect(
        DeployHookService.validate(
          'https://api.vercel.com/v1/integrations/deploy/prj_abc/xyz',
        ),
        isNull,
      );
    });

    test('合法的 Netlify hook 通过', () {
      expect(
        DeployHookService.validate(
          'https://hooks.netlify.com/build_hooks/abc123',
        ),
        isNull,
      );
    });

    test('localhost 被拒（SSRF）', () {
      expect(
        DeployHookService.validate('https://localhost/hook'),
        contains('内网'),
      );
    });

    test('127.0.0.1 被拒', () {
      expect(
        DeployHookService.validate('https://127.0.0.1/hook'),
        contains('内网'),
      );
    });

    test('10.x 私网被拒', () {
      expect(
        DeployHookService.validate('https://10.0.0.5/hook'),
        contains('内网'),
      );
    });

    test('192.168.x 私网被拒', () {
      expect(
        DeployHookService.validate('https://192.168.1.10/hook'),
        contains('内网'),
      );
    });

    test('172.16~31 私网被拒', () {
      expect(
        DeployHookService.validate('https://172.16.0.1/hook'),
        contains('内网'),
      );
      expect(
        DeployHookService.validate('https://172.31.5.5/hook'),
        contains('内网'),
      );
    });

    test('172.32 不在私网段内，应放行', () {
      expect(DeployHookService.validate('https://172.32.0.1/hook'), isNull);
    });

    test('169.254 链路本地被拒', () {
      expect(
        DeployHookService.validate('https://169.254.1.1/hook'),
        contains('内网'),
      );
    });

    test('.local 主机名被拒', () {
      expect(
        DeployHookService.validate('https://printer.local/hook'),
        contains('内网'),
      );
    });

    test('缺少域名被拒', () {
      expect(DeployHookService.validate('https:///hook'), isNotNull);
    });
  });

  group('commit message 生成', () {
    test('没有变更时给通用文案', () {
      expect(
        DeployHookService.suggestCommitMessage(const []),
        '更新站点内容',
      );
    });

    test('单篇文章用文件名做标题', () {
      expect(
        DeployHookService.suggestCommitMessage(
          ['content/posts/hello-world.md'],
        ),
        '更新文章：hello-world',
      );
    });

    test('去掉日期前缀', () {
      expect(
        DeployHookService.suggestCommitMessage(
          ['content/posts/20240501-hello.md'],
        ),
        '更新文章：hello',
      );
    });

    test('多篇（≤3）全部列出', () {
      final msg = DeployHookService.suggestCommitMessage([
        'content/posts/a.md',
        'content/posts/b.md',
      ]);
      expect(msg, '更新文章：a、b');
    });

    test('超过 3 篇时只列前两篇并给总数', () {
      final msg = DeployHookService.suggestCommitMessage([
        'content/posts/a.md',
        'content/posts/b.md',
        'content/posts/c.md',
        'content/posts/d.md',
      ]);
      expect(msg, contains('等 4 篇'));
      expect(msg, contains('a、b'));
    });

    test('非 md 文件走数量文案', () {
      expect(
        DeployHookService.suggestCommitMessage(['config.toml']),
        '更新 config.toml',
      );
      expect(
        DeployHookService.suggestCommitMessage(['a.txt', 'b.txt']),
        '更新 2 个文件',
      );
    });
  });
}