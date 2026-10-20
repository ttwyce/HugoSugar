import 'package:flutter_test/flutter_test.dart';
import 'package:hugosugar/core/post/front_matter.dart';

/// 序列化 → 再解析，验证往返一致性。
///
/// 这是整个写回链路的护栏：只要往返不丢信息，
/// 用户点保存就不会破坏自己的文章。
PostDocument roundTrip(String original) {
  final doc = FrontMatter.parse(
    relativePath: 'content/posts/t.md',
    fileName: 't.md',
    content: original,
  );
  final rebuilt = doc.serialize(title: doc.title, body: doc.body);
  return FrontMatter.parse(
    relativePath: 'content/posts/t.md',
    fileName: 't.md',
    content: rebuilt,
  );
}

void main() {
  group('往返一致性', () {
    test('YAML 基本字段往返不丢', () {
      final doc = roundTrip('''---
title: 我的文章
date: 2024-05-01 10:20:30
draft: true
categories: [技术, 随笔]
tags: [flutter, hugo]
description: 一段简介
---

正文内容。
''');
      expect(doc.title, '我的文章');
      expect(doc.draft, isTrue);
      expect(doc.categories, ['技术', '随笔']);
      expect(doc.tags, ['flutter', 'hugo']);
      expect(doc.description, '一段简介');
      expect(doc.date?.year, 2024);
      expect(doc.date?.hour, 10);
      expect(doc.body.trim(), '正文内容。');
    });

    test('TOML 格式往返保持 +++ 分隔符', () {
      final doc = roundTrip('''+++
title = "TOML 标题"
date = "2024-06-01"
draft = false
categories = ["技术"]
tags = ["go"]
+++

TOML 正文。
''');
      expect(doc.format, 'toml');
      expect(doc.title, 'TOML 标题');
      expect(doc.tags, ['go']);
      expect(doc.body.trim(), 'TOML 正文。');
    });
  });

  group('保留未知字段（关键）', () {
    test('author / series / aliases 不丢', () {
      final doc = roundTrip('''---
title: 有自定义字段
author: 张三
series: 深入 Flutter
aliases: [/old-url, /another]
cover: /images/cover.png
---

正文。
''');
      expect(doc.frontMatter['author'], '张三');
      expect(doc.frontMatter['series'], '深入 Flutter');
      expect(doc.frontMatter['aliases'], ['/old-url', '/another']);
      expect(doc.frontMatter['cover'], '/images/cover.png');
    });

    test('嵌套 map 不丢', () {
      final doc = roundTrip('''---
title: 嵌套
sitemap:
  priority: 0.8
  changefreq: weekly
---

正文。
''');
      final sitemap = doc.frontMatter['sitemap'];
      expect(sitemap, isA<Map>());
      expect((sitemap as Map)['priority'].toString(), '0.8');
    });

    test('lastmod 等日期字段不丢', () {
      final doc = roundTrip('''---
title: t
lastmod: 2024-07-01
---

正文。
''');
      expect(doc.frontMatter['lastmod'], isNotNull);
    });
  });

  group('特殊字符转义', () {
    test('title 含冒号会加引号并能解析回来', () {
      final doc = roundTrip('''---
title: t
---

x
''');
      // 直接用 builder 生成带冒号的标题
      final built = FrontMatterBuilder.build(
        original: const {},
        format: 'yaml',
        title: 'Dart: 从入门到放弃',
        body: '正文',
        date: DateTime(2024, 1, 1),
      );
      // 生成的文本必须能被自己解析回来
      final parsed = FrontMatter.parse(
        relativePath: 'content/posts/a.md',
        fileName: 'a.md',
        content: built,
      );
      expect(parsed.title, 'Dart: 从入门到放弃');
      expect(doc.title, 't');
    });

    test('title 以 # 开头会加引号', () {
      final built = FrontMatterBuilder.build(
        original: const {},
        format: 'yaml',
        title: '#这不是标题',
        body: 'x',
        date: DateTime(2024, 1, 1),
      );
      final parsed = FrontMatter.parse(
        relativePath: 'content/posts/a.md',
        fileName: 'a.md',
        content: built,
      );
      expect(parsed.title, '#这不是标题');
    });

    test('title 含双引号会转义', () {
      final built = FrontMatterBuilder.build(
        original: const {},
        format: 'yaml',
        title: '他说"你好"',
        body: 'x',
        date: DateTime(2024, 1, 1),
      );
      final parsed = FrontMatter.parse(
        relativePath: 'content/posts/a.md',
        fileName: 'a.md',
        content: built,
      );
      expect(parsed.title, '他说"你好"');
    });

    test('中文标题不需要引号', () {
      final built = FrontMatterBuilder.build(
        original: const {},
        format: 'yaml',
        title: '纯中文标题',
        body: 'x',
        date: DateTime(2024, 1, 1),
      );
      expect(built.contains('title: 纯中文标题'), isTrue);
    });

    test('看起来像布尔的 title 会加引号', () {
      final built = FrontMatterBuilder.build(
        original: const {},
        format: 'yaml',
        title: 'true',
        body: 'x',
        date: DateTime(2024, 1, 1),
      );
      final parsed = FrontMatter.parse(
        relativePath: 'content/posts/a.md',
        fileName: 'a.md',
        content: built,
      );
      // 不加引号时 YAML 会解析成 bool，title 就丢了
      expect(parsed.title, 'true');
    });
  });

  group('createNew', () {
    test('生成可解析的新文章', () {
      final text = FrontMatterBuilder.createNew(
        title: '新文章',
        categories: ['技术'],
        tags: ['flutter'],
        description: '简介',
        date: DateTime(2024, 3, 15, 9, 30),
      );
      final doc = FrontMatter.parse(
        relativePath: 'content/posts/new.md',
        fileName: 'new.md',
        content: text,
      );
      expect(doc.title, '新文章');
      expect(doc.draft, isTrue); // 默认草稿
      expect(doc.categories, ['技术']);
      expect(doc.tags, ['flutter']);
      expect(doc.description, '简介');
      expect(doc.date?.month, 3);
      expect(doc.body.trim(), isEmpty);
    });

    test('无分类无标签时不写空数组', () {
      final text = FrontMatterBuilder.createNew(title: '简单');
      expect(text.contains('categories'), isFalse);
      expect(text.contains('tags'), isFalse);
    });
  });

  group('无 Front Matter 的文件', () {
    test('编辑后仍然不加上 Front Matter（除非有内容）', () {
      final doc = FrontMatter.parse(
        relativePath: 'content/posts/plain.md',
        fileName: 'plain.md',
        content: '纯正文，没有头部。\n',
      );
      expect(doc.format, 'none');
      // serialize 会带上 title，所以此时应生成头部 —— 这是预期行为：
      // 用户编辑后文件会获得规范的 Front Matter。
      final rebuilt = doc.serialize(title: '标题', body: doc.body);
      expect(rebuilt.startsWith('---'), isTrue);
    });
  });

  group('日期格式', () {
    test('写成可读的空格分隔形式', () {
      final text = FrontMatterBuilder.build(
        original: const {},
        format: 'yaml',
        title: 't',
        body: 'x',
        date: DateTime(2024, 5, 1, 8, 3, 9),
      );
      expect(text.contains('2024-05-01 08:03:09'), isTrue);
    });
  });

  group('编辑元信息不丢字段', () {
    const original = '''
title: 原标题
date: 2024-05-01 08:03:09
draft: true
categories: [技术]
tags: [flutter, hugo]
description: 原简介
author: 张三
series: 深入 Flutter
weight: 3
''';

    // 注意：这个辅助函数只用于**解析手写的原始 FM 文本**。
    // FrontMatterBuilder.build() 返回的是「带 --- 分隔符的完整文件」，
    // 不能塞进这里，否则会二次包裹导致解析失败。
    Map<String, Object?> parseRaw(String text) => FrontMatter.parse(
          relativePath: 'content/posts/a.md',
          fileName: 'a.md',
          content: '---\n$text---\n\n正文',
        ).frontMatter;

    /// 解析 build() 的输出（已是完整文件内容）
    Map<String, Object?> parseBuilt(String fullFile) => FrontMatter.parse(
          relativePath: 'content/posts/a.md',
          fileName: 'a.md',
          content: fullFile,
        ).frontMatter;

    test('改分类和标签后，author / series / weight 仍在', () {
      final fm = parseRaw(original);
      final out = FrontMatterBuilder.build(
        original: fm,
        format: 'yaml',
        title: '原标题',
        body: '正文',
        categories: ['生活'],
        tags: ['随笔'],
      );
      final again = parseBuilt(out);
      expect(again['author'], '张三');
      expect(again['series'], '深入 Flutter');
      expect(again['weight'], 3);
      expect(again['categories'], ['生活']);
      expect(again['tags'], ['随笔']);
    });

    test('改日期后写回新日期，旧日期不残留', () {
      final fm = parseRaw(original);
      final out = FrontMatterBuilder.build(
        original: fm,
        format: 'yaml',
        title: '原标题',
        body: '正文',
        date: DateTime(2025, 1, 2, 3, 4, 5),
      );
      expect(out.contains('2025-01-02 03:04:05'), isTrue);
      expect(out.contains('2024-05-01'), isFalse);
    });

    test('简介传空串时删除 description 键', () {
      final fm = parseRaw(original);
      final out = FrontMatterBuilder.build(
        original: fm,
        format: 'yaml',
        title: '原标题',
        body: '正文',
        description: '',
      );
      final again = parseBuilt(out);
      expect(again.containsKey('description'), isFalse);
    });

    test('草稿开关切换后状态正确', () {
      final fm = parseRaw(original);
      final out = FrontMatterBuilder.build(
        original: fm,
        format: 'yaml',
        title: '原标题',
        body: '正文',
        draft: false,
      );
      expect(parseBuilt(out)['draft'], isFalse);
    });

    test('清空分类时不写空数组，而是去掉该键', () {
      final fm = parseRaw(original);
      final out = FrontMatterBuilder.build(
        original: fm,
        format: 'yaml',
        title: '原标题',
        body: '正文',
        categories: const [],
      );
      expect(parseBuilt(out).containsKey('categories'), isFalse);
    });

    test('TOML 格式同样能保留自定义字段', () {
      const toml = '''
title = "原标题"
draft = true
categories = ["技术"]
author = "张三"
''';
      final doc = FrontMatter.parse(
        relativePath: 'content/posts/a.md',
        fileName: 'a.md',
        content: '+++\n$toml+++\n\n正文',
      );
      final out = FrontMatterBuilder.build(
        original: doc.frontMatter,
        format: 'toml',
        title: '原标题',
        body: '正文',
        draft: false,
      );
      expect(out.startsWith('+++'), isTrue);
      expect(out.contains('author = "张三"'), isTrue);
    });
  });
}