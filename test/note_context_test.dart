import 'package:flutter_test/flutter_test.dart';
import 'package:hugosugar/core/ai/note_context.dart';
import 'package:hugosugar/core/note/note.dart';

Note mk(
  String id, {
  String title = '',
  String content = '',
  bool pinned = false,
  String? categoryId,
  DateTime? updatedAt,
  DateTime? deletedAt,
}) {
  final t = updatedAt ?? DateTime(2024, 1, 1);
  return Note(
    id: id,
    title: title,
    content: content.isEmpty ? 'body-$id' : content,
    createdAt: t,
    updatedAt: t,
    pinned: pinned,
    categoryId: categoryId,
    deletedAt: deletedAt,
  );
}

void main() {
  final builder = NoteContextBuilder();

  group('默认读全部想法', () {
    test('不指定范围时，非置顶的也会被读到', () {
      final notes = [
        mk('a', title: 'A'),
        mk('b', title: 'B'), // 没有 pinned
        mk('c', title: 'C', pinned: true),
      ];
      final r = builder.build(allNotes: notes);

      expect(r.mode, NoteScopeMode.all);
      expect(r.notes.length, 3, reason: '置顶与否不影响是否被读取');
      expect(r.truncated, 0);
    });

    test('回收站里的想法不注入', () {
      final notes = [
        mk('a'),
        mk('gone', deletedAt: DateTime(2024, 6, 1)),
      ];
      final r = builder.build(allNotes: notes);
      expect(r.notes.map((e) => e.id), ['a']);
    });
  });

  group('按分组读取', () {
    test('只读选中分组', () {
      final notes = [
        mk('a', categoryId: 'cat1'),
        mk('b', categoryId: 'cat2'),
        mk('c'),
      ];
      final r = builder.build(
        allNotes: notes,
        mode: NoteScopeMode.categories,
        categoryIds: {'cat1'},
      );
      expect(r.notes.map((e) => e.id), ['a']);
    });

    test('多选分组取并集', () {
      final notes = [
        mk('a', categoryId: 'cat1'),
        mk('b', categoryId: 'cat2'),
        mk('c', categoryId: 'cat3'),
      ];
      final r = builder.build(
        allNotes: notes,
        mode: NoteScopeMode.categories,
        categoryIds: {'cat1', 'cat2'},
      );
      expect(r.notes.map((e) => e.id).toSet(), {'a', 'b'});
    });

    test('选了分组模式但一个分组都没选 → 读不到，而不是偷偷读全部', () {
      final notes = [mk('a'), mk('b')];
      final r = builder.build(
        allNotes: notes,
        mode: NoteScopeMode.categories,
        categoryIds: {},
      );
      expect(r.notes, isEmpty);
      expect(r.describe(), '选中的分组里没有说话');
    });
  });

  group('精选模式', () {
    test('只读 pinned', () {
      final notes = [
        mk('a', pinned: true),
        mk('b'),
      ];
      final r = builder.build(
        allNotes: notes,
        mode: NoteScopeMode.pinned,
      );
      expect(r.notes.map((e) => e.id), ['a']);
    });
  });

  group('上限截断', () {
    test('超出上限按最近更新保留，并报告截断条数', () {
      final notes = [
        for (var i = 0; i < 10; i++)
          mk('n$i', updatedAt: DateTime(2024, 1, 1 + i)),
      ];
      final small = const NoteContextBuilder(maxNotes: 4);
      final r = small.build(allNotes: notes);

      expect(r.notes.length, 4);
      expect(r.totalMatched, 10);
      expect(r.truncated, 6);
      // 最新的 4 条是 n9..n6
      expect(r.notes.map((e) => e.id), ['n9', 'n8', 'n7', 'n6']);
      expect(r.describe(), contains('另有 6 条'));
    });
  });

  group('提示词拼装', () {
    test('无标题用占位，正文原样', () {
      final notes = [mk('a', content: '第一句')];
      final block = builder.build(allNotes: notes).toPromptBlock();
      expect(block, contains('## 用户的想法'));
      expect(block, contains('（无标题）'));
      expect(block, contains('第一句'));
    });

    test('空列表返回空串', () {
      final block = builder
          .build(allNotes: [], mode: NoteScopeMode.none)
          .toPromptBlock();
      expect(block, isEmpty);
    });
  });

  group('describe 文案', () {
    test('全部模式', () {
      final r = builder.build(allNotes: [mk('a'), mk('b')]);
      expect(r.describe(), '读取全部想法 2 条');
    });

    test('none 模式', () {
      final r = builder.build(allNotes: [mk('a')], mode: NoteScopeMode.none);
      expect(r.describe(), '不读取想法');
    });
  });
}