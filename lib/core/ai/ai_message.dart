import 'dart:convert';

/// 一条对话消息。
class AiMessage {
  const AiMessage({
    required this.role,
    this.content = '',
    this.toolCalls = const [],
    this.toolCallId = '',
    this.name = '',
  });

  /// system / user / assistant / tool
  final String role;
  final String content;

  /// assistant 发起工具调用时为非空
  final List<AiToolCall> toolCalls;

  /// role == tool 时，对应哪个调用
  final String toolCallId;

  /// role == tool 时，工具名（部分服务端要求）
  final String name;

  bool get isUser => role == 'user';
  bool get isAssistant => role == 'assistant';
  bool get isTool => role == 'tool';

  Map<String, dynamic> toApiJson() {
    final m = <String, dynamic>{'role': role};
    // assistant + tool_calls 时 content 允许为 null，
    // 但部分兼容实现不接受 null，给空串更稳
    m['content'] = content.isEmpty && toolCalls.isNotEmpty ? null : content;

    if (toolCalls.isNotEmpty) {
      m['tool_calls'] = toolCalls.map((c) => c.toApiJson()).toList();
    }
    if (role == 'tool') {
      m['tool_call_id'] = toolCallId;
      if (name.isNotEmpty) m['name'] = name;
    }
    return m;
  }

  AiMessage copyWith({String? content, List<AiToolCall>? toolCalls}) {
    return AiMessage(
      role: role,
      content: content ?? this.content,
      toolCalls: toolCalls ?? this.toolCalls,
      toolCallId: toolCallId,
      name: name,
    );
  }

  Map<String, dynamic> toJson() => {
        'role': role,
        'content': content,
        if (toolCalls.isNotEmpty) 'toolCalls': toolCalls.map((c) => c.toJson()).toList(),
        if (toolCallId.isNotEmpty) 'toolCallId': toolCallId,
        if (name.isNotEmpty) 'name': name,
      };

  static AiMessage fromJson(Map<String, dynamic> j) {
    final rawCalls = j['toolCalls'];
    final calls = <AiToolCall>[];
    if (rawCalls is List) {
      for (final c in rawCalls) {
        if (c is Map) calls.add(AiToolCall.fromJson(Map<String, dynamic>.from(c)));
      }
    }
    return AiMessage(
      role: j['role'] as String? ?? 'user',
      content: j['content'] as String? ?? '',
      toolCalls: calls,
      toolCallId: j['toolCallId'] as String? ?? '',
      name: j['name'] as String? ?? '',
    );
  }
}

/// 一次工具调用。
class AiToolCall {
  const AiToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });

  final String id;
  final String name;

  /// 原始 JSON 字符串。不解析成 Map，因为模型可能给出非法 JSON，
  /// 保留原文才能把错误原样回灌给模型让它自己修正。
  final String arguments;

  Map<String, dynamic> toApiJson() => {
        'id': id,
        'type': 'function',
        'function': {'name': name, 'arguments': arguments},
      };

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'arguments': arguments};

  static AiToolCall fromJson(Map<String, dynamic> j) => AiToolCall(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        arguments: j['arguments'] as String? ?? '{}',
      );
}

/// 流式拼装器：把一串 chunk 累积成一条完整消息。
///
/// ## 这是整个流式实现里最容易写错的地方
///
/// 模型的 `tool_calls` 在流里是**按字段分片下发**的：
///
/// ```
/// chunk1: {"tool_calls":[{"index":0,"id":"call_a","function":{"name":"read_note"}}]}
/// chunk2: {"tool_calls":[{"index":0,"function":{"arguments":"{\"id\":"}}]}
/// chunk3: {"tool_calls":[{"index":0,"function":{"arguments":"\"abc\"}"}}]}
/// ```
///
/// 必须按 `index` 归并，且**只做字符串拼接**、不能每次重新 jsonDecode。
/// 早先的写法是「每个 chunk 覆盖前一个」，结果参数只剩最后一小段，
/// 表现为「工具收到的参数永远是半截 JSON」。
class StreamAccumulator {
  final StringBuffer _content = StringBuffer();
  final Map<int, _PartialCall> _calls = {};

  /// 推理过程（DeepSeek-R1 / 各类 R1 兼容实现）。
  ///
  /// 协议事实：DeepSeek 把思考内容放在 `delta.reasoning_content`，
  /// 与正文 `delta.content` **并行下发**，两者都是流式增量。
  /// 硅基流动、vLLM、各类中转站的 R1 实现都跟随这个字段 ——
  /// 所以按字段适配，不按模型名硬编码，换端点不用改代码。
  ///
  /// 注意：OpenAI o1/o3 是**不返回**思考内容的（只返回 `reasoning_effort`
  /// 参数，正文里没有），所以那边这个字段会一直是空。
  /// 空的时候 UI 不显示思考区，行为与以前一致。
  final StringBuffer _reasoning = StringBuffer();

  /// 服务端返回的用量（部分实现才有）
  int? promptTokens;
  int? completionTokens;
  String? finishReason;

  String get content => _content.toString();

  /// 思考过程全文。空串表示该模型没有返回思考内容。
  String get reasoning => _reasoning.toString();

  bool get hasReasoning => _reasoning.isNotEmpty;

