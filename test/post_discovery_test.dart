import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hugosugar/core/fs/site_storage.dart';
import 'package:hugosugar/core/post/front_matter.dart';
import 'package:path/path.dart' as p;

/// 端到端：在真实临时目录里造一个 Hugo 结构的站点，
/// 验证递归发现 + Front Matter 解析整条链路。
void main() {
  test('真实目录结构下的文章发现与解析', () async {
    final tmp = Directory.systemTemp.createTempSync('hugo_e2e');
    final content = Directory(p.join(tmp.path, 'content/posts'));

    // 造一个典型的 Hugo 结构：含子目录、含 TOML、含无 Front Matter
    Directory(p.join(content.path, 'tech')).createSync(recursive: true);

    File(p.join(content.path, 'hello.md')).writeAsStringSync('''---
title: 你好 Hugo
date: 2024-05-01
categories: [随笔]
tags: [hello]
draft: false
---

正文内容。
''');

    File(p.join(content.path, 'tech', 'flutter.md')).writeAsStringSync('''---
title: Flutter 状态管理
date: 2024-06-15
categories: [技术]
tags: [flutter, dart]
draft: true
---

技术文章正文。
''');

    File(p.join(content.path, 'tech', 'toml-post.md')).writeAsStringSync('''+++
title = "TOML 文章"
date = "2024-07-01"
categories = ["技术"]
+++

TOML 正文。
''');

    File(p.join(content.path, 'plain.md'))
        .writeAsStringSync('没有 Front Matter 的文章。\n');

    // 干扰文件：非 md 应被忽略
    File(p.join(content.path, 'draft.txt')).writeAsStringSync('x');

    final storage = _TempStorage(tmp);
    final paths = await storage.listFilesRecursive(
      'content/posts',
      extension: '.md',
    );

    // 递归必须找到 3 层以下 + 根目录，共 4 个 md
    expect(paths.length, 4, reason: '实际找到：$paths');

    final docs = <PostDocument>[];
    for (final rel in paths) {
      final raw = await storage.readString(rel);
      docs.add(
        FrontMatter.parse(
          relativePath: rel,
          fileName: p.basename(rel),
          content: raw,
        ),
      );
    }

    final byTitle = {for (final d in docs) d.title: d};

    // 子目录里的文章被正确识别
    expect(byTitle.containsKey('Flutter 状态管理'), isTrue);
    expect(byTitle['Flutter 状态管理']!.draft, isTrue);
    expect(byTitle['Flutter 状态管理']!.folderName, 'tech');

    // TOML 文章
    expect(byTitle.containsKey('TOML 文章'), isTrue);
    expect(byTitle['TOML 文章']!.format, 'toml');

    // 无 Front Matter 的回退到文件名
    expect(byTitle.containsKey('Plain'), isTrue);

    // 分类聚合
    final cats = <String>{};
    for (final d in docs) {
      cats.addAll(d.categories);
    }
    expect(cats, containsAll(['随笔', '技术']));

    tmp.deleteSync(recursive: true);
  });
}

/// 最小 storage 实现，只用于测试
class _TempStorage implements SiteStorage {
  _TempStorage(this.root);

  @override
  final Directory root;

  @override
  Future<bool> get exists async => root.exists();

  @override
  Future<bool> existsPath(String rel) async {
    if (File(p.join(root.path, rel)).existsSync()) return true;
    return Directory(p.join(root.path, rel)).existsSync();
  }

  @override
  Future<String> readString(String rel) =>
      File(p.join(root.path, rel)).readAsString();

  @override
  Future<void> writeString(String rel, String content) async {
    final f = File(p.join(root.path, rel));
    f.parent.createSync(recursive: true);
    await f.writeAsString(content);
  }

  @override
  Future<void> delete(String rel, {bool recursive = false}) async {
    final f = File(p.join(root.path, rel));
    if (f.existsSync()) {
      await f.delete();
    }
  }

  @override
  Future<List<String>> listFilesRecursive(
    String rel, {
    String extension = '',
  }) async {
    final dir = Directory(p.join(root.path, rel));
    if (!dir.existsSync()) return const [];
    final out = <String>[];
    for (final e in dir.listSync(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      final name = p.basename(e.path);
      if (name.startsWith('.')) continue;
      if (extension.isNotEmpty && !name.endsWith(extension)) continue;
      out.add(p.relative(e.path, from: root.path));
    }
    out.sort();
    return out;
  }
}