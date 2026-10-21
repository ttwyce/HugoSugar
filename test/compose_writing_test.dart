import 'package:flutter_test/flutter_test.dart';
import 'package:hugosugar/core/ai/ai_client.dart';
import 'package:hugosugar/core/ai/ai_controller.dart';
import 'package:hugosugar/core/ai/ai_endpoint.dart';
import 'package:hugosugar/core/ai/ai_message.dart';
import 'package:hugosugar/core/ai/cancel_token.dart';

/// 捕获发出去的 messages，并假装模型回了一段固定文本。
class _FakeClient extends AiClient {
  List<AiMessage>? captured;
  String reply = '# 标题\n\n这是生成的开头。';

  @override
  Future<void> streamChat({
    required AiEndpoint endpoint,
    required String apiKey,
    required List<AiMessage> messages,
    required StreamAccumulator accumulator,
    List<Map<String, dynamic>> tools = const [],
    void Function(String delta)? onDelta,
    void Function(String delta)? onReasoningDelta,
    Duration timeout = const Duration(seconds: 60),
    CancelToken? cancelToken,
    int maxRetries = 2,
    void Function(int attempt, int maxAttempts, Duration wait)? onRetry,
    ThinkingLevel thinkingLevel = ThinkingLevel.none,
  }) async {
    captured = messages;
    accumulator.addContent(reply);
    onDelta?.call(reply);
  }
}

/// 让 readKey 直接返回一把假 key。
class _FakeKeyStore implements AiKeyStore {
  @override
  Future<String?> read(String id) async => 'sk-test';
  @override
  Future<void> write(String id, String key) async {}
  @override
  Future<void> delete(String id) async {}
}

void main() {
  test('composeWriting 把指令与当前正文都送进 messages，且不进对话 session',
      () async {
    final fake = _FakeClient();
    final ctrl = AiController(client: fake);
    addTearDown(ctrl.dispose);
    ctrl.debugSetKeyStore(_FakeKeyStore());

    ctrl.debugSetConfig(const AiConfig(
      endpoints: [
        AiEndpoint(
          id: 'e1',
          name: '测试端点',
          baseUrl: 'https://api.example.com/v1',
          model: 'gpt-test',
        ),
      ],
      activeId: 'e1',
    ));

    String? streamed;
    final result = await ctrl.composeWriting(
      instruction: '帮我写一段开头',
      currentBody: '原有的一段正文',
      onDelta: (t) => streamed = t,
    );

    // 返回完整文本，且流式回调也拿到了
    expect(result, contains('这是生成的开头'));
    expect(streamed, contains('这是生成的开头'));

    // messages 结构：system + user
    final msgs = fake.captured!;
    expect(msgs.length, 2);
    expect(msgs[0].role, 'system');
    expect(msgs[1].role, 'user');

    // 指令与正文都进去了
    final userText = msgs[1].content;
    expect(userText, contains('帮我写一段开头'));
    expect(userText, contains('原有的一段正文'));

    // 不污染对话 session
    expect(ctrl.session, isNull);
  });

  test('未配置端点时抛 AiException', () async {
    final ctrl = AiController(client: _FakeClient());
    addTearDown(ctrl.dispose);
    ctrl.debugSetKeyStore(_FakeKeyStore());
    expect(
      () => ctrl.composeWriting(instruction: 'x', currentBody: ''),
      throwsA(isA<AiException>()),
    );
  });
}