  /// 清空累加内容。
  ///
  /// 重试时用：上一次的正文/思考/工具参数都是半截的，
  /// 不清掉会和下一次的内容拼在一起，产生「同一段话说两遍」。
  void reset() {
    _content.clear();
    _reasoning.clear();
    _calls.clear();
    promptTokens = null;
    completionTokens = null;
    finishReason = null;
  }

  List<AiToolCall> get toolCalls {
    final idx = _calls.keys.toList()..sort();
    return idx
        .map((i) => _calls[i]!)
        .where((c) => c.name.isNotEmpty)
        .map((c) => AiToolCall(id: c.id, name: c.name, arguments: c.args.toString()))
        .toList();
  }

  bool get hasToolCalls => toolCalls.isNotEmpty;

  void addContent(String s) => _content.write(s);

  /// 处理一个已经解析成 Map 的 chunk（`choices[0]` 及其外层 `usage`）
  void addChunk(Map<String, dynamic> json) {
    // usage 可能出现在任意一个 chunk 上，也可能最后单独一个 chunk
    final usage = json['usage'];
    if (usage is Map) {
      promptTokens = (usage['prompt_tokens'] as num?)?.toInt() ?? promptTokens;
      completionTokens =
          (usage['completion_tokens'] as num?)?.toInt() ?? completionTokens;
    }

    final choices = json['choices'];
    if (choices is! List || choices.isEmpty) return;

    final first = choices.first;
    if (first is! Map) return;

    finishReason = (first['finish_reason'] as String?) ?? finishReason;

    final delta = first['delta'] ?? first['message'];
    if (delta is! Map) return;

    final c = delta['content'];
    if (c is String) _content.write(c);

    // 思考过程。与 content 并行下发，同样按增量拼接。
    //
    // 三种写法都要认，因为不同实现的字段位置有差异：
    //   1. delta.reasoning_content  —— DeepSeek 官方 / 硅基流动 / vLLM
    //   2. delta.reasoning          —— 部分中转站和 OpenRouter
    //   3. delta.thinking           —— Anthropic 风格的兼容层
    // 全部拿不到就当作「该模型不返回思考内容」，静默跳过。
    final r = delta['reasoning_content'] ??
        delta['reasoning'] ??
        delta['thinking'];
    if (r is String && r.isNotEmpty) _reasoning.write(r);

    final calls = delta['tool_calls'];
    if (calls is! List) return;

    for (final raw in calls) {
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw);

      // index 缺省时按 0 处理 —— 单工具调用的实现常省略它
      final idx = (m['index'] as num?)?.toInt() ?? 0;
      final partial = _calls.putIfAbsent(idx, () => _PartialCall());

      final id = m['id'];
      if (id is String && id.isNotEmpty) partial.id = id;

      final fn = m['function'];
      if (fn is Map) {
        final fnMap = Map<String, dynamic>.from(fn);
        final name = fnMap['name'];
        if (name is String && name.isNotEmpty) {
          // 有的实现把 name 也分片下发，但绝大多数是一次给全。
          // 若给了新的 name 就覆盖（分片拼接 name 属于异常情况）。
          partial.name = name;
        }
        final args = fnMap['arguments'];
        if (args is String) partial.args.write(args);
      }
    }
  }
}

class _PartialCall {
  String id = '';
  String name = '';
  final StringBuffer args = StringBuffer();
}

/// 估算 token 数。
///
/// ## 为什么不追求精确
///
/// 精确计算需要服务商的分词器（tiktoken 一类），Dart 没有官方实现，
/// 自己移植 BPE 表体积大且容易和服务商版本对不上。
///
/// 这里用业界常用的粗略换算：
/// - 英文约 4 字符 / token
/// - 中文约 1 字 / token
///
/// **调用方必须把结果标注为「估算」**，不能当精确值展示。
int estimateTokens(String text) {
  if (text.isEmpty) return 0;
  var cjk = 0;
  var other = 0;
  for (final r in text.runes) {
    // CJK 统一表意文字 + 中日韩标点
    if ((r >= 0x4E00 && r <= 0x9FFF) ||
        (r >= 0x3040 && r <= 0x30FF) ||
        (r >= 0xAC00 && r <= 0xD7AF) ||
        (r >= 0x3000 && r <= 0x303F) ||
        (r >= 0xFF00 && r <= 0xFFEF)) {
      cjk++;
    } else {
      other++;
    }
  }
  return cjk + (other / 4).ceil();
}

/// 估算一组消息（含工具调用参数）的 token
int estimateMessagesTokens(List<AiMessage> messages) {
  var total = 0;
  for (final m in messages) {
    // 每条消息有固定开销（role、分隔符等），业界惯例约 4
    total += 4;
    total += estimateTokens(m.content);
    for (final c in m.toolCalls) {
      total += estimateTokens(c.name) + estimateTokens(c.arguments);
    }
  }
  return total;
}

/// 把 JSON 字符串安全地格式化成可读的 Map。
/// 失败时返回 null，让调用方走「参数解析失败」分支而不是崩掉。
Map<String, dynamic>? tryDecodeArgs(String s) {
  try {
    final j = jsonDecode(s);
    if (j is Map) return Map<String, dynamic>.from(j);
    return null;
  } catch (_) {
    return null;
  }
}