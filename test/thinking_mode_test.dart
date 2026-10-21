import 'package:flutter_test/flutter_test.dart';
import 'package:hugosugar/core/ai/ai_endpoint.dart';
import 'package:hugosugar/core/ai/ai_message.dart';
import 'package:hugosugar/core/ai/context_compressor.dart';

void main() {
  group('ThinkingMode 序列化', () {
    test('默认是 none', () {
      const ep = AiEndpoint(id: 'a', name: 'n', baseUrl: 'https://x');
      expect(ep.thinkingMode, ThinkingMode.none);
    });

    test('toJson / fromJson 往返不丢', () {
      const ep = AiEndpoint(
        id: 'a',
        name: 'n',
        baseUrl: 'https://x',
        thinkingMode: ThinkingMode.enableThinking,
      );
      final back = AiEndpoint.fromJson(ep.toJson());
      expect(back.thinkingMode, ThinkingMode.enableThinking);
    });

    test('旧配置缺字段回落到 none', () {
      final back = AiEndpoint.fromJson({
        'id': 'a',
        'name': 'n',
        'baseUrl': 'https://x',
      });
      expect(back.thinkingMode, ThinkingMode.none);
    });

    test('未知值回落到 none，不抛异常', () {
      final back = AiEndpoint.fromJson({
        'id': 'a',
        'name': 'n',
        'baseUrl': 'https://x',
        'thinkingMode': 'something_new',
      });
      expect(back.thinkingMode, ThinkingMode.none);
    });

    test('只有 parseOnly / enableThinking 会显示思考内容', () {
      expect(ThinkingMode.parseOnly.showsReasoning, isTrue);
      expect(ThinkingMode.enableThinking.showsReasoning, isTrue);
      // o 系列不返回思考内容
      expect(ThinkingMode.reasoningEffort.showsReasoning, isFalse);
      expect(ThinkingMode.none.showsReasoning, isFalse);
    });
  });

  group('reasoning_content 解析', () {
    StreamAccumulator accOf(List<Map<String, dynamic>> chunks) {
      final a = StreamAccumulator();
      for (final c in chunks) {
        a.addChunk(c);
      }
      return a;
    }

    Map<String, dynamic> delta(Map<String, dynamic> d) => {
          'choices': [
            {'delta': d},
          ],
        };

    test('DeepSeek 的 reasoning_content 被累积', () {
      final a = accOf([
        delta({'reasoning_content': '先想一想'}),
        delta({'reasoning_content': '再想一想'}),
        delta({'content': '答案是 42'}),
      ]);
      expect(a.reasoning, '先想一想再想一想');
      expect(a.content, '答案是 42');
      expect(a.hasReasoning, isTrue);
    });

    test('兼容 reasoning 字段（OpenRouter 等）', () {
      final a = accOf([
        delta({'reasoning': '思考中'}),
        delta({'content': '答'}),
      ]);
      expect(a.reasoning, '思考中');
    });

    test('兼容 thinking 字段（Anthropic 风格）', () {
      final a = accOf([
        delta({'thinking': '想想'}),
        delta({'content': '答'}),
      ]);
      expect(a.reasoning, '想想');
    });

    test('普通模型没有思考内容时 reasoning 为空', () {
      final a = accOf([
        delta({'content': '直接回答'}),
      ]);
      expect(a.reasoning, isEmpty);
      expect(a.hasReasoning, isFalse);
    });

    test('思考与正文并行下发时不串味', () {
      final a = accOf([
        delta({'reasoning_content': 'R1', 'content': 'C1'}),
        delta({'reasoning_content': 'R2', 'content': 'C2'}),
      ]);
      expect(a.reasoning, 'R1R2');
      expect(a.content, 'C1C2');
    });
  });

  group('压缩阈值可配置', () {
    test('阈值以下不压缩', () {
      final c = const ContextCompressor(maxMessages: 10, keepRecent: 4);
      final msgs = List.generate(
        10,
        (i) => AiMessage(role: 'user', content: 'm$i'),
      );
      expect(c.compress(msgs).compressed, isFalse);
    });

    test('超过阈值触发压缩，并保留最近 N 条', () {
      final c = const ContextCompressor(maxMessages: 10, keepRecent: 4);
      final msgs = List.generate(
        12,
        (i) => AiMessage(role: 'user', content: 'm$i'),
      );
      final r = c.compress(msgs);
      expect(r.compressed, isTrue);
      expect(r.droppedCount, greaterThan(0));
      // 压缩后总条数应显著减少
      expect(r.messages.length, lessThan(msgs.length));
    });

    test('保留数 >= 阈值时不压缩（避免压完反而更长）', () {
      // 这是 ContextCompressor 里 needsCompression 的前提条件
      final c = const ContextCompressor(maxMessages: 5, keepRecent: 8);
      final msgs = List.generate(
        6,
        (i) => AiMessage(role: 'user', content: 'm$i'),
      );
      expect(c.compress(msgs).compressed, isFalse);
    });
  });
}