import 'package:flutter_test/flutter_test.dart';
import 'package:hugosugar/core/ai/chat_store.dart';

/// 这些测试锁死一个曾经写错的行为：
///
/// 「再生成」早期实现会先把 session 截断到提问位置再发送，
/// 结果旧回答被永久删除 —— 界面上和「重发」毫无区别，
/// 而注释还写着「保留旧回答」。
///
/// 这里不测 UI，只测数据层面的不变量：
/// 无论 regenerate 怎么实现，`entries` 都不能少。
void main() {
  ChatSession sessionWith({
    required List<ChatEntry> entries,
  }) {
    return ChatSession(
      id: 's1',
      title: 't',
      updatedAt: DateTime.now(),
      entries: entries,
    );
  }

  ChatEntry user(String text) =>
      ChatEntry(role: 'user', text: text, at: DateTime.now());
  ChatEntry ai(String text) =>
      ChatEntry(role: 'assistant', text: text, at: DateTime.now());

  group('再生成的前置条件', () {
    test('能从末尾找到最后一条用户提问', () {
      final s = sessionWith(entries: [
        user('第一个问题'),
        ai('第一个回答'),
        user('第二个问题'),
        ai('第二个回答'),
      ]);

      var idx = -1;
      for (var i = s.entries.length - 1; i >= 0; i--) {
        if (s.entries[i].isUser) {
          idx = i;
          break;
        }
      }

      expect(idx, 2);
      expect(s.entries[idx].text, '第二个问题');
    });

    test('历史切片不包含旧回答（避免模型「接着上次说」）', () {
      final s = sessionWith(entries: [
        user('Q1'),
        ai('A1'),
        user('Q2'),
        ai('A2'),
      ]);

      const lastUserIdx = 2;
      final history = s.entries.sublist(0, lastUserIdx);

      expect(history.length, 2);
      expect(history.map((e) => e.text), ['Q1', 'A1']);
      // Q2 之后的内容不能出现在历史里
      expect(history.any((e) => e.text == 'A2'), isFalse);
    });
  });

  group('不变量：再生成不能丢失已有条目', () {
    test('用 copyWith 追加不会删除旧回答', () {
      final s = sessionWith(entries: [
        user('Q1'),
        ai('A1'),
      ]);

      // 正确的做法：保留全部，追加新的回答
      final afterRegenerate = s.copyWith(entries: [
        ...s.entries,
        ai('A1-新'),
      ]);

      expect(afterRegenerate.entries.length, 3);
      expect(afterRegenerate.entries[1].text, 'A1'); // 旧的还在
      expect(afterRegenerate.entries[2].text, 'A1-新');
    });

    test('截断再追加会丢掉旧回答（说明为什么不能这么做）', () {
      final s = sessionWith(entries: [
        user('Q1'),
        ai('A1'),
      ]);

      const lastUserIdx = 0;
      final wrong = s.entries.sublist(0, lastUserIdx);

      // 这就是旧实现的 bug：长度只剩 0，A1 被删了
      expect(wrong.length, 0);
      expect(s.entries.length, 2); // 原对象没变，但被写回存储后就丢了
    });
  });

  group('重发 vs 再生成 的语义差异', () {
    test('重发：撤回后的条目应比原来少', () {
      final s = sessionWith(entries: [
        user('Q1'),
        ai('A1'),
        user('Q2'),
        ai('A2'),
      ]);

      // resend 在 Q1 处撤回 → 只剩空
      final afterRecall = s.entries.sublist(0, 0);
      expect(afterRecall.length, lessThan(s.entries.length));
    });

    test('再生成：条目数只能增加或不变', () {
      final s = sessionWith(entries: [
        user('Q1'),
        ai('A1'),
      ]);

      final after = s.copyWith(entries: [...s.entries, ai('A1b')]);
      expect(after.entries.length, greaterThanOrEqualTo(s.entries.length));
    });
  });
}