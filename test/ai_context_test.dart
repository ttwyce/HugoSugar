import 'package:flutter_test/flutter_test.dart';
import 'package:hugosugar/core/ai/ai_message.dart';
import 'package:hugosugar/core/ai/cancel_token.dart';
import 'package:hugosugar/core/ai/context_compressor.dart';

void main() {
  AiMessage u(String t) => AiMessage(role: 'user', content: t);
  AiMessage a(String t) => AiMessage(role: 'assistant', content: t);
  AiMessage s(String t) => AiMessage(role: 'system', content: t);

  /// 常用配置：超过 4 条开始压缩，保留最近 2 条。
  /// 两者必须满足 maxMessages > keepRecent，否则压缩无意义。
  const small = ContextCompressor(maxMessages: 4, keepRecent: 2);

  group('CancelToken', () {
    test('初始未取消', () {
      expect(CancelToken().isCancelled, isFalse);
    });

    test('cancel 后置位', () {
      final t = CancelToken()..cancel();
      expect(t.isCancelled, isTrue);
    });

    test('未取消时 throwIfCancelled 不抛', () {
      expect(() => CancelToken().throwIfCancelled(), returnsNormally);
    });

    test('已取消时抛 CancelledException', () {
      final t = CancelToken()..cancel();
      expect(() => t.throwIfCancelled(), throwsA(isA<CancelledException>()));
    });

    test('重复 cancel 无害', () {
      final t = CancelToken()
        ..cancel()
        ..cancel();
      expect(t.isCancelled, isTrue);
    });

    test('异常文案是「已取消」', () {
      expect(const CancelledException().toString(), '已取消');
    });
  });

  group('ContextCompressor 触发条件', () {
    test('未超阈值不压缩', () {
      final r = small.compress(List.generate(4, (i) => u('m$i')));
      expect(r.compressed, isFalse);
      expect(r.messages.length, 4);
      expect(r.droppedCount, 0);
    });

    test('超过阈值触发压缩', () {
      final r = small.compress(List.generate(10, (i) => u('m$i')));
      expect(r.compressed, isTrue);
      expect(r.droppedCount, 8);
      // 摘要 1 条 + 最近 2 条
      expect(r.messages.length, 3);
    });

    test('keepRecent 大于 maxMessages 时不会误判', () {
      // 这种配置本身不合理，但也不能让压缩「越压越长」
      const weird = ContextCompressor(maxMessages: 2, keepRecent: 10);
      final r = weird.compress(List.generate(5, (i) => u('m$i')));
      expect(r.compressed, isFalse);
    });

    test('needsCompression 边界', () {
      expect(small.needsCompression(4), isFalse);
      expect(small.needsCompression(5), isTrue);
    });
  });

  group('ContextCompressor 保留策略', () {
    test('最近消息原样保留', () {
      final msgs = [
        u('old1'), u('old2'), u('old3'),
        u('recent1'), u('recent2'),
      ];
      final r = small.compress(msgs);
      expect(r.messages.last.content, 'recent2');
      expect(r.messages[r.messages.length - 2].content, 'recent1');
    });

    test('system 消息永远排在最前', () {
      final msgs = [s('你是写作助手'), ...List.generate(10, (i) => u('m$i'))];
      final r = small.compress(msgs);
      expect(r.messages.first.role, 'system');
      expect(r.messages.first.content, '你是写作助手');
    });

    test('摘要放在 system 之后、最近消息之前', () {
      final msgs = [s('系统'), ...List.generate(10, (i) => u('m$i'))];
      final r = small.compress(msgs);
      expect(r.messages[0].role, 'system');
      expect(r.messages[0].content, '系统');
      expect(r.messages[1].role, 'system');
      expect(r.messages[1].content.contains('之前的对话'), isTrue);
    });
  });

  group('ContextCompressor 摘要内容', () {
    test('保留早期关键前提', () {
      final msgs = [
        u('我在写一本关于 Rust 的书'),
        ...List.generate(6, (i) => a('收到$i')),
      ];
      final r = small.compress(msgs);
      // 关键背景丢了模型就完全不知道在聊什么
      expect(r.summary.contains('Rust'), isTrue);
    });

    test('标明说话人', () {
      final msgs = [u('用户的话'), a('助手的话'), u('x'), u('y'), u('新')];
      final r = small.compress(msgs);
      expect(r.summary.contains('用户'), isTrue);
      expect(r.summary.contains('助手'), isTrue);
    });

    test('长消息被截断，不整段搬进摘要', () {
      final msgs = [u('x' * 500), u('a'), u('b'), u('c'), u('新')];
      final r = small.compress(msgs);
      // 每条限 80 字，摘要总长必须远小于原文的 500
      expect(r.summary.length, lessThan(400));
      expect(r.summary.contains('…'), isTrue);
    });

    test('摘要总长受 maxSummaryChars 限制', () {
      const c = ContextCompressor(
        maxMessages: 4,
        keepRecent: 2,
        maxSummaryChars: 200,
      );
      final msgs = [
        ...List.generate(30, (i) => u('第$i条：${'内容' * 60}')),
        u('新1'),
        u('新2'),
      ];
      final r = c.compress(msgs);
      // 允许一点溢出（分隔符），但不能放任
      expect(r.summary.length, lessThanOrEqualTo(260));
    });

    test('旧消息全是空文本时不生成空摘要', () {
      // 前 3 条（被折叠的部分）全部是空白，才能验证「不注入空摘要」
      final msgs = [u('  '), u(''), u('   '), u('x'), u('新')];
      final r = small.compress(msgs);
      expect(r.summary, isEmpty);
      // 不能注入一个空的 system 块白占 token
      expect(
        r.messages.where((m) => m.role == 'system' && m.content.trim().isEmpty).length,
        0,
      );
    });
  });

  group('ContextCompressor 效果', () {
    test('压缩后 token 明显下降', () {
      final msgs = List.generate(
        40,
        (i) => u('这是第 $i 条消息，${'内容' * 20}'),
      );
      final before = estimateMessagesTokens(msgs);
      final after = estimateMessagesTokens(small.compress(msgs).messages);
      // 压缩有没有意义就看这个比值
      expect(after, lessThan(before * 0.5));
    });

    test('压缩后消息条数下降', () {
      final msgs = List.generate(40, (i) => u('m$i'));
      final r = small.compress(msgs);
      expect(r.messages.length, lessThan(msgs.length));
    });
  });
}