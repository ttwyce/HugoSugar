import 'package:flutter_test/flutter_test.dart';
import 'package:hugosugar/core/post/front_matter.dart';

PostDocument parse(String content, {String name = 'test.md'}) {
  return FrontMatter.parse(
    relativePath: 'content/posts/$name',
    fileName: name,
    content: content,
  );
}

void main() {
  group('YAML Front Matter', () {
    test('解析 title / date / draft / categories / tags', () {
      final doc = parse('''
---
title: 我的第一篇文章
date: 2024-05-01
draft: true
categories: [技术, 随笔]
tags:
  - flutter
  - hugo
description: 一段简介
---

正文第一段。
''');

      expect(doc.title, '我的第一篇文章');
      expect(doc.draft, isTrue);
      expect(doc.categories, ['技术', '随笔']);
      expect(doc.tags, ['flutter', 'hugo']);
      expect(doc.description, '一段简介');
      expect(doc.date?.year, 2024);
      expect(doc.date?.month, 5);
      expect(doc.date?.day, 1);
      expect(doc.body.trim(), '正文第一段。');
      expect(doc.format, 'yaml');
    });

    test('title 缺失时回退文件名并去掉日期前缀', () {
      final doc = parse('''
---
date: 2024-01-01
---
正文
''', name: '2024-01-01-hello-world.md');

      expect(doc.title, 'Hello world');
    });

    test('中文文件名不做大小写变换', () {
      final doc = parse('---\ndate: 2024-01-01\n---\n正文',
          name: '中文标题.md');
      expect(doc.title, '中文标题');
    });

    test('结束标记用 ... 也能识别', () {
      final doc = parse('''
---
title: 用点结尾
...
正文在这里
''');
      expect(doc.title, '用点结尾');
      expect(doc.body.trim(), '正文在这里');
    });

    test('正文里的 --- 水平线不会被误判为结束', () {
      final doc = parse('''
---
title: 有分割线
---

第一段

---

第二段
''');
      expect(doc.title, '有分割线');
      expect(doc.body.contains('第一段'), isTrue);
      expect(doc.body.contains('第二段'), isTrue);
    });

    test('带时区的日期能解析', () {
      final doc = parse('''
---
title: t
date: 2024-05-01T10:20:30+08:00
---
x
''');
      expect(doc.date, isNotNull);
      expect(doc.date!.year, 2024);
    });

    test('空格分隔的日期时间能解析', () {
      final doc = parse('''
---
title: t
date: 2024-05-01 10:20:30
---
x
''');
      expect(doc.date, isNotNull);
      expect(doc.date!.hour, 10);
    });

    test('publishDate 也是合法键', () {
      final doc = parse('''
---
title: t
publishDate: 2024-03-03
---
x
''');
      expect(doc.date?.month, 3);
    });

    test('引号包裹的 title 会去掉引号', () {
      final doc = parse('''
---
title: "带引号的标题"
---
x
''');
      expect(doc.title, '带引号的标题');
    });

    test('标题里有冒号不会被截断', () {
      final doc = parse('''
---
title: "Dart：从入门到放弃"
---
x
''');
      expect(doc.title, 'Dart：从入门到放弃');
    });

    test('categories 写成逗号字符串也能解析', () {
      final doc = parse('''
---
title: t
categories: 技术, 随笔
---
x
''');
      expect(doc.categories, ['技术', '随笔']);
    });

    test('单数 category / tag 也支持', () {
      final doc = parse('''
---
title: t
category: 技术
tag: flutter
---
x
''');
      expect(doc.categories, ['技术']);
      expect(doc.tags, ['flutter']);
    });
  });

  group('TOML Front Matter', () {
    test('解析 +++ 包裹的 TOML', () {
      final doc = parse('''
+++
title = "TOML 标题"
date = "2024-06-01"
draft = false
categories = ["技术"]
tags = ["go", "hugo"]
+++

TOML 正文
''');

      expect(doc.title, 'TOML 标题');
      expect(doc.draft, isFalse);
      expect(doc.categories, ['技术']);
      expect(doc.tags, ['go', 'hugo']);
      expect(doc.body.trim(), 'TOML 正文');
      expect(doc.format, 'toml');
    });
  });

  group('异常与边界', () {
    test('没有 Front Matter 时整篇都是正文', () {
      final doc = parse('# 只有正文\n\n内容');
      expect(doc.format, 'none');
      expect(doc.body, '# 只有正文\n\n内容');
      expect(doc.title, 'Test'); // 文件名 test.md
    });

    test('YAML 语法错误时退化成逐行解析，不丢标题', () {
      // 故意写坏的 YAML：数组缩进混乱
      final doc = parse('''
---
title: 坏掉的 YAML
tags: [a,
date: 2024-01-01
---

正文
''');
      // 至少不该崩，且正文还在
      expect(doc.body.contains('正文'), isTrue);
      expect(doc.title, isNotEmpty);
    });

    test('BOM 开头也能正确解析', () {
      final doc = parse('\uFEFF---\ntitle: 带 BOM\n---\n正文');
      expect(doc.title, '带 BOM');
    });

    test('空 Front Matter 不报错', () {
      final doc = parse('---\n---\n正文');
      expect(doc.title, 'Test');
      expect(doc.body.trim(), '正文');
    });

    test('空文件不报错', () {
      final doc = parse('');
      expect(doc.title, 'Test');
      expect(doc.body, '');
    });
  });

  group('excerpt', () {
    test('优先用 description', () {
      final doc = parse('''
---
title: t
description: 这是描述
---
正文很长很长
''');
      expect(doc.excerpt, '这是描述');
    });

    test('没有 description 时从正文提取并去掉 Markdown 标记', () {
      final doc = parse('''
---
title: t
---
# 大标题

这是**加粗**的正文，还有[链接](http://a.com)。
''');
      final e = doc.excerpt;
      // 明确断言期望值，失败时能看到实际内容
      expect(e, '大标题 这是加粗的正文，还有链接。',
          reason: '实际摘要为：[$e]');
    });

    test('代码块内容不进摘要', () {
      final doc = parse('''
---
title: t
---
```dart
这个不应该出现();
```

后面才是正文
''');
      final e = doc.excerpt;
      expect(e.contains('这个不应该出现'), isFalse, reason: '实际：[$e]');
      expect(e.contains('后面才是正文'), isTrue, reason: '实际：[$e]');
    });

    test('过长会截断', () {
      final doc = parse('---\ntitle: t\n---\n${'长' * 200}');
      expect(doc.excerpt.length <= 81, isTrue);
      expect(doc.excerpt.endsWith('…'), isTrue);
    });
  });

  group('titleFromFileName', () {
    test('连字符转空格并首字母大写', () {
      expect(
        FrontMatter.titleFromFileName('hello-world-post.md'),
        'Hello world post',
      );
    });

    test('下划线也处理', () {
      expect(FrontMatter.titleFromFileName('my_note.md'), 'My note');
    });

    test('去掉 20240501 形式前缀', () {
      expect(
        FrontMatter.titleFromFileName('20240501-daily.md'),
        'Daily',
      );
    });
  });

  group('folderName', () {
    test('取父目录名', () {
      final doc = FrontMatter.parse(
        relativePath: 'content/posts/tech/a.md',
        fileName: 'a.md',
        content: '---\ntitle: t\n---\nx',
      );
      expect(doc.folderName, 'tech');
    });
  });
}