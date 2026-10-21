import 'package:flutter_test/flutter_test.dart';
import 'package:hugosugar/core/ai/ai_endpoint.dart';
import 'package:hugosugar/core/ai/ai_message.dart';
import 'package:hugosugar/core/ai/context_compressor.dart';

void main() {
  group('ThinkingLevel 档位', () {
    test('none 表示不思考', () {
      expect(ThinkingLevel.none.isThinking, isFalse);
    });

    test('其余档位都算思考', () {
      expect(ThinkingLevel.low.isThinking, isTrue);
      expect(ThinkingLevel.medium.isThinking, isTrue);
      expect(ThinkingLevel.high.isThinking, isTrue);
      expect(ThinkingLevel.xhigh.isThinking, isTrue);
    });

    test('effortValue 映射：xhigh 降级为 high', () {
      expect(ThinkingLevel.low.effortValue, 'low');
      expect(ThinkingLevel.medium.effortValue, 'medium');
      expect(ThinkingLevel.high.effortValue, 'high');
      // xhigh 不在 o 系列允许值内，降级而不是报 400
      expect(ThinkingLevel.xhigh.effortValue, 'high');
    });

    test('fromId 往返', () {
      for (final v in ThinkingLevel.values) {
        expect(ThinkingLevel.fromId(v.id), v);
      }
    });

    test('未知 id 回落到 none', () {
      expect(ThinkingLevel.fromId('whatever'), ThinkingLevel.none);
      expect(ThinkingLevel.fromId(null), ThinkingLevel.none);
    });
  });

  group('ThinkingProtocol 协议', () {
    test('只有 reasoningEffort 支持档位', () {
      expect(ThinkingProtocol.reasoningEffort.supportsLevels, isTrue);
      expect(ThinkingProtocol.enableThinking.supportsLevels, isFalse);
      expect(ThinkingProtocol.alwaysOn.supportsLevels, isFalse);
      expect(ThinkingProtocol.off.supportsLevels, isFalse);
    });

    test('只有 alwaysOn / enableThinking 会返回思考内容', () {
      expect(ThinkingProtocol.alwaysOn.returnsReasoning, isTrue);
      expect(ThinkingProtocol.enableThinking.returnsReasoning, isTrue);
      // o 系列不返回思考内容
      expect(ThinkingProtocol.reasoningEffort.returnsReasoning, isFalse);
      expect(ThinkingProtocol.off.returnsReasoning, isFalse);
    });

    test('兼容旧 id：parse_only -> alwaysOn', () {
      expect(ThinkingProtocol.fromId('parse_only'), ThinkingProtocol.alwaysOn);
    });

    test('未知 id 回落到 off', () {
      expect(ThinkingProtocol.fromId('bogus'), ThinkingProtocol.off);
    });
  });

  group('AiEndpoint 序列化', () {
    test('默认协议是 off', () {
      const ep = AiEndpoint(id: 'a', name: 'n', baseUrl: 'https://x');
      expect(ep.thinkingProtocol, ThinkingProtocol.off);
    });

    test('toJson / fromJson 往返不丢', () {
      const ep = AiEndpoint(
        id: 'a',
        name: 'n',
        baseUrl: 'https://x',
        thinkingProtocol: ThinkingProtocol.enableThinking,
      );
      final back = AiEndpoint.fromJson(ep.toJson());
      expect(back.thinkingProtocol, ThinkingProtocol.enableThinking);
    });

    test('旧配置文件（字段名 thinkingMode）能读', () {
      final back = AiEndpoint.fromJson({
        'id': 'a',
        'name': 'n',
        'baseUrl': 'https://x',
        'thinkingMode': 'reasoning_effort',
      });
      expect(back.thinkingProtocol, ThinkingProtocol.reasoningEffort);
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

    test('兼容 reasoning / thinking 字段', () {
      expect(accOf([delta({'reasoning': '思考中'})]).reasoning, '思考中');
      expect(accOf([delta({'thinking': '想想'})]).reasoning, '想想');
    });

    test('普通模型没有思考内容', () {
      final a = accOf([delta({'content': '直接回答'})]);
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

    test('reset 清空一切（重试用）', () {
      final a = accOf([delta({'reasoning_content': '想', 'content': '答'})]);
      a.reset();
      expect(a.reasoning, isEmpty);
      expect(a.content, isEmpty);
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

    test('超过阈值触发压缩', () {
      final c = const ContextCompressor(maxMessages: 10, keepRecent: 4);
      final msgs = List.generate(
        12,
        (i) => AiMessage(role: 'user', content: 'm$i'),
      );
      final r = c.compress(msgs);
      expect(r.compressed, isTrue);
      expect(r.droppedCount, greaterThan(0));
      expect(r.messages.length, lessThan(msgs.length));
    });

    test('保留数 >= 阈值时不压缩', () {
      final c = const ContextCompressor(maxMessages: 5, keepRecent: 8);
      final msgs = List.generate(
        6,
        (i) => AiMessage(role: 'user', content: 'm$i'),
      );
      expect(c.compress(msgs).compressed, isFalse);
    });
  });
}