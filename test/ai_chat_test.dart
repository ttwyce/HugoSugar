import 'package:flutter_test/flutter_test.dart';
import 'package:hugosugar/core/ai/chat_store.dart';
import 'package:hugosugar/features/ai/write_approval_sheet.dart';

void main() {
  group('computeDiff', () {
    test('完全相同 → 无新增无删除', () {
      final d = computeDiff('a\nb', 'a\nb');
      expect(d.added, 0);
      expect(d.removed, 0);
      expect(d.lines.every((l) => l.kind == DiffKind.same), isTrue);
    });

    test('新增文件：旧为空，全部算新增', () {
      final d = computeDiff('', 'line1\nline2\nline3');
      expect(d.added, 3);
      expect(d.removed, 0);
    });

    test('删掉一行', () {
      final d = computeDiff('a\nb\nc', 'a\nc');
      expect(d.removed, 1);
      expect(d.added, 0);
    });

    test('改一行 = 1 删 1 增', () {
      final d = computeDiff('a\nb\nc', 'a\nx\nc');
      expect(d.removed, 1);
      expect(d.added, 1);
    });

    test('中间插入一行', () {
      final d = computeDiff('a\nc', 'a\nb\nc');
      expect(d.added, 1);
      expect(d.removed, 0);
    });

    test('顺序保留：未改动行按原顺序出现', () {
      final d = computeDiff('one\ntwo\nthree', 'one\nTWO\nthree');
      final same = d.lines
          .where((l) => l.kind == DiffKind.same)
          .map((l) => l.text)
          .toList();
      expect(same, ['one', 'three']);
    });

    test('超长文件走快速路径，不逐行比对', () {
      final big = List.generate(3100, (i) => 'line$i').join('\n');
      final d = computeDiff('', big);
      // 应该只有一条提示 + 若干新增，不能是 O(n*m) 的完整比对
      expect(d.lines.first.kind, DiffKind.removed);
      expect(d.lines.first.text.contains('文件过大'), isTrue);
    });
  });

  group('ChatEntry 序列化', () {
    test('backups 往返不丢字段', () {
      final e = ChatEntry(
        role: 'assistant',
        text: '写好了',
        at: DateTime(2026, 1, 2, 3, 4),
        backups: [
          WriteBackup(
            relPath: 'posts/a.md',
            previous: 'old content',
            at: DateTime(2026, 1, 2, 3, 4),
          ),
        ],
      );

      final back = ChatEntry.fromJson(e.toJson());
      expect(back.backups.length, 1);
      expect(back.backups.first.relPath, 'posts/a.md');
      expect(back.backups.first.previous, 'old content');
      expect(back.canRollback, isTrue);
    });

    test('新建文件的备份 previous 为 null', () {
      final e = ChatEntry(
        role: 'assistant',
        text: '',
        at: DateTime.now(),
        backups: [
          WriteBackup(relPath: 'posts/new.md', previous: null, at: DateTime.now()),
        ],
      );
      final back = ChatEntry.fromJson(e.toJson());
      // null 要能正确往返，否则回滚会误判成「恢复成空文件」
      expect(back.backups.first.previous, isNull);
    });

    test('多条备份都能保住', () {
      final e = ChatEntry(
        role: 'assistant',
        text: '',
        at: DateTime.now(),
        backups: [
          WriteBackup(relPath: 'a.md', previous: '1', at: DateTime.now()),
          WriteBackup(relPath: 'b.md', previous: '2', at: DateTime.now()),
        ],
      );
      final back = ChatEntry.fromJson(e.toJson());
      expect(back.backups.length, 2);
      expect(back.backups.map((b) => b.relPath).toList(), ['a.md', 'b.md']);
    });

    test('没有备份时 canRollback 为 false', () {
      final e = ChatEntry(role: 'assistant', text: 'x', at: DateTime.now());
      expect(e.canRollback, isFalse);
    });
  });

  group('ChatSession', () {
    test('toApiMessages 跳过错误消息', () {
      final s = ChatSession(
        id: 'c1',
        title: 't',
        updatedAt: DateTime.now(),
        entries: [
          ChatEntry(role: 'user', text: '问', at: DateTime.now()),
          ChatEntry(
            role: 'assistant',
            text: '出错了',
            at: DateTime.now(),
            isError: true,
          ),
          ChatEntry(role: 'assistant', text: '答', at: DateTime.now()),
        ],
      );

      final msgs = s.toApiMessages();
      // 错误消息回放给模型会造成困惑，也浪费 token
      expect(msgs.length, 2);
      expect(msgs.map((m) => m.content).toList(), ['问', '答']);
    });

    test('toApiMessages 跳过空文本', () {
      final s = ChatSession(
        id: 'c1',
        title: 't',
        updatedAt: DateTime.now(),
        entries: [
          ChatEntry(role: 'user', text: '问', at: DateTime.now()),
          ChatEntry(role: 'assistant', text: '   ', at: DateTime.now()),
        ],
      );
      expect(s.toApiMessages().length, 1);
    });

    test('toApiMessages 超过上限时保留最近的', () {
      final entries = List.generate(
        30,
        (i) => ChatEntry(role: 'user', text: 'm$i', at: DateTime.now()),
      );
      final s = ChatSession(
        id: 'c1',
        title: 't',
        updatedAt: DateTime.now(),
        entries: entries,
      );
      final msgs = s.toApiMessages(maxEntries: 10);
      expect(msgs.length, 10);
      // 应该保留最后 10 条（m20..m29）
      expect(msgs.first.content, 'm20');
      expect(msgs.last.content, 'm29');
    });

    test('token 累加', () {
      final s = ChatSession(
        id: 'c1',
        title: 't',
        updatedAt: DateTime.now(),
        entries: [
          ChatEntry(
            role: 'assistant',
            text: '',
            at: DateTime.now(),
            promptTokens: 10,
            completionTokens: 5,
          ),
          ChatEntry(
            role: 'assistant',
            text: '',
            at: DateTime.now(),
            promptTokens: 20,
            completionTokens: 8,
          ),
        ],
      );
      expect(s.totalPromptTokens, 30);
      expect(s.totalCompletionTokens, 13);
      expect(s.hasExactUsage, isTrue);
    });

    test('没有 usage 时 hasExactUsage 为 false', () {
      final s = ChatSession(
        id: 'c1',
        title: 't',
        updatedAt: DateTime.now(),
        entries: [
          ChatEntry(role: 'assistant', text: 'x', at: DateTime.now()),
        ],
      );
      expect(s.hasExactUsage, isFalse);
    });

    test('完整往返不丢字段', () {
      final s = ChatSession(
        id: 'c9',
        title: '标题',
        updatedAt: DateTime(2026, 5, 1),
        endpointId: 'ep_1',
        model: 'm',
        categoryIds: ['cat_a', 'cat_b'],
        readNotes: true,
        entries: [
          ChatEntry(role: 'user', text: 'hi', at: DateTime(2026, 5, 1)),
        ],
      );
      final back = ChatSession.fromJson(s.toJson());
      expect(back.id, 'c9');
      expect(back.title, '标题');
      expect(back.endpointId, 'ep_1');
      expect(back.categoryIds, ['cat_a', 'cat_b']);
      expect(back.readNotes, isTrue);
      expect(back.entries.length, 1);
    });
  });
}