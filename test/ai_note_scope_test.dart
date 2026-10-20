import 'package:flutter_test/flutter_test.dart';
import 'package:hugosugar/core/ai/note_context.dart';
import 'package:hugosugar/core/note/note.dart';

Note mk(
  String id, {
  bool pinned = false,
  String? categoryId,
  DateTime? deletedAt,
}) {
  return Note(
    id: id,
    title: id,
    content: 'body-$id',
    createdAt: DateTime(2024, 1, 1),
    updatedAt: DateTime(2024, 1, 1),
    pinned: pinned,
    categoryId: categoryId,
    deletedAt: deletedAt,
  );
}

void main() {
  const builder = NoteContextBuilder();
  final notes = [
    mk('a', categoryId: 'cat1'),
    mk('b', categoryId: 'cat2'),
    mk('c', pinned: true),
    mk('gone', categoryId: 'cat1', deletedAt: DateTime(2024, 6, 1)),
  ];

  group('总开关关闭（默认）', () {
    test('什么都没指定 → 一条都不读', () {
      final r = builder.buildFromSettings(
        allNotes: notes,
        enabled: false,
      );
      expect(r.notes, isEmpty);
      expect(r.mode, NoteScopeMode.none);
      expect(r.describe(), '不读取想法');
    });

    test('明确指定分组 → 即使开关关着也读', () {
      final r = builder.buildFromSettings(
        allNotes: notes,
        enabled: false,
        explicitCategoryIds: {'cat1'},
      );
      // gone 已删除，不该出现
      expect(r.notes.map((e) => e.id), ['a']);
    });

    test('明确指定某几条想法 → 即使开关关着也读', () {
      final r = builder.buildFromSettings(
        allNotes: notes,
        enabled: false,
        explicitNoteIds: {'b'},
      );
      expect(r.notes.map((e) => e.id), ['b']);
      expect(r.mode, NoteScopeMode.explicitNotes);
    });

    test('指定了已删除的想法 → 读不到', () {
      final r = builder.buildFromSettings(
        allNotes: notes,
        enabled: false,
        explicitNoteIds: {'gone'},
      );
      expect(r.notes, isEmpty);
    });
  });

  group('总开关打开', () {
    test('没有限定分组 → 读全部', () {
      final r = builder.buildFromSettings(
        allNotes: notes,
        enabled: true,
      );
      expect(r.notes.map((e) => e.id).toSet(), {'a', 'b', 'c'});
      expect(r.mode, NoteScopeMode.all);
    });

    test('限定了分组 → 只读这些分组', () {
      final r = builder.buildFromSettings(
        allNotes: notes,
        enabled: true,
        categoryIds: {'cat2'},
      );
      expect(r.notes.map((e) => e.id), ['b']);
    });

    test('明确指定的分组优先于设置里的分组', () {
      final r = builder.buildFromSettings(
        allNotes: notes,
        enabled: true,
        categoryIds: {'cat2'},
        explicitCategoryIds: {'cat1'},
      );
      expect(r.notes.map((e) => e.id), ['a']);
    });

    test('明确指定单条优先于分组', () {
      final r = builder.buildFromSettings(
        allNotes: notes,
        enabled: true,
        categoryIds: {'cat1'},
        explicitCategoryIds: {'cat1'},
        explicitNoteIds: {'c'},
      );
      expect(r.notes.map((e) => e.id), ['c']);
    });
  });

  test('回收站里的想法永远不会被读到', () {
    final r = builder.buildFromSettings(
      allNotes: notes,
      enabled: true,
    );
    expect(r.notes.any((e) => e.id == 'gone'), isFalse);
  });
}