import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hugosugar/core/site/post_trash_store.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;
  late String file;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('hs_trash_test');
    file = p.join(dir.path, 'trash.json');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  TrashedPost mk(String path, {String title = '', String content = ''}) =>
      TrashedPost(
        relativePath: path,
        title: title,
        content: content.isEmpty ? 'raw-$path' : content,
        deletedAt: DateTime(2024, 1, 1),
      );

  test('空的回收站', () async {
    final s = await PostTrashStore.openAt(file);
    expect(s.count, 0);
    expect(s.items, isEmpty);
  });

  test('加入后可读回，且保存了完整原文', () async {
    final s = await PostTrashStore.openAt(file);
    await s.add(mk('content/posts/a.md', title: 'A', content: '---\ntitle: A\ncover: x.png\n---\n正文'));

    // 重新打开，验证落盘
    final s2 = await PostTrashStore.openAt(file);
    expect(s2.count, 1);
    expect(s2.items.first.title, 'A');
    // 关键：未知 Front Matter 键必须原样保留，否则恢复会丢用户配置
    expect(s2.items.first.content, contains('cover: x.png'));
    expect(s2.items.first.content, contains('正文'));
  });

  test('同一路径重复加入只保留一条', () async {
    final s = await PostTrashStore.openAt(file);
    await s.add(mk('a.md', title: '第一次'));
    await s.add(mk('a.md', title: '第二次'));
    expect(s.count, 1);
    expect(s.items.first.title, '第二次');
  });

  test('remove 返回被删项并从列表消失', () async {
    final s = await PostTrashStore.openAt(file);
    await s.add(mk('a.md'));
    await s.add(mk('b.md'));

    final removed = await s.remove('a.md');
    expect(removed, isNotNull);
    expect(removed!.relativePath, 'a.md');
    expect(s.count, 1);
    expect(s.contains('a.md'), isFalse);
    expect(s.contains('b.md'), isTrue);
  });

  test('remove 不存在的路径返回 null', () async {
    final s = await PostTrashStore.openAt(file);
    expect(await s.remove('nope.md'), isNull);
  });

  test('按删除时间倒序', () async {
    final s = await PostTrashStore.openAt(file);
    await s.add(TrashedPost(
      relativePath: 'old.md',
      title: 'old',
      content: '',
      deletedAt: DateTime(2024, 1, 1),
    ));
    await s.add(TrashedPost(
      relativePath: 'new.md',
      title: 'new',
      content: '',
      deletedAt: DateTime(2024, 6, 1),
    ));
    expect(s.items.first.relativePath, 'new.md');
  });

  test('clear 清空并返回条数', () async {
    final s = await PostTrashStore.openAt(file);
    await s.add(mk('a.md'));
    await s.add(mk('b.md'));
    expect(await s.clear(), 2);
    expect(s.count, 0);
  });

  test('文件损坏时当作空回收站，不抛异常', () async {
    File(file).writeAsStringSync('{ this is not json');
    final s = await PostTrashStore.openAt(file);
    expect(s.count, 0);
    // 仍然可写
    await s.add(mk('a.md'));
    expect(s.count, 1);
  });
}