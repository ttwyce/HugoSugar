import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hugosugar/core/ai/memory_store.dart';
import 'package:hugosugar/core/ai/skill_store.dart';
import 'package:hugosugar/core/settings/app_settings.dart';

MemoryStore _fresh() =>
    MemoryStore(File('/tmp/nonexistent_${DateTime.now().microsecondsSinceEpoch}.json'));

void main() {
  group('记忆冲突检测', () {
    test('意思相反的两句会被识别为冲突', () async {
      // 这是真会发生的：模型今天听用户说「喜欢短句」，明天听成「不喜欢短句」
      // 两条都写进去，之后每轮 Prompt 都在拉锯。
      final s = _fresh();
      await s.add(content: '用户喜欢短句', category: MemoryCategory.style);

      final c = s.findConflict('用户不喜欢短句');
      expect(c, isNotNull);
      expect(c!.content, contains('喜欢短句'));
    });

    test('重复内容不算冲突（交给 findSimilar 处理）', () async {
      final s = _fresh();
      await s.add(content: '用户喜欢短句', category: MemoryCategory.style);
      expect(s.findConflict('用户喜欢短句。'), isNull);
    });

    test('两件不相干的事不算冲突', () async {
      final s = _fresh();
      await s.add(content: '用户喜欢短句', category: MemoryCategory.style);
      expect(s.findConflict('用户用 Rust 写后端'), isNull);
    });

    test('极性相同只是表述不同，不算冲突', () async {
      final s = _fresh();
      await s.add(content: '用户不喜欢形容词堆砌', category: MemoryCategory.style);
      expect(s.findConflict('用户不喜欢华丽辞藻'), isNull);
    });

    test('空库不会误报', () async {
      final s = _fresh();
      expect(s.findConflict('用户喜欢短句'), isNull);
    });
  });

  group('hitCount 累加', () {
    test('注入后每条都 +1', () async {
      final s = _fresh();
      await s.add(content: '用户喜欢短句', category: MemoryCategory.style);
      await s.add(content: '用户写 Go', category: MemoryCategory.workflow);
      expect(s.all.map((m) => m.hitCount), [0, 0]);

      s.markHitAll();
      expect(s.all.map((m) => m.hitCount), [1, 1]);

      s.markHitAll();
      expect(s.all.map((m) => m.hitCount), [2, 2]);
    });

    test('空库调用不报错', () async {
      final s = _fresh();
      expect(() => s.markHitAll(), returnsNormally);
    });
  });

  group('Skill', () {
    test('内置 Skill 至少有润色/精简/技术博客/挑毛病/翻译', () {
      final names = kBuiltinSkills.map((s) => s.name).toSet();
      expect(names, containsAll(['润色', '精简', '技术博客', '挑毛病', '翻译']));
    });

    test('每个内置 Skill 都有非空 prompt 和 description', () {
      for (final s in kBuiltinSkills) {
        expect(s.prompt.trim(), isNotEmpty, reason: '${s.name} 缺 prompt');
        expect(s.description.trim(), isNotEmpty, reason: '${s.name} 缺说明');
        expect(s.builtin, isTrue);
      }
    });

    test('内置 Skill id 唯一', () {
      final ids = kBuiltinSkills.map((s) => s.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('promptBlockFor 只拼启用项，且带上名字', () {
      final store = SkillStore(File('/tmp/sk_${DateTime.now().microsecondsSinceEpoch}.json'));
      final block = store.promptBlockFor(['builtin_polish', 'builtin_translate']);
      expect(block, contains('润色'));
      expect(block, contains('翻译'));
      expect(block, isNot(contains('精简')));
      // 要有角色声明，说明这是「怎么做」而不是内容本身
      expect(block, contains('工作模式'));
    });

    test('空列表返回空串（不注入无用段落）', () {
      final store = SkillStore(File('/tmp/sk2_${DateTime.now().microsecondsSinceEpoch}.json'));
      expect(store.promptBlockFor(const []), '');
    });

    test('未知 id 被忽略，不会拼出空标题', () {
      final store = SkillStore(File('/tmp/sk3_${DateTime.now().microsecondsSinceEpoch}.json'));
      final block = store.promptBlockFor(['not_exist_id']);
      expect(block, '');
    });

    test('自建 Skill 能增删改，且不能改内置', () async {
      final f = File('/tmp/sk4_${DateTime.now().microsecondsSinceEpoch}.json');
      addTearDown(() async {
        if (await f.exists()) await f.delete();
      });
      final store = SkillStore(f);
      final s = await store.add(name: '口语化', prompt: '改得像聊天');
      expect(store.custom, hasLength(1));

      // 内置的改不了
      expect(await store.update('builtin_polish', name: 'X'), isFalse);

      expect(await store.update(s.id, name: '更口语'), isTrue);
      expect(store.byId(s.id)!.name, '更口语');

      expect(await store.remove(s.id), isTrue);
      expect(store.custom, isEmpty);
    });

    test('重复 load 不会把内置 Skill 存进文件', () async {
      final f = File('/tmp/sk5_${DateTime.now().microsecondsSinceEpoch}.json');
      addTearDown(() async {
        if (await f.exists()) await f.delete();
      });
      final store = SkillStore(f);
      await store.add(name: '自建', prompt: 'x');
      await store.load();
      // 文件里只该有一条（自建的），内置的从代码来
      expect(store.custom.length, 1);
      expect(store.all.length, kBuiltinSkills.length + 1);
    });
  });

  group('AppSettings 新字段', () {
    test('默认值：工具全开、无 Skill、默认强调色', () {
      const s = AppSettings();
      expect(s.aiDisabledTools, isEmpty);
      expect(s.skillIds, isEmpty);
      expect(s.accentPreset, 0);
    });

    test('序列化往返保留三个新字段', () {
      const s = AppSettings(
        aiDisabledTools: ['write_post', 'fetch_url'],
        skillIds: ['builtin_polish'],
        accentPreset: 3,
      );
      final back = AppSettings.fromJson(s.toJson());
      expect(back.aiDisabledTools, ['write_post', 'fetch_url']);
      expect(back.skillIds, ['builtin_polish']);
      expect(back.accentPreset, 3);
    });

    test('旧配置文件（无新字段）能读，落到安全默认', () {
      final legacy = {
        'dateFormat': 'iso',
        'fileNameStyle': 'fromTitle',
      };
      final s = AppSettings.fromJson(Map<String, Object?>.from(legacy));
      expect(s.aiDisabledTools, isEmpty);
      expect(s.skillIds, isEmpty);
      expect(s.accentPreset, 0);
    });

    test('accentPreset 越界会被夹住', () {
      final s = AppSettings.fromJson(
        Map<String, Object?>.from({'accentPreset': 999}),
      );
      expect(s.accentPreset, lessThanOrEqualTo(20));
    });
  });
}