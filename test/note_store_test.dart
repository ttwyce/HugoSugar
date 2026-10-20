import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hugosugar/core/note/note.dart';
import 'package:hugosugar/core/note/note_store.dart';
import 'package:path/path.dart' as p;

/// 每个测试用独立的临时文件，互不干扰，也不碰真实 App 目录
Future<(NoteStore, Directory)> newStore() async {
  final dir = Directory.systemTemp.createTempSync('hs_notes');
  final store = await NoteStore.openAt(p.join(dir.path, 'notes.json'));
  return (store, dir);
}

void main() {
  group('基本 CRUD', () {
    test('新建笔记能读回来', () async {
      final (store, dir) = await newStore();
      final note = await store.create(title: '标题', content: '正文');

      expect(note.id, isNotEmpty);
      expect(store.byId(note.id)?.title, '标题');
      expect(store.active.length, 1);

      dir.deleteSync(recursive: true);
    });

    test('更新会刷新 updatedAt', () async {
      final (store, dir) = await newStore();
      final note = await store.create(title: 'a', content: 'b');
      // 让时间明显推进
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final updated = await store.update(note.copyWith(content: '改过'));

      expect(updated!.content, '改过');
      expect(
        updated.updatedAt.isAfter(note.updatedAt),
        isTrue,
        reason: '更新时间应晚于创建时间',
      );

      dir.deleteSync(recursive: true);
    });

    test('更新不存在的 id 返回 null 而不抛', () async {
      final (store, dir) = await newStore();
      final ghost = Note(
        id: 'not_exist',
        title: 'x',
        content: '',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(await store.update(ghost), isNull);
      dir.deleteSync(recursive: true);
    });
  });

  group('回收站', () {
    test('删除进回收站，不在 active 里', () async {
      final (store, dir) = await newStore();
      final note = await store.create(title: '待删', content: 'x');

      expect(await store.trash(note.id), isTrue);
      expect(store.active.where((n) => n.id == note.id), isEmpty);
      expect(store.trashed.where((n) => n.id == note.id).length, 1);
      expect(store.byId(note.id)?.isDeleted, isTrue);

      dir.deleteSync(recursive: true);
    });

    test('删除会把置顶取消掉', () async {
      final (store, dir) = await newStore();
      final note = await store.create(title: 'p', content: 'x', pinned: true);
      await store.trash(note.id);

      // 回收站里的笔记不该再注入 AI 上下文
      expect(store.pinned.where((n) => n.id == note.id), isEmpty);

      dir.deleteSync(recursive: true);
    });

    test('恢复后回到 active', () async {
      final (store, dir) = await newStore();
      final note = await store.create(title: 'r', content: 'x');
      await store.trash(note.id);
      expect(await store.restore(note.id), isTrue);

      expect(store.active.where((n) => n.id == note.id).length, 1);
      expect(store.trashed.where((n) => n.id == note.id), isEmpty);

      dir.deleteSync(recursive: true);
    });

    test('永久删除后彻底消失', () async {
      final (store, dir) = await newStore();
      final note = await store.create(title: 'x', content: 'y');
      await store.trash(note.id);
      expect(await store.purge(note.id), isTrue);
      expect(store.byId(note.id), isNull);

      dir.deleteSync(recursive: true);
    });

    test('清空回收站只删已删除的', () async {
      final (store, dir) = await newStore();
      final a = await store.create(title: 'a', content: '');
      final b = await store.create(title: 'b', content: '');
      await store.trash(b.id);

      final removed = await store.purgeAllTrashed();
      expect(removed, 1);
      expect(store.byId(a.id), isNotNull);
      expect(store.byId(b.id), isNull);

      dir.deleteSync(recursive: true);
    });
  });

  group('置顶', () {
    test('togglePin 来回切换', () async {
      final (store, dir) = await newStore();
      final note = await store.create(title: 'p', content: '');

      await store.togglePin(note.id);
      expect(store.byId(note.id)!.pinned, isTrue);
      expect(store.pinned.length, 1);

      await store.togglePin(note.id);
      expect(store.byId(note.id)!.pinned, isFalse);
      expect(store.pinned, isEmpty);

      dir.deleteSync(recursive: true);
    });
  });

  group('分类', () {
    test('新建分类并归类笔记', () async {
      final (store, dir) = await newStore();
      final cat = await store.createCategory('技术');
      final note = await store.create(title: 'n', content: '', categoryId: cat.id);

      expect(store.categoryById(cat.id)?.name, '技术');
      expect(store.countInCategory(cat.id), 1);
      expect(store.inCategory(cat.id).map((n) => n.id), contains(note.id));

      dir.deleteSync(recursive: true);
    });

    test('删除分类不删笔记，只解除归属', () async {
      final (store, dir) = await newStore();
      final cat = await store.createCategory('临时');
      final note = await store.create(title: 'n', content: '', categoryId: cat.id);

      await store.deleteCategory(cat.id);

      expect(store.categoryById(cat.id), isNull);
      expect(store.byId(note.id), isNotNull, reason: '笔记不能跟着被删');
      expect(store.byId(note.id)!.categoryId, isNull);

      dir.deleteSync(recursive: true);
    });

    test('重命名分类', () async {
      final (store, dir) = await newStore();
      final cat = await store.createCategory('旧名');
      await store.renameCategory(cat.id, '新名');
      expect(store.categoryById(cat.id)?.name, '新名');
      dir.deleteSync(recursive: true);
    });
  });

  group('搜索', () {
    test('标题和正文都能命中', () async {
      final (store, dir) = await newStore();
      await store.create(title: 'Flutter 布局', content: 'Row 和 Column');
      await store.create(title: '别的', content: '提到 flutter 一次');

      final hits = store.search('flutter');
      expect(hits.length, 2);

      dir.deleteSync(recursive: true);
    });

    test('大小写不敏感', () async {
      final (store, dir) = await newStore();
      await store.create(title: 'DART', content: '');
      expect(store.search('dart').length, 1);
      dir.deleteSync(recursive: true);
    });

    test('默认不搜回收站', () async {
      final (store, dir) = await newStore();
      final n = await store.create(title: '目标', content: '');
      await store.trash(n.id);

      expect(store.search('目标'), isEmpty);
      expect(store.search('目标', includeTrashed: true).length, 1);

      dir.deleteSync(recursive: true);
    });
  });

  group('持久化', () {
    test('重开文件后数据还在', () async {
      final dir = Directory.systemTemp.createTempSync('hs_persist');
      final path = p.join(dir.path, 'notes.json');

      final s1 = await NoteStore.openAt(path);
      final cat = await s1.createCategory('分类A');
      await s1.create(title: '持久', content: '内容', categoryId: cat.id, pinned: true);

      // 重新打开，模拟 App 重启
      final s2 = await NoteStore.openAt(path);
      expect(s2.active.length, 1);
      expect(s2.active.first.title, '持久');
      expect(s2.active.first.pinned, isTrue);
      expect(s2.categories.length, 1);
      expect(s2.categories.first.name, '分类A');

      dir.deleteSync(recursive: true);
    });

    test('回收站状态也能持久化', () async {
      final dir = Directory.systemTemp.createTempSync('hs_persist2');
      final path = p.join(dir.path, 'notes.json');

      final s1 = await NoteStore.openAt(path);
      final n = await s1.create(title: 't', content: '');
      await s1.trash(n.id);

      final s2 = await NoteStore.openAt(path);
      expect(s2.active, isEmpty);
      expect(s2.trashed.length, 1);

      dir.deleteSync(recursive: true);
    });

    test('文件损坏时备份并从空库启动，不抛异常', () async {
      final dir = Directory.systemTemp.createTempSync('hs_corrupt');
      final path = p.join(dir.path, 'notes.json');
      File(path).writeAsStringSync('这不是合法 JSON {{{');

      final store = await NoteStore.openAt(path);
      expect(store.active, isEmpty);
      expect(store.isLoaded, isTrue);

      // 坏文件应被备份出来
      final backups = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('.corrupt-'))
          .toList();
      expect(backups, isNotEmpty, reason: '损坏文件应被保留以便抢救');

      dir.deleteSync(recursive: true);
    });

    test('空文件不报错', () async {
      final dir = Directory.systemTemp.createTempSync('hs_empty');
      final path = p.join(dir.path, 'notes.json');
      File(path).writeAsStringSync('');

      final store = await NoteStore.openAt(path);
      expect(store.active, isEmpty);

      dir.deleteSync(recursive: true);
    });
  });

  group('Note 模型', () {
    test('preview 去掉 Markdown 标记', () {
      final parsed = Note.fromJson({
        'id': '1',
        'title': 't',
        'content': '# 标题\n\n这是**加粗**和[链接](http://a.com)。',
        'createdAt': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
      });
      expect(parsed.preview.contains('**'), isFalse);
      expect(parsed.preview.contains('('), isFalse);
      expect(parsed.preview.contains('加粗'), isTrue);
      expect(parsed.preview.contains('链接'), isTrue);
    });

    test('charCount 不计空白', () {
      final n = Note.fromJson({
        'id': '1',
        'title': '',
        'content': '一二三\n\n四 五',
        'createdAt': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
      });
      expect(n.charCount, 5);
    });

    test('JSON 往返完整', () {
      final now = DateTime.now();
      final n = Note(
        id: 'x',
        title: '标',
        content: '内容',
        createdAt: now,
        updatedAt: now,
        categoryId: 'c1',
        pinned: true,
        convertedPostId: 'content/posts/a.md',
      );
      final back = Note.fromJson(n.toJson());
      expect(back.id, 'x');
      expect(back.pinned, isTrue);
      expect(back.categoryId, 'c1');
      expect(back.convertedPostId, 'content/posts/a.md');
    });
  });
}