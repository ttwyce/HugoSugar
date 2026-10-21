import 'package:flutter_test/flutter_test.dart';
import 'package:hugosugar/core/ai/tools/builtin_tools.dart';
import 'package:hugosugar/core/note/note.dart';

/// 构造一个只关心 save_note 的 registry。
///
/// 其它字段给空实现：save_note 不依赖它们，这样测试不会被无关的 IO 干扰。
ToolRegistry _registry({
  required Future<Note?> Function({
    required String title,
    required String content,
    required bool pinned,
  })
  createNote,
  List<String> disabled = const [],
}) {
  return ToolRegistry(
    listNotes: () => const <Note>[],
    readNote: (_) => null,
    searchNotes: (_) => const <Note>[],
    createNote: createNote,
    listPosts: () => const [],
    readPost: (_) async => null,
    writePost: (_, _) async {},
    contentDirAbs: '/tmp/content',
    disabledTools: disabled,
  );
}

void main() {
  group('save_note 工具', () {
    test('出现在 schema 里，且不要求审批（写想法可回收，属低风险）', () {
      final tools = _registry(
        createNote:
            ({required title, required content, required pinned}) async => null,
      ).build();
      final t = tools.firstWhere((e) => e.name == 'save_note');
      expect(t.requiresApproval, isFalse);
      final props = t.parameters['properties'] as Map;
      expect(props.containsKey('title'), isTrue);
      expect(props.containsKey('content'), isTrue);
      expect(props.containsKey('pinned'), isTrue);
    });

    test('正常保存，把 title/content/pinned 透传给 createNote', () async {
      String? gotTitle;
      String? gotContent;
      bool? gotPinned;
      final tools = _registry(
        createNote:
            ({required title, required content, required pinned}) async {
              gotTitle = title;
              gotContent = content;
              gotPinned = pinned;
              return Note(
                id: 'n1',
                title: title,
                content: content,
                createdAt: DateTime(2026),
                updatedAt: DateTime(2026),
                pinned: pinned,
              );
            },
      ).build();
      final t = tools.firstWhere((e) => e.name == 'save_note');
      final r = await t.execute({
        'title': 'Flutter 状态管理',
        'content': '## 资料\nhttps://example.com 关键结论…',
        'pinned': true,
      });
      expect(r.ok, isTrue);
      expect(gotTitle, 'Flutter 状态管理');
      expect(gotPinned, isTrue);
      expect(gotContent, contains('example.com'));
      expect(r.text, contains('n1'));
    });

    test('内容为空时拒绝，不调用 createNote', () async {
      var called = false;
      final tools = _registry(
        createNote:
            ({required title, required content, required pinned}) async {
              called = true;
              return null;
            },
      ).build();
      final t = tools.firstWhere((e) => e.name == 'save_note');
      final r = await t.execute({'title': 'x', 'content': '   '});
      expect(r.ok, isFalse);
      expect(called, isFalse);
    });

    test('标题为空时用正文首行兜底，避免列表里认不出', () async {
      String? gotTitle;
      final tools = _registry(
        createNote:
            ({required title, required content, required pinned}) async {
              gotTitle = title;
              return Note(
                id: 'n2',
                title: title,
                content: content,
                createdAt: DateTime(2026),
                updatedAt: DateTime(2026),
              );
            },
      ).build();
      final t = tools.firstWhere((e) => e.name == 'save_note');
      await t.execute({'content': '## 今天搜到的\n更多内容'});
      expect(gotTitle, '今天搜到的');
    });

    test('笔记库不可用（createNote 返回 null）时回明确失败', () async {
      final tools = _registry(
        createNote:
            ({required title, required content, required pinned}) async => null,
      ).build();
      final t = tools.firstWhere((e) => e.name == 'save_note');
      final r = await t.execute({'title': 'a', 'content': 'b'});
      expect(r.ok, isFalse);
      expect(r.text, contains('不可用'));
    });

    test('被用户关掉后，不出现在 schema 里', () {
      final tools = _registry(
        createNote:
            ({required title, required content, required pinned}) async => null,
        disabled: ['save_note'],
      ).build();
      expect(tools.any((e) => e.name == 'save_note'), isFalse);
    });
  });
}
