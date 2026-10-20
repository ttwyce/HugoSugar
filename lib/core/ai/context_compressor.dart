import 'ai_message.dart';

/// 上下文压缩。
///
/// ## 为什么需要
///
/// 对话一长，两件事同时发生：
/// 1. 请求体越来越大 → 越来越慢、越来越贵
/// 2. 超过模型上下文窗口 → 直接报错，整个对话无法继续
///
/// 而绝大多数历史内容对当前这轮没有价值 ——
/// 用户问「帮我把刚才那篇改短点」时，真正需要的是
/// 「刚才那篇」，不是三小时前那一整段闲聊。
///
/// ## 策略
///
/// 分三段处理，而不是简单「只留最近 N 条」：
///
/// ```
/// [系统提示]       永远保留
/// [较早消息摘要]    被折叠成一段文字
/// [最近 N 条]      原样保留
/// ```
///
/// 只留最近 N 条的问题：用户第一轮说「我在写一本关于 Rust 的书」，
/// 聊了 50 轮之后这条被裁掉，模型就完全不知道背景了。
/// 折叠成摘要能保住这类关键前提。
///
/// ## 摘要怎么来
///
/// **不用 LLM 做摘要**。理由是：
/// - 每次压缩都要额外一次 API 调用，用户等不了
/// - 摘要本身可能失败，失败时怎么办很麻烦
/// - 规则化摘要（谁说了什么 + 前若干字）已经足够保住上下文
///
/// 这是明确的能力取舍：省一次调用，换来的是摘要不够精炼。
class ContextCompressor {
  const ContextCompressor({
    this.maxMessages = 20,
    this.keepRecent = 8,
    this.maxSummaryChars = 1200,
    this.maxCharsPerMessage = 50,
    this.maxSummaryEntries = 12,
  });

  /// 超过多少条消息开始压缩
  final int maxMessages;

  /// 最近多少条原样保留
  final int keepRecent;

  /// 摘要文本的上限（防止摘要本身撑爆上下文）
  final int maxSummaryChars;

  /// 摘要里每条消息最多留多少字。
  ///
  /// 一开始写死 120，实测 38 条旧消息折叠后仍有 4560 字，
  /// 比原文还占地方 —— 压缩等于白做。
  /// 50 字足够提示「聊过什么」，细节本来就该重新问。
  final int maxCharsPerMessage;

  /// 摘要里最多列多少条旧消息。
  ///
  /// 只限每条长度是不够的：旧消息有 100 条时，
  /// 100 × 50 = 5000 字，摘要本身就撑爆了。
  /// 超出的部分只保留一条「另有 N 条」的说明。
  final int maxSummaryEntries;

  /// 是否需要压缩。
  ///
  /// 同时要求超过 [maxMessages] 和 [keepRecent]：如果只判前者，
  /// 在 `maxMessages < keepRecent` 这种配置下会出现
  /// 「判定要压缩，但保留的条数比阈值还多」，压缩完反而更长。
  bool needsCompression(int messageCount) =>
      messageCount > maxMessages && messageCount > keepRecent;

  /// 压缩消息列表。
  ///
  /// 返回新列表：开头的 system 消息原样保留，随后是一条摘要，
  /// 再后面是最近若干条原文。未触发压缩时原样返回。
  CompressionResult compress(List<AiMessage> messages) {
    if (!needsCompression(messages.length)) {
      return CompressionResult(
        messages: messages,
        compressed: false,
        droppedCount: 0,
        summary: '',
      );
    }

    // 保留开头的 system 消息（系统提示不能丢）
    final systemMessages = <AiMessage>[];
    var rest = messages;
    while (rest.isNotEmpty && rest.first.role == 'system') {
      systemMessages.add(rest.first);
      rest = rest.sublist(1);
    }

    if (rest.length <= keepRecent) {
      return CompressionResult(
        messages: messages,
        compressed: false,
        droppedCount: 0,
        summary: '',
      );
    }

    final splitAt = rest.length - keepRecent;
    final older = rest.sublist(0, splitAt);
    final recent = rest.sublist(splitAt);

    final summary = _summarize(older);
    if (summary.isEmpty) {
      // 摘要为空（旧消息全是空文本）：
      // 直接丢弃，不注入空的 system 块 —— 那只会白占 token
      return CompressionResult(
        messages: [...systemMessages, ...recent],
        compressed: true,
        droppedCount: older.length,
        summary: '',
      );
    }

    return CompressionResult(
      messages: [
        ...systemMessages,
        AiMessage(role: 'system', content: summary),
        ...recent,
      ],
      compressed: true,
      droppedCount: older.length,
      summary: summary,
    );
  }

  /// 把较早的消息折叠成一段可读的摘要。
  String _summarize(List<AiMessage> older) {
    final valid = older.where((m) => m.content.trim().isNotEmpty).toList();

    // 一条有效内容都没有 → 不生成摘要
    if (valid.isEmpty) return '';

    // 只取最近的 maxSummaryEntries 条。
    //
    // 为什么不取最早的：越靠近现在的消息越可能还被引用
    //（「刚才说的那个」指的就是最近几轮）。
    // 而最早的若干条往往只是开场寒暄，信息密度最低。
    final picked = valid.length > maxSummaryEntries
        ? valid.sublist(valid.length - maxSummaryEntries)
        : valid;
    final omitted = valid.length - picked.length;

    final buf = StringBuffer();
    buf.writeln('## 之前的对话（已折叠）');
    buf.writeln();
    if (omitted > 0) {
      buf.writeln('（更早的 $omitted 条已省略）');
    }
    for (final m in picked) {
      final who = m.isUser ? '用户' : '助手';
      buf.writeln('- $who：${_squash(m.content)}');
    }

    var text = buf.toString().trim();

    // 超长时保留开头和结尾。
    // 只截开头会丢掉「最后聊到哪儿」，那恰恰是最有用的部分。
    if (text.length > maxSummaryChars) {
      final headLen = (maxSummaryChars * 0.6).floor();
      final tailLen = maxSummaryChars - headLen - 20;
      if (tailLen > 0) {
        text = '${text.substring(0, headLen)}\n…（中间省略）…\n'
            '${text.substring(text.length - tailLen)}';
      }
    }
    return text;
  }

  /// 把一条消息压成单行、限长。
  ///
  /// 摘要的目的是「提醒模型有过这回事」，不是复述全文。
  /// 全文还在原始 session 里，用户随时能看。
  String _squash(String s) {
    final one = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (one.length <= maxCharsPerMessage) return one;
    return '${one.substring(0, maxCharsPerMessage)}…';
  }
}

class CompressionResult {
  const CompressionResult({
    required this.messages,
    required this.compressed,
    required this.droppedCount,
    required this.summary,
  });

  final List<AiMessage> messages;

  /// 是否真的做了压缩
  final bool compressed;

  /// 被折叠进摘要的消息条数
  final int droppedCount;

  /// 摘要文本（未压缩时为空）
  final String summary;
}