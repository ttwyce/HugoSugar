import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hugosugar/core/note/note.dart';
import 'package:hugosugar/core/note/note_store.dart';
import 'package:path/path.dart' as p;

/// 备份合并规则测试。
///
/// 用 openAt 直接指定临时路径，绕开 path_provider，
/// 这样不需要在测试里 mock 平台通道。
void main() {
  late Directory tmp;
  late NoteStore store;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('hs_merge_');
    store = await NoteStore.openAt(p.join(tmp.path, 'notes.json'));
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Note note(String id, String content, DateTime updatedAt) => Note(
        id: id,
        title: '',
        content: content,
        createdAt: updatedAt,
        updatedAt: updatedAt,
      );

  final t0 = DateTime(2026, 1, 1, 10);
  final t1 = DateTime(2026, 1, 2, 10);
  final t2 = DateTime(2026, 1, 3, 10);

  test('备份里独有的想法会被加入', () async {
    await store.create(title: '本地', content: '本地内容');

    final stats = await store.mergeBackup(
      notes: [note('remote_1', '来自备份', t1)],
      categories: const [],
    );

    expect(stats.added, 1);
    expect(stats.updated, 0);
    expect(store.byId('remote_1')?.content, '来自备份');
  });

  test('同一条笔记取较新的版本', () async {
    await store.mergeBackup(
      notes: [note('n1', '旧内容', t0)],
      categories: const [],
    );

    final stats = await store.mergeBackup(
      notes: [note('n1', '新内容', t2)],
      categories: const [],
    );

    expect(stats.updated, 1);
    expect(store.byId('n1')?.content, '新内容');
  });

  test('本地更新时不会被备份覆盖', () async {
    await store.mergeBackup(
      notes: [note('n2', '本地较新', t2)],
      categories: const [],
    );

    final stats = await store.mergeBackup(
      notes: [note('n2', '备份较旧', t0)],
      categories: const [],
    );

    expect(stats.kept, 1);
    expect(store.byId('n2')?.content, '本地较新');
  });

  test('分类按 id 去重', () async {
    final existing = await store.createCategory('已有分类');

    final stats = await store.mergeBackup(
      notes: const [],
      categories: [
        NoteCategory(id: existing.id, name: '改名也不应重复', order: 0),
        const NoteCategory(id: 'cat_remote', name: '云端分类', order: 1),
      ],
    );

    expect(stats.categoriesAdded, 1);
    expect(store.categories.length, 2);
    expect(store.categoryById('cat_remote')?.name, '云端分类');
  });

  test('空 id 的脏数据被跳过', () async {
    final stats = await store.mergeBackup(
      notes: [note('', '没有 id', t1)],
      categories: const [],
    );

    expect(stats.added, 0);
    expect(store.all.length, 0);
  });

  test('合并结果会落盘，重新打开仍在', () async {
    await store.mergeBackup(
      notes: [note('remote_persist', '持久化', t1)],
      categories: const [],
    );

    final reopened = await NoteStore.openAt(p.join(tmp.path, 'notes.json'));
    expect(reopened.byId('remote_persist')?.content, '持久化');
  });
}
