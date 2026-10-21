import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hugosugar/core/ai/chat_store.dart';

/// 复刻 AiController 的删除门槛逻辑。
///
/// 为什么不直接 new 一个 AiController：它的构造函数要 SettingsController、
/// SiteStorage 等一串依赖，在纯单元测试里全是噪音。
/// 这里只验证「未归档不能删」这条不变量本身。
/// controller 里的实现与这里保持同一份判断顺序：
///   1. 先从内存列表找
///   2. 找不到再读盘
///   3. 只有 isArchived 为真才允许删
Future<bool> deleteIfArchived(ChatStore store, List<ChatSession> cached,
    String id) async {
  final inMem = cached.where((s) => s.id == id);
  final archived = inMem.isNotEmpty
      ? inMem.first.isArchived
      : (await store.load(id))?.isArchived ?? false;
  if (!archived) return false;
  await store.delete(id);
  return true;
}

void main() {
  group('归档后才能删除', () {
    late Directory tmp;
    late ChatStore store;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('archive_test');
      store = ChatStore(Directory('${tmp.path}/chats'));
    });

    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('未归档的会话拒绝删除，文件仍在', () async {
      await store.save(ChatSession(
        id: 'a',
        title: 'a',
        updatedAt: DateTime(2026, 1, 1),
      ));

      final ok = await deleteIfArchived(
        store,
        await store.listAll(),
        'a',
      );

      expect(ok, isFalse, reason: '未归档不该允许删除');
      expect(await store.load('a'), isNotNull, reason: '文件必须还在');
    });

    test('归档后可以删除', () async {
      await store.save(ChatSession(
        id: 'a',
        title: 'a',
        updatedAt: DateTime(2026, 1, 1),
        archivedAt: DateTime(2026, 2, 1),
      ));

      final ok = await deleteIfArchived(store, await store.listAll(), 'a');

      expect(ok, isTrue);
      expect(await store.load('a'), isNull);
    });

    test('取消归档后又删不掉了', () async {
      // 这条防的是「归档->恢复->还能删」的漏洞：
      // 恢复后必须重新走一遍归档流程。
      final s = ChatSession(
        id: 'a',
        title: 'a',
        updatedAt: DateTime(2026, 1, 1),
        archivedAt: DateTime(2026, 2, 1),
      );
      await store.save(s.copyWith(clearArchived: true));

      final ok = await deleteIfArchived(store, await store.listAll(), 'a');
      expect(ok, isFalse);
      expect(await store.load('a'), isNotNull);
    });

    test('内存列表里没有时，读盘判断依然生效', () async {
      await store.save(ChatSession(
        id: 'a',
        title: 'a',
        updatedAt: DateTime(2026, 1, 1),
        archivedAt: DateTime(2026, 2, 1),
      ));

      // 传一个空缓存，模拟「列表还没刷新」
      final ok = await deleteIfArchived(store, const [], 'a');
      expect(ok, isTrue);
    });
  });
}