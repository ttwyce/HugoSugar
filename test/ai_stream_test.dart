import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hugosugar/core/ai/ai_message.dart';
import 'package:hugosugar/core/ai/sse_parser.dart';

void main() {
  group('SseParser', () {
    test('完整事件一次喂入', () {
      final p = SseParser();
      final out = p.push('data: {"a":1}\n\ndata: {"b":2}\n\n');
      expect(out, ['{"a":1}', '{"b":2}']);
    });

    test('事件被网络分片切断，仍能正确拼回', () {
      final p = SseParser();
      // 第一片：事件还没完
      expect(p.push('data: {"content":"你'), isEmpty);
      // 第二片：补完
      expect(p.push('好"}\n\n'), ['{"content":"你好"}']);
    });

    test('一个分片里塞了多个事件', () {
      final p = SseParser();
      final out = p.push('data: a\n\ndata: b\n\ndata: c\n\n');
      expect(out, ['a', 'b', 'c']);
    });

    test('\\r\\n 分隔也能解析', () {
      final p = SseParser();
      final out = p.push('data: {"x":1}\r\n\r\n');
      expect(out, ['{"x":1}']);
    });

    test('[DONE] 原样保留，由调用方判断', () {
      final p = SseParser();
      final out = p.push('data: [DONE]\n\n');
      expect(out, ['[DONE]']);
    });

    test('忽略 event: / id: 等非 data 行', () {
      final p = SseParser();
      final out = p.push('event: message\nid: 3\ndata: {"k":1}\n\n');
      expect(out, ['{"k":1}']);
    });

    test('flush 吐出末尾没有空行的残留', () {
      final p = SseParser();
      expect(p.push('data: {"tail":1}'), isEmpty);
      expect(p.flush(), ['{"tail":1}']);
    });

    test('半个 UTF-8 字符被切开时不崩（上层按字节流解码处理）', () {
      // 这里覆盖的是「文本已经被正确解码，但分片边界在 JSON 中间」
      final p = SseParser();
      expect(p.push('data: {"a":"'), isEmpty);
      expect(p.push('中"}\n\n'), ['{"a":"中"}']);
    });
  });

  group('StreamAccumulator 文本', () {
    test('多 delta 拼接', () {
      final a = StreamAccumulator();
      a.addChunk({
        'choices': [
          {
            'delta': {'content': 'Hello'}
          }
        ]
      });
      a.addChunk({
        'choices': [
          {
            'delta': {'content': ' world'}
          }
        ]
      });
      expect(a.content, 'Hello world');
      expect(a.hasToolCalls, isFalse);
    });

    test('读取 usage', () {
      final a = StreamAccumulator();
      a.addChunk({
        'choices': [],
        'usage': {'prompt_tokens': 12, 'completion_tokens': 34},
      });
      expect(a.promptTokens, 12);
      expect(a.completionTokens, 34);
    });
  });

  group('StreamAccumulator 工具调用拼装', () {
    // 这是整个流式实现里最容易写错的点：
    // 参数是分片下发的，必须按 index 归并后拼接
    test('参数分三片下发，拼成完整 JSON', () {
      final a = StreamAccumulator();

      a.addChunk({
        'choices': [
          {
            'delta': {
              'tool_calls': [
                {
                  'index': 0,
                  'id': 'call_a',
                  'function': {'name': 'read_note'},
                }
              ]
            }
          }
        ]
      });
      a.addChunk({
        'choices': [
          {
            'delta': {
              'tool_calls': [
                {
                  'index': 0,
                  'function': {'arguments': '{"id":'}
                }
              ]
            }
          }
        ]
      });
      a.addChunk({
        'choices': [
          {
            'delta': {
              'tool_calls': [
                {
                  'index': 0,
                  'function': {'arguments': '"abc"}'}
                }
              ]
            }
          }
        ]
      });

      final calls = a.toolCalls;
      expect(calls.length, 1);
      expect(calls.first.id, 'call_a');
      expect(calls.first.name, 'read_note');
      expect(calls.first.arguments, '{"id":"abc"}');
      // 拼出来的必须是合法 JSON
      expect(jsonDecode(calls.first.arguments), {'id': 'abc'});
    });

    test('两个工具调用并发，按 index 分开归并', () {
      final a = StreamAccumulator();

      a.addChunk({
        'choices': [
          {
            'delta': {
              'tool_calls': [
                {'index': 0, 'id': 'c0', 'function': {'name': 'list_notes'}},
                {'index': 1, 'id': 'c1', 'function': {'name': 'read_post'}},
              ]
            }
          }
        ]
      });
      a.addChunk({
        'choices': [
          {
            'delta': {
              'tool_calls': [
                {'index': 0, 'function': {'arguments': '{"limit":5}'}},
                {'index': 1, 'function': {'arguments': '{"path":"a.md"}'}},
              ]
            }
          }
        ]
      });

      final calls = a.toolCalls;
      expect(calls.length, 2);
      expect(calls[0].name, 'list_notes');
      expect(calls[0].arguments, '{"limit":5}');
      expect(calls[1].name, 'read_post');
      expect(calls[1].arguments, '{"path":"a.md"}');
    });

    test('缺少 index 时按 0 处理', () {
      final a = StreamAccumulator();
      a.addChunk({
        'choices': [
          {
            'delta': {
              'tool_calls': [
                {'id': 'x', 'function': {'name': 'f'}}
              ]
            }
          }
        ]
      });
      a.addChunk({
        'choices': [
          {
            'delta': {
              'tool_calls': [
                {
                  'function': {'arguments': '{}'}
                }
              ]
            }
          }
        ]
      });
      expect(a.toolCalls.single.arguments, '{}');
    });

    test('没有 name 的残片不会被当成有效调用', () {
      final a = StreamAccumulator();
      a.addChunk({
        'choices': [
          {
            'delta': {
              'tool_calls': [
                {
                  'index': 0,
                  'function': {'arguments': '{"a":1}'}
                }
              ]
            }
          }
        ]
      });
      // 只拼了参数、没给名字 → 丢弃，避免执行一个不知道名字的工具
      expect(a.hasToolCalls, isFalse);
    });

    test('同时有文本和工具调用', () {
      final a = StreamAccumulator();
      a.addChunk({
        'choices': [
          {
            'delta': {
              'content': '我先查一下。',
              'tool_calls': [
                {'index': 0, 'id': 'c', 'function': {'name': 'list_notes'}}
              ]
            }
          }
        ]
      });
      expect(a.content, '我先查一下。');
      expect(a.hasToolCalls, isTrue);
    });
  });

  group('token 估算', () {
    test('空串为 0', () {
      expect(estimateTokens(''), 0);
    });

    test('中文按字计', () {
      expect(estimateTokens('你好世界'), 4);
    });

    test('英文按 4 字符约 1 token', () {
      expect(estimateTokens('abcdefgh'), 2);
    });

    test('中英混合', () {
      // 2 个汉字 + 4 个英文字符 = 2 + 1
      expect(estimateTokens('你好abcd'), 3);
    });

    test('消息列表计入 role 开销', () {
      final t = estimateMessagesTokens([
        const AiMessage(role: 'user', content: '你好'),
      ]);
      // 4 固定开销 + 2 汉字
      expect(t, 6);
    });
  });

  group('AiMessage 序列化', () {
    test('assistant + tool_calls 的 content 为 null', () {
      const m = AiMessage(
        role: 'assistant',
        toolCalls: [
          AiToolCall(id: 'c1', name: 'f', arguments: '{}')
        ],
      );
      final j = m.toApiJson();
      expect(j['content'], isNull);
      expect((j['tool_calls'] as List).length, 1);
    });

    test('tool 消息带 tool_call_id', () {
      const m = AiMessage(
        role: 'tool',
        content: '结果',
        toolCallId: 'c1',
        name: 'f',
      );
      final j = m.toApiJson();
      expect(j['tool_call_id'], 'c1');
      expect(j['name'], 'f');
    });

    test('本地 JSON 往返不丢字段', () {
      const m = AiMessage(
        role: 'assistant',
        content: 'hi',
        toolCalls: [
          AiToolCall(id: 'c', name: 'n', arguments: '{"a":1}')
        ],
      );
      final back = AiMessage.fromJson(m.toJson());
      expect(back.content, 'hi');
      expect(back.toolCalls.single.name, 'n');
      expect(back.toolCalls.single.arguments, '{"a":1}');
    });
  });
}