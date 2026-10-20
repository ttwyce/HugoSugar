import 'package:flutter_test/flutter_test.dart';
import 'package:hugosugar/core/settings/app_settings.dart';
import 'package:hugosugar/core/site/file_naming.dart';

void main() {
  final t = DateTime(2024, 5, 1, 8, 3, 9);

  group('跟随标题 fromTitle', () {
    test('中文标题直接用中文做文件名', () {
      // 这是用户实际反馈的场景：选了「跟随标题」却拿到时间戳，
      // 等于这个选项根本没生效。
      expect(
        buildFileSlug(
          title: '我的第一篇 Hugo 文章',
          style: FileNameStyle.fromTitle,
          now: t,
        ),
        '我的第一篇 Hugo 文章',
      );
    });

    test('纯中文标题不回退成时间戳', () {
      final slug = buildFileSlug(
        title: '手机写作',
        style: FileNameStyle.fromTitle,
        now: t,
      );
      expect(slug, '手机写作');
      expect(slug.contains('post-2024'), isFalse);
    });

    test('非法文件名字符被替换成空格', () {
      expect(
        buildFileSlug(
          title: 'a/b:c*d?e"f<g>h|i',
          style: FileNameStyle.fromTitle,
          now: t,
        ),
        'a b c d e f g h i',
      );
    });

    test('压缩连续空白并去掉首尾空白', () {
      expect(
        buildFileSlug(
          title: '  hello    world  ',
          style: FileNameStyle.fromTitle,
          now: t,
        ),
        'hello world',
      );
    });

    test('超长标题被截断', () {
      final slug = buildFileSlug(
        title: 'x' * 200,
        style: FileNameStyle.fromTitle,
        now: t,
      );
      expect(slug.length, lessThanOrEqualTo(60));
    });

    test('标题全为非法字符时有兜底值', () {
      final slug = buildFileSlug(
        title: '///???',
        style: FileNameStyle.fromTitle,
        now: t,
      );
      expect(slug, isNotEmpty);
      expect(slug.contains('/'), isFalse);
    });
  });

  group('时间戳 timestamp', () {
    test('格式为 post-年月日-时分秒', () {
      expect(
        buildFileSlug(
          title: '随便什么标题',
          style: FileNameStyle.timestamp,
          now: t,
        ),
        'post-20240501-080309',
      );
    });
  });

  group('日期 + 标题 dateAndTitle', () {
    test('ASCII 标题拼在日期后', () {
      expect(
        buildFileSlug(
          title: 'Hello World',
          style: FileNameStyle.dateAndTitle,
          now: t,
        ),
        '20240501-hello-world',
      );
    });

    test('中文标题退化为纯日期，不产生 20240501-.md', () {
      expect(
        buildFileSlug(
          title: '纯中文',
          style: FileNameStyle.dateAndTitle,
          now: t,
        ),
        '20240501',
      );
    });
  });

  group('边界', () {
    test('三种风格结果互不相同', () {
      final a = buildFileSlug(
        title: 'Hello',
        style: FileNameStyle.fromTitle,
        now: t,
      );
      final b = buildFileSlug(
        title: 'Hello',
        style: FileNameStyle.timestamp,
        now: t,
      );
      final c = buildFileSlug(
        title: 'Hello',
        style: FileNameStyle.dateAndTitle,
        now: t,
      );
      expect({a, b, c}.length, 3);
    });
  });
}