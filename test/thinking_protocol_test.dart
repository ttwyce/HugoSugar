import 'package:flutter_test/flutter_test.dart';
import 'package:hugosugar/core/ai/ai_endpoint.dart';

void main() {
  group('按模型名推断思考协议', () {
    test('OpenAI o 系列走 reasoning_effort', () {
      expect(ThinkingProtocol.infer('o1'), ThinkingProtocol.reasoningEffort);
      expect(ThinkingProtocol.infer('o3-mini'), ThinkingProtocol.reasoningEffort);
      expect(ThinkingProtocol.infer('o4-mini'), ThinkingProtocol.reasoningEffort);
      expect(ThinkingProtocol.infer('openai/o3'), ThinkingProtocol.reasoningEffort);
      expect(ThinkingProtocol.infer('gpt-5'), ThinkingProtocol.reasoningEffort);
    });

    test('Qwen3 / GLM 混合模型走 enable_thinking', () {
      expect(ThinkingProtocol.infer('qwen3-235b'), ThinkingProtocol.enableThinking);
      expect(ThinkingProtocol.infer('Qwen3-32B'), ThinkingProtocol.enableThinking);
      expect(ThinkingProtocol.infer('glm-4.5'), ThinkingProtocol.enableThinking);
      expect(ThinkingProtocol.infer('qwq-32b'), ThinkingProtocol.enableThinking);
    });

    test('R1 系列永远思考，不发参数', () {
      expect(ThinkingProtocol.infer('deepseek-r1'), ThinkingProtocol.alwaysOn);
      expect(ThinkingProtocol.infer('deepseek-reasoner'), ThinkingProtocol.alwaysOn);
      expect(ThinkingProtocol.infer('r1-distill-qwen-7b'), ThinkingProtocol.alwaysOn);
    });

    test('认不出的模型默认发 enable_thinking，而不是什么都不发', () {
      // 这是关键取舍：宁可多发一个字段（服务端不认会自动降级），
      // 也不能默认什么都不发，否则用户选了「深度」等于没选。
      expect(ThinkingProtocol.infer('some-unknown-model'),
          ThinkingProtocol.enableThinking);
      expect(ThinkingProtocol.infer(''), ThinkingProtocol.enableThinking);
    });

    test('不会把 deepseek-chat 误判成 R1', () {
      // deepseek-chat 是 V3，不思考；它名字里没有 r1
      expect(ThinkingProtocol.infer('deepseek-chat'),
          ThinkingProtocol.enableThinking);
    });

    test('不会把 o1 之外的含 o 名字误判', () {
      // "solo-1" 里虽然有 o1，但不是模型名
      expect(ThinkingProtocol.infer('solo-1'), ThinkingProtocol.enableThinking);
      expect(ThinkingProtocol.infer('koto-13b'), ThinkingProtocol.enableThinking);
    });
  });

  group('effectiveProtocol 的优先级', () {
    test('用户显式配过就用用户的', () {
      const ep = AiEndpoint(
        id: 'a',
        name: 'n',
        baseUrl: 'https://x',
        model: 'qwen3-32b',
        thinkingProtocol: ThinkingProtocol.alwaysOn,
      );
      expect(ep.effectiveProtocol, ThinkingProtocol.alwaysOn);
    });

    test('没配过（off）就按模型名推断', () {
      const ep = AiEndpoint(
        id: 'a',
        name: 'n',
        baseUrl: 'https://x',
        model: 'deepseek-r1',
      );
      expect(ep.effectiveProtocol, ThinkingProtocol.alwaysOn);
    });

    test('新建端点默认 off，但 effective 不会是 off', () {
      const ep = AiEndpoint(id: 'a', name: 'n', baseUrl: 'https://x');
      expect(ep.thinkingProtocol, ThinkingProtocol.off);
      expect(ep.effectiveProtocol, isNot(ThinkingProtocol.off));
    });
  });
}
