import 'package:flutter_test/flutter_test.dart';
import 'package:hugosugar/core/site/commit_message.dart';

void main() {
  group('commit message 生成', () {
    test('没有变更时给通用文案', () {
      expect(
        CommitMessage.suggest(const []),
        '更新站点内容',
      );
    });

    test('单篇文章用文件名做标题', () {
      expect(
        CommitMessage.suggest(
          ['content/posts/hello-world.md'],
        ),
        '更新文章：hello-world',
      );
    });

    test('去掉日期前缀', () {
      expect(
        CommitMessage.suggest(
          ['content/posts/20240501-hello.md'],
        ),
        '更新文章：hello',
      );
    });

    test('多篇（≤3）全部列出', () {
      final msg = CommitMessage.suggest([
        'content/posts/a.md',
        'content/posts/b.md',
      ]);
      expect(msg, '更新文章：a、b');
    });

    test('超过 3 篇时只列前两篇并给总数', () {
      final msg = CommitMessage.suggest([
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
        CommitMessage.suggest(['config.toml']),
        '更新 config.toml',
      );
      expect(
        CommitMessage.suggest(['a.txt', 'b.txt']),
        '更新 2 个文件',
      );
    });
  });
}