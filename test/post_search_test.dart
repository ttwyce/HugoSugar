import 'package:flutter_test/flutter_test.dart';
import 'package:hugosugar/core/post/front_matter.dart';
import 'package:hugosugar/core/post/post_search.dart';

PostDocument post({
  String title = '标题',
  String body = '',
  String description = '',
  List<String> categories = const [],
  List<String> tags = const [],
  String path = 'content/posts/a.md',
}) {
  return PostDocument(
    relativePath: path,
    fileName: path.split('/').last,
    title: title,
    frontMatter: const {},
    body: body,
    rawFrontMatter: '',
    format: 'yaml',
    categories: categories,
    tags: tags,
    description: description,
  );
}

void main() {
  group('PostSearch.matches', () {
    test('空查询命中一切', () {
      final s = PostSearch('');
      expect(s.matches(post(title: '任意')), isTrue);
      expect(s.isEmpty, isTrue);
    });

    test('命中文档标题，大小写不敏感', () {
      final s = PostSearch('flutter');
      expect(s.matches(post(title: 'Flutter 状态管理')), isTrue);
    });

    test('命中正文', () {
      final s = PostSearch('isolate');
      expect(
        s.matches(post(body: '把所有耗时计算挪到后台 isolate 里')),
        isTrue,
      );
    });

    test('命中路径', () {
      final s = PostSearch('2026-11');
      expect(
        s.matches(post(path: 'content/posts/2026-11-note.md')),
        isTrue,
      );
    });

    test('命中标签与分类', () {
      expect(
        PostSearch('dart').matches(post(tags: const ['Dart', 'hugo'])),
        isTrue,
      );
      expect(
        PostSearch('技术').matches(post(categories: const ['技术'])),
        isTrue,
      );
    });

    test('命中简介', () {
      expect(
        PostSearch('备份')
            .matches(post(description: 'WebDAV 加密备份的实现取舍')),
        isTrue,
      );
    });

    test('完全不相关时不命中', () {
      final s = PostSearch('kubernetes');
      expect(
        s.matches(post(title: 'Hugo 写作', body: '手机端写文章')),
        isFalse,
      );
    });

    test('查询未归一化时会漏——调用方必须先转小写', () {
      // 这条是给「谁改调用方式」的人看的护栏：PostSearch 不做归一化，
      // 因为同一个查询词会被反复复用，归一化应该在进入时做一次。
      expect(PostSearch('FLUTTER').matches(post(title: 'flutter')), isFalse);
    });
  });

  group('PostSearch.snippet', () {
    test('正文未命中时返回 null', () {
      final s = PostSearch('rust');
      expect(s.snippet(post(title: 'rust', body: 'go 也不错')), isNull);
    });

    test('截取命中词前后的上下文', () {
      final s = PostSearch('加密');
      final text = '备份链路是先在手机上 gzip 压缩再用口令加密最后上传到服务器';
      final out = s.snippet(post(body: text));
      expect(out, isNotNull);
      expect(out!.contains('加密'), isTrue);
    });

    test('换行被压缩成空格', () {
      final s = PostSearch('第二行');
      final out = s.snippet(post(body: '第一行\n\n第二行\n第三行'));
      expect(out, isNotNull);
      expect(out!.contains('\n'), isFalse);
      expect(out.contains('第二行'), isTrue);
    });

    test('开头命中时不加前省略号', () {
      final s = PostSearch('开头');
      final out = s.snippet(post(body: '开头就在这里'));
      expect(out!.startsWith('…'), isFalse);
    });

    test('结尾命中时不加后省略号', () {
      final s = PostSearch('结尾');
      final out = s.snippet(post(body: '这一篇的结尾'));
      expect(out!.endsWith('…'), isFalse);
    });

    test('中段命中时两侧都有省略号', () {
      final s = PostSearch('中段');
      // 后半段必须比 after 窗口长，否则会一直截到结尾、没有尾巴省略号
      final body = '${'前' * 40}中段${'后' * 80}';
      final out = s.snippet(post(body: body))!;
      expect(out.startsWith('…'), isTrue);
      expect(out.endsWith('…'), isTrue);
    });
  });
}
