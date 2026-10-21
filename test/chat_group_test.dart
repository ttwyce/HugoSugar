import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hugosugar/core/ai/chat_store.dart';

ChatSession _s(String id, {String groupId = '', DateTime? archivedAt}) =>
    ChatSession(
      id: id,
      title: id,
      updatedAt: DateTime(2026, 1, 1),
      groupId: groupId,
      archivedAt: archivedAt,
    );

void main() {
  group('ChatSession 分组与归档字段', () {
    test('默认未分组、未归档', () {
      final s = _s('a');
      expect(s.groupId, '');
      expect(s.isArchived, isFalse);
    });

    test('copyWith 能设置分组', () {
      expect(_s('a').copyWith(groupId: 'g1').groupId, 'g1');
    });

    test('copyWith 不动归档状态时保留原值', () {
      final t = DateTime(2026, 3, 1);
      final s = _s('a', archivedAt: t);
      expect(s.copyWith(title: 'x').archivedAt, t);
    });

    test('clearArchived 能真的置回 null', () {
      // 关键：copyWith 的 ?? 语法无法把字段设成 null，
      // 没有这个开关就永远无法「取消归档」。
      final s = _s('a', archivedAt: DateTime(2026, 3, 1));
      final r = s.copyWith(clearArchived: true);
      expect(r.archivedAt, isNull);
      expect(r.isArchived, isFalse);
    });

    test('序列化往返保留分组与归档', () {
      final t = DateTime(2026, 5, 20, 10, 30);
      final s = _s('a', groupId: 'g1', archivedAt: t);
      final back = ChatSession.fromJson(s.toJson());
      expect(back.groupId, 'g1');
      expect(back.archivedAt, t);
    });

    test('旧数据（无 groupId/archivedAt 字段）能读，且视为未分组未归档', () {
      // 升级兼容：老版本存的 JSON 没有这两个字段，
      // 读出来必须是「未分组 + 未归档」，而不是崩或变成已归档。
      final legacy = {
        'id': 'old',
        'title': '老对话',
        'updatedAt': '2026-01-01T00:00:00.000',
        'entries': <dynamic>[],
      };
      final s = ChatSession.fromJson(Map<String, dynamic>.from(legacy));
      expect(s.groupId, '');
      expect(s.isArchived, isFalse);
    });
  });

  group('ChatStore 分组持久化', () {
    late Directory tmp;
    late ChatStore store;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('chatstore_test');
      store = ChatStore(Directory('${tmp.path}/chats'));
    });

    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('新建分组后能读回来', () async {
      await store.saveGroups([
        const ChatGroup(id: 'g1', name: '写作辅助'),
        const ChatGroup(id: 'g2', name: '排错'),
      ]);
      final out = await store.listGroups();
      expect(out.map((g) => g.name), ['写作辅助', '排错']);
    });

    test('分组文件不会被 listAll 当成会话', () async {
      // 这是真会发生的错：_groups.json 和会话文件同目录，
      // 不过滤就会多出一个 id 为空、标题空白的「幽灵会话」。
      await store.save(_s('real'));
      await store.saveGroups([const ChatGroup(id: 'g1', name: 'G')]);
      final sessions = await store.listAll();
      expect(sessions, hasLength(1));
      expect(sessions.first.id, 'real');
    });

    test('分组文件不存在时返回空列表而不是抛异常', () async {
      expect(await store.listGroups(), isEmpty);
    });

    test('分组文件损坏时返回空列表，不影响会话', () async {
      await store.save(_s('real'));
      await store.saveGroups([const ChatGroup(id: 'g1', name: 'G')]);
      // 手动写坏
      final f = File('${tmp.path}/chats/_groups.json');
      await f.writeAsString('{broken');
      expect(await store.listGroups(), isEmpty);
      expect(await store.listAll(), hasLength(1));
    });
  });
}