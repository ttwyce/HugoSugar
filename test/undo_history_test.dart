import 'package:flutter_test/flutter_test.dart';
import 'package:hugosugar/core/edit/undo_history.dart';

void main() {
  group('UndoHistory', () {
    test('初始状态不能撤销也不能重做', () {
      final h = EditHistory();
      h.seed('t', 'b');
      expect(h.canUndo, isFalse);
      expect(h.canRedo, isFalse);
    });

    test('记录一步后可撤销，撤销回到上一步', () {
      final h = EditHistory(debounce: Duration.zero);
      h.seed('标题', '原文');
      h.record('标题', '原文改');
      h.flush();

      expect(h.canUndo, isTrue);
      final snap = h.undo();
      expect(snap!.body, '原文');
      expect(snap.title, '标题');
    });

    test('撤销后可重做回新内容', () {
      final h = EditHistory(debounce: Duration.zero);
      h.seed('t', 'v1');
      h.record('t', 'v2');
      h.flush();

      h.undo();
      expect(h.canRedo, isTrue);
      final redo = h.redo();
      expect(redo!.body, 'v2');
    });

    test('内容没变时不留重复快照', () {
      final h = EditHistory(debounce: Duration.zero);
      h.seed('t', 'same');
      h.record('t', 'same');
      h.flush();
      expect(h.canUndo, isFalse);
    });

    test('在历史中间编辑会丢弃 redo 分支', () {
      final h = EditHistory(debounce: Duration.zero);
      h.seed('t', 'a');
      h.record('t', 'b');
      h.flush();
      h.record('t', 'c');
      h.flush();

      // 回到 b
      h.undo();
      expect(h.canRedo, isTrue);

      // 此时编辑，c 应该被丢弃
      h.record('t', 'd');
      h.flush();
      expect(h.canRedo, isFalse);
    });

    test('超出上限时丢掉最老的记录', () {
      final h = EditHistory(debounce: Duration.zero, maxEntries: 3);
      h.seed('t', 'v0');
      for (var i = 1; i <= 5; i++) {
        h.record('t', 'v$i');
        h.flush();
      }
      // 只能退到 v3（总共保留 3 条：v3 v4 v5）
      expect(h.undo()!.body, 'v4');
      expect(h.undo()!.body, 'v3');
      expect(h.undo(), isNull);
    });

    test('muted 期间不记录', () {
      final h = EditHistory(debounce: Duration.zero);
      h.seed('t', 'a');
      h.mute(true);
      h.record('t', 'b');
      h.flush();
      h.mute(false);
      expect(h.canUndo, isFalse);
    });

    test('标题和正文一起回退，不会错位', () {
      final h = EditHistory(debounce: Duration.zero);
      h.seed('旧标题', '旧正文');
      h.record('新标题', '新正文');
      h.flush();

      final s = h.undo()!;
      expect(s.title, '旧标题');
      expect(s.body, '旧正文');
    });

    test('undo 会先 flush 待定快照，避免一跳两步', () {
      final h = EditHistory(debounce: const Duration(seconds: 10));
      h.seed('t', 'a');
      h.record('t', 'b');
      // 不 flush，直接撤
      final s = h.undo();
      expect(s!.body, 'a');
    });
  });
}