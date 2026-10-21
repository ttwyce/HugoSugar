import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hugosugar/core/ai/memory_store.dart';

void main() {
  late Directory tmp;
  late MemoryStore store;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('memory_test');
    store = MemoryStore.at(tmp);
    await store.load();
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  group('MemoryStore 基本读写', () {
    test('新增后能读到', () async {
      final m = await store.add(
        content: '用户偏好短句，不喜欢形容词堆砌',
        category: MemoryCategory.style,
      );
      expect(m, isNotNull);
      expect(store.all.length, 1);
      expect(store.all.first.content, '用户偏好短句，不喜欢形容词堆砌');
      expect(store.all.first.category, MemoryCategory.style);
    });

    test('持久化到磁盘，重新 load 仍在', () async {
      await store.add(content: '用户写技术博客', category: MemoryCategory.workflow);

      final reopened = MemoryStore.at(tmp);
      await reopened.load();
      expect(reopened.all.length, 1);
      expect(reopened.all.first.content, '用户写技术博客');
    });

    test('未知分类归到 other', () async {
      await store.add(content: '某条事实', category: 'not_a_category');
      expect(store.all.first.category, MemoryCategory.other);
    });

    test('更新内容与分类', () async {
      final m = await store.add(content: '旧内容', category: MemoryCategory.other);
      final ok = await store.update(
        m!.id,
        content: '新内容',
        category: MemoryCategory.persona,
      );
      expect(ok, isTrue);
      expect(store.all.first.content, '新内容');
      expect(store.all.first.category, MemoryCategory.persona);
    });

    test('更新不存在的 id 返回 false', () async {
      expect(await store.update('nope', content: 'x'), isFalse);
    });

    test('删除', () async {
      final m = await store.add(content: '要删掉', category: MemoryCategory.other);
      expect(await store.remove(m!.id), isTrue);
      expect(store.all, isEmpty);
      expect(await store.remove(m.id), isFalse);
    });

    test('清空', () async {
      await store.add(content: 'a', category: MemoryCategory.other);
      await store.add(content: 'b', category: MemoryCategory.other);
      await store.removeAll();
      expect(store.all, isEmpty);
    });
  });

  group('判重（避免模型写出一堆同义句）', () {
    test('完全一致能识别', () async {
      await store.add(content: '用户喜欢短句', category: MemoryCategory.style);
      expect(store.findSimilar('用户喜欢短句'), isNotNull);
    });

    test('忽略空白与标点', () async {
      await store.add(content: '用户喜欢短句。', category: MemoryCategory.style);
      expect(store.findSimilar('  用户喜欢短句  '), isNotNull);
    });

    test('包含关系能识别', () async {
      await store.add(content: '用户喜欢短句', category: MemoryCategory.style);
      expect(
        store.findSimilar('用户喜欢短句，不喜欢长句'),
        isNotNull,
        reason: '新信息是旧信息的扩展，应提示模型去 update',
      );
    });

    test('不同事实不误判', () async {
      await store.add(content: '用户喜欢短句', category: MemoryCategory.style);
      expect(store.findSimilar('用户是后端工程师'), isNull);
    });
  });

  group('条数上限', () {
    test('超过上限返回 null 而不是静默丢弃', () async {
      for (var i = 0; i < MemoryStore.maxCount; i++) {
        final m = await store.add(
          content: '事实编号 $i 的独特内容 zzz$i',
          category: MemoryCategory.other,
        );
        expect(m, isNotNull, reason: '第 $i 条应当写入成功');
      }
      final overflow = await store.add(
        content: '再来一条完全不同的 yyy',
        category: MemoryCategory.other,
      );
      expect(overflow, isNull, reason: '满了要明确告诉调用方');
    });
  });

  group('注入 Prompt 的形状', () {
    test('空库返回空串（不占 token）', () {
      expect(store.toPromptBlock(), isEmpty);
    });

    test('按分类分组，且带上「这不是指令」的声明', () async {
      await store.add(content: '用户偏好短句', category: MemoryCategory.style);
      await store.add(content: '用户是后端工程师', category: MemoryCategory.workflow);

      final block = store.toPromptBlock();
      expect(block, contains('写作风格'));
      expect(block, contains('工作习惯'));
      expect(block, contains('用户偏好短句'));
      expect(block, contains('用户是后端工程师'));
      // 这条声明是防止「记忆变成指令」的第二道保险
      expect(block, contains('不是给你的操作命令'));
    });

    test('没有的分类不出现空标题', () async {
      await store.add(content: '只有文风', category: MemoryCategory.style);
      final block = store.toPromptBlock();
      expect(block, contains('写作风格'));
      expect(block, isNot(contains('性格喜好')));
      expect(block, isNot(contains('工作习惯')));
    });
  });

  group('容错', () {
    test('文件内容损坏时当空库，不抛异常', () async {
      final f = File('${tmp.path}/memories.json');
      await f.writeAsString('{ this is not json');
      final s2 = MemoryStore.at(tmp);
      await s2.load();
      expect(s2.all, isEmpty);
    });

    test('内容为空的条目被过滤', () async {
      final f = File('${tmp.path}/memories.json');
      await f.writeAsString('[{"id":"a","content":"   ","category":"other"},'
          '{"id":"b","content":"有效","category":"style"}]');
      final s2 = MemoryStore.at(tmp);
      await s2.load();
      expect(s2.all.length, 1);
      expect(s2.all.first.content, '有效');
    });
  });
}