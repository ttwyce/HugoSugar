import 'package:flutter_test/flutter_test.dart';
import 'package:hugosugar/core/ai/default_prompt.dart';
import 'package:hugosugar/core/settings/app_settings.dart';

/// System Prompt 可编辑（规格决议 5）。
///
/// 之前这份内容硬编码在 `_buildSystemPrompt()` 里，设置页只有一个
/// `onTap: () {}` 的占位项 —— 点了没反应。
///
/// 这里守两条容易退化的不变量：
///   1. 「空串 = 未覆盖」的语义（决定将来改默认值能否惠及老用户）
///   2. token 上限的下限保护（0 会让第一轮请求立刻失败）
void main() {
  group('默认 Prompt', () {
    test('包含规格要求的四节', () {
      expect(kDefaultSystemPrompt, contains('## 你的职责'));
      expect(kDefaultSystemPrompt, contains('## 文章规范'));
      expect(kDefaultSystemPrompt, contains('## 工具使用规则'));
      expect(kDefaultSystemPrompt, contains('## 行为边界'));
    });

    test('含 fetch_url 的硬约束（规格明确要求写进 Prompt）', () {
      expect(kDefaultSystemPrompt, contains('fetch_url'));
      expect(kDefaultSystemPrompt, contains('不要主动联网搜索'));
      expect(kDefaultSystemPrompt, contains('不要连续抓取'));
    });

    test('含 Front Matter 字段说明', () {
      expect(kDefaultSystemPrompt, contains('Front Matter'));
      expect(kDefaultSystemPrompt, contains('title'));
      expect(kDefaultSystemPrompt, contains('draft'));
    });

    test('不是空白', () {
      expect(kDefaultSystemPrompt.trim().isNotEmpty, isTrue);
    });
  });

  group('AppSettings 序列化', () {
    test('默认值：Prompt 覆盖为空串，token 上限 120000', () {
      const s = AppSettings();
      expect(s.aiSystemPrompt, '');
      expect(s.aiMaxTokensPerRound, 120000);
    });

    test('自定义 Prompt 能往返', () {
      const s = AppSettings(aiSystemPrompt: '你是一个严格的技术编辑。');
      final back = AppSettings.fromJson(s.toJson());
      expect(back.aiSystemPrompt, '你是一个严格的技术编辑。');
    });

    test('token 上限能往返', () {
      const s = AppSettings(aiMaxTokensPerRound: 50000);
      final back = AppSettings.fromJson(s.toJson());
      expect(back.aiMaxTokensPerRound, 50000);
    });

    test('旧版配置文件缺字段时回落默认值而不是 0', () {
      // 模拟升级前写下的 json：没有这两个键
      final old = <String, Object?>{
        'dateFormat': 'iso',
        'fileNameStyle': 'fromTitle',
        'aiReadNotes': false,
      };
      final s = AppSettings.fromJson(old);

      expect(s.aiSystemPrompt, '');
      // 关键：不能是 0，否则第一轮就「已超上限」
      expect(s.aiMaxTokensPerRound, 120000);
      expect(s.aiMaxTokensPerRound > 0, isTrue);
    });

    test('copyWith 不改动未传入的字段', () {
      const s = AppSettings(
        aiSystemPrompt: '自定义',
        aiMaxTokensPerRound: 8000,
      );
      final t = s.copyWith(authorName: 'octocat');

      expect(t.aiSystemPrompt, '自定义');
      expect(t.aiMaxTokensPerRound, 8000);
      expect(t.authorName, 'octocat');
    });

    test('copyWith 能把 Prompt 清空（恢复默认）', () {
      const s = AppSettings(aiSystemPrompt: '自定义');
      expect(s.copyWith(aiSystemPrompt: '').aiSystemPrompt, '');
    });
  });
}