import 'package:flutter_test/flutter_test.dart';
import 'package:hugosugar/core/ai/agent_runner.dart';
import 'package:hugosugar/core/ai/ai_controller.dart';
import 'package:hugosugar/core/ai/chat_store.dart';

/// 撤回 / 重发 / 编辑对话。
///
/// 用户要求：「增加撤回对话功能，如果文件有更改可以选择是否回滚文件，
/// 重发对话功能，编辑对话功能」。
///
/// 这里覆盖 controller 层的语义约束。最容易写错的是撤回粒度：
/// user 消息撤「这条及之后」，assistant 消息只撤「这条」。
void main() {
  ChatEntry userEntry(String text) =>
      ChatEntry(role: 'user', text: text, at: DateTime(2026, 1, 1));

  ChatEntry assistantEntry(String text) => ChatEntry(
        role: 'assistant',
        text: text,
        at: DateTime(2026, 1, 1),
      );

  ChatSession sessionWith(List<ChatEntry> entries, {String title = '测试'}) =>
      ChatSession(
        id: 's1',
        title: title,
        updatedAt: DateTime(2026, 1, 1),
        entries: entries,
      );

  test('ChatEntry.isUser 正确区分角色', () {
    expect(userEntry('a').isUser, isTrue);
    expect(assistantEntry('b').isUser, isFalse);
  });

  group('recallFromEntry 的粒度', () {
    late AiController ctrl;

    setUp(() {
      ctrl = AiController();
    });

    test('user 消息撤回「这条及之后」', () async {
      final u1 = userEntry('第一问');
      final a1 = assistantEntry('第一答');
      final u2 = userEntry('第二问');
      final a2 = assistantEntry('第二答');

      ctrl.debugSetSession(sessionWith([u1, a1, u2, a2]));

      // 撤回第一条提问 → 后面三条都没了
      await ctrl.recallFromEntry(u1, rollbackFiles: false);

      expect(ctrl.session!.entries.length, 0);
      // 全删光后标题回到「新对话」
      expect(ctrl.session!.title, '新对话');
    });

    test('user 消息撤回保留它前面的内容', () async {
      final u1 = userEntry('第一问');
      final a1 = assistantEntry('第一答');
      final u2 = userEntry('第二问');

      ctrl.debugSetSession(sessionWith([u1, a1, u2]));

      await ctrl.recallFromEntry(u2, rollbackFiles: false);

      expect(ctrl.session!.entries.length, 2);
      expect(ctrl.session!.entries[0].text, '第一问');
      expect(ctrl.session!.entries[1].text, '第一答');
    });

    test('assistant 消息 single=true 只删这一条', () async {
      final u1 = userEntry('第一问');
      final a1 = assistantEntry('第一答');
      final u2 = userEntry('第二问');
      final a2 = assistantEntry('第二答');

      ctrl.debugSetSession(sessionWith([u1, a1, u2, a2]));

      await ctrl.recallFromEntry(a1, rollbackFiles: false, single: true);

      // 只少了 a1，其余三个都在
      expect(ctrl.session!.entries.length, 3);
      expect(
        ctrl.session!.entries.map((e) => e.text).toList(),
        ['第一问', '第二问', '第二答'],
      );
    });

    test('不存在的 entry 返回 -1', () async {
      ctrl.debugSetSession(sessionWith([userEntry('a')]));

      final r = await ctrl.recallFromEntry(
        userEntry('不在任何会话里'),
        rollbackFiles: false,
      );
      expect(r, -1);
    });
  });

  group('deleteEntry', () {
    test('只删一条且不动其他', () async {
      final a = userEntry('A');
      final b = assistantEntry('B');
      final c = userEntry('C');

      final ctrl = AiController();
      ctrl.debugSetSession(sessionWith([a, b, c], title: 't'));

      expect(await ctrl.deleteEntry(b), isTrue);
      expect(
        ctrl.session!.entries.map((e) => e.text).toList(),
        ['A', 'C'],
      );
    });
  });

  group('生成中禁止改写对话', () {
    test('busy 时 recall 返回 -1', () async {
      final u = userEntry('问');
      final ctrl = AiController();
      ctrl.debugSetSession(sessionWith([u], title: 't'));
      ctrl.debugSetBusy(true);

      expect((await ctrl.recallFromEntry(u, rollbackFiles: false)), -1);
      // 消息还在
      expect(ctrl.session!.entries.length, 1);
    });

    test('busy 时 deleteEntry 返回 false', () async {
      final u = userEntry('问');
      final ctrl = AiController();
      ctrl.debugSetSession(sessionWith([u], title: 't'));
      ctrl.debugSetBusy(true);

      expect(await ctrl.deleteEntry(u), isFalse);
      expect(ctrl.session!.entries.length, 1);
    });
  });

  group('编辑 / 重发的参数校验', () {
    test('assistant 消息不能当作用户提问重发', () async {
      final ctrl = AiController();
      final a = assistantEntry('答');

      final ok = await ctrl.editAndResend(
        a,
        '新内容',
        onApproval: (_) async => ApprovalDecision.reject,
      );
      expect(ok, isFalse);
    });

    test('空内容不发送', () async {
      final ctrl = AiController();
      final u = userEntry('原内容');

      final ok = await ctrl.editAndResend(
        u,
        '   ',
        onApproval: (_) async => ApprovalDecision.reject,
      );
      expect(ok, isFalse);
    });
  });
}
