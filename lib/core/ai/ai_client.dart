import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_endpoint.dart';
import 'cancel_token.dart';
import 'ai_message.dart';
import 'sse_parser.dart';

/// AI 调用过程中出现的可分类错误。
///
/// 分类而不是只给一段字符串，是因为调用方需要区别对待：
/// key 错了要引导去设置，被限流要提示稍后，网络错可以重试。
enum AiErrorKind {
  /// 没配置端点 / 没选模型
  notConfigured,

  /// 401/403：key 不对或没有权限
  badKey,

  /// 429：限流或额度用尽
  rateLimited,

  /// 4xx：请求本身有问题（模型名不对、参数不支持）
  badRequest,

  /// 5xx：服务端故障
  serverError,

  /// 网络层：超时、连不上、TLS
  network,

  /// 流解析失败
  badStream,
}

class AiException implements Exception {
  AiException(this.kind, this.message, {this.hint});

  final AiErrorKind kind;
  final String message;
  final String? hint;

  /// 是否值得原样提示用户重试
  bool get retryable =>
      kind == AiErrorKind.network ||
      kind == AiErrorKind.serverError ||
      kind == AiErrorKind.rateLimited;

  @override
  String toString() => hint == null ? message : '$message（$hint）';
}

/// 模型列表项
class AiModel {
  const AiModel({required this.id});

  final String id;

  /// 粗略判断能否用于对话。
  ///
  /// `/models` 会把 embedding、whisper、tts、dall-e 也列出来，
  /// 全部塞进下拉框会让用户挑到一个根本不能聊天的模型，
  /// 然后在发送时收到 400。这里提前兜一层。
  bool get looksChatCapable {
    final s = id.toLowerCase();
    const denied = [
      'embedding',
      'whisper',
      'tts',
      'dall-e',
      'moderation',
      'rerank',
      'bge-',
      'text-similarity',
    ];
    for (final d in denied) {
      if (s.contains(d)) return false;
    }
    return true;
  }
}

/// OpenAI 兼容端点客户端。
///
/// 只依赖 `package:http`，不引入任何 LLM SDK ——
/// 各家 SDK 都只支持官方服务，反而挡不住「接入多个端点」这个需求。
class AiClient {
  AiClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  void dispose() => _client.close();

  Map<String, String> _headers(String apiKey) => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $apiKey',
    // 部分中转站要求这个头，不要求时无害
    'Accept': 'text/event-stream',
  };

  /// 拉取模型列表。
  ///
  /// 走 `GET /models`，几乎所有 OpenAI 兼容实现都有。
  /// 少数中转站不支持，此时抛 [AiErrorKind.badRequest]，
  /// 调用方应当退化成「手动填写模型名」而不是卡住。
  Future<List<AiModel>> listModels({
    required AiEndpoint endpoint,
    required String apiKey,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    if (endpoint.baseUrl.trim().isEmpty) {
      throw AiException(AiErrorKind.notConfigured, '还没有填写端点地址');
    }

    late http.Response res;
    try {
      res = await _client
          .get(endpoint.uri('models'), headers: _headers(apiKey))
          .timeout(timeout);
    } on TimeoutException {
      throw AiException(
        AiErrorKind.network,
        '获取模型列表超时',
        hint: '检查网络，或直接手动填写模型名',
      );
    } catch (e) {
      throw AiException(AiErrorKind.network, '获取模型列表失败：$e');
    }

    if (res.statusCode == 401 || res.statusCode == 403) {
      throw AiException(
        AiErrorKind.badKey,
        'API Key 无效或没有权限',
        hint: '检查 key 是否正确、是否已过期',
      );
    }
    if (res.statusCode >= 500) {
      throw AiException(AiErrorKind.serverError, '服务端错误 ${res.statusCode}');
    }
    if (res.statusCode != 200) {
      throw AiException(
        AiErrorKind.badRequest,
        '获取模型列表失败（${res.statusCode}）',
        hint: '这个端点可能不支持 /models，可以手动填写模型名',
      );
    }

    try {
      final j = jsonDecode(utf8.decode(res.bodyBytes));
      if (j is! Map) throw const FormatException('不是 JSON 对象');
      final data = j['data'];
      if (data is! List) throw const FormatException('缺少 data 字段');
      final models = <AiModel>[];
      for (final m in data) {
        if (m is Map) {
          final id = m['id'];
          if (id is String && id.isNotEmpty) models.add(AiModel(id: id));
        }
      }
      models.sort((a, b) => a.id.compareTo(b.id));
      return models;
    } on FormatException catch (e) {
      throw AiException(
        AiErrorKind.badRequest,
        '模型列表格式不对：${e.message}',
        hint: '这个端点可能不是 OpenAI 兼容接口',
      );
    }
  }

  /// 发起一次流式对话。
  ///
  /// 返回的 Stream 会先吐出文本增量（String），
  /// 结束时由调用方从 [StreamAccumulator] 取完整结果。
  ///
  /// [onDelta] 用于实时更新 UI；[accumulator] 由调用方传入以便
  /// 在流结束后读取 tool_calls 与 usage。
  /// 带自动重试的流式对话。
  ///
  /// ## 什么错该重试
  ///
  /// 只看 [AiException.retryable]：网络抖动、5xx、429 才退避重试。
  /// **401 / 400 绝不重试** —— key 错了重试三次只是让用户白等，
  /// 而且会让「明明配错了」看起来像「网络不好」。
  ///
  /// ## 为什么要退避而不是立刻重试
  ///
  /// 429 是「你太快了」。立刻重试等于继续踩油门，
  /// 有些服务会因此把冷却时间拉得更长。
  /// 1s → 2s 的简单指数退避足够，不做 8s 那种长等待
  /// （用户盯着屏幕等，超过 3 秒就会以为卡死）。
  ///
  /// ## 为什么不重试「中途断流」
  ///
  /// 已经吐出半篇内容后再从头发一次，会导致同一段文本出现两遍
  /// 且 token 双倍计费。这种情况交给用户决定（重新生成）。
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
    var attempt = 0;
    while (true) {
      try {
        await _streamChatOnce(
          endpoint: endpoint,
          apiKey: apiKey,
          messages: messages,
          accumulator: accumulator,
          tools: tools,
          onDelta: onDelta,
          onReasoningDelta: onReasoningDelta,
          timeout: timeout,
          cancelToken: cancelToken,
          thinkingLevel: thinkingLevel,
        );
        return;
      } on AiException catch (e) {
        // 取消不是失败，不重试
        if (cancelToken?.isCancelled ?? false) rethrow;
        if (!e.retryable || attempt >= maxRetries) rethrow;

        attempt++;
        final wait = Duration(seconds: 1 << (attempt - 1)); // 1s, 2s
        onRetry?.call(attempt, maxRetries, wait);
        // 等待期间也要能被取消，否则用户点了停止还要等 2 秒
        await Future<void>.delayed(wait);
        cancelToken?.throwIfCancelled();
        // 重试前清空累加器：半截内容不能和新的一次混在一起
        accumulator.reset();
      }
    }
  }

  Future<void> _streamChatOnce({
    required AiEndpoint endpoint,
    required String apiKey,
    required List<AiMessage> messages,
    required StreamAccumulator accumulator,
    List<Map<String, dynamic>> tools = const [],
    void Function(String delta)? onDelta,
    void Function(String delta)? onReasoningDelta,
    Duration timeout = const Duration(seconds: 60),
    CancelToken? cancelToken,
    ThinkingLevel thinkingLevel = ThinkingLevel.none,
  }) async {
    // 短名字：下面拼 body 时用得多
    final level = thinkingLevel;

    if (endpoint.baseUrl.trim().isEmpty) {
      throw AiException(AiErrorKind.notConfigured, '还没有配置 AI 端点');
    }
    if (endpoint.model.trim().isEmpty) {
      throw AiException(AiErrorKind.notConfigured, '还没有选择模型');
    }

    // 发请求前先看一眼：用户可能在按下发送的瞬间就点了停止
    cancelToken?.throwIfCancelled();

    final body = <String, dynamic>{
      'model': endpoint.model,
      'messages': messages.map((m) => m.toApiJson()).toList(),
      'stream': true,
      // 让服务端在流末尾带上 usage；不支持的实现会忽略这个字段
      'stream_options': {'include_usage': true},
    };
    if (tools.isNotEmpty) {
      body['tools'] = tools;
      body['tool_choice'] = 'auto';
    }

    // 思考模式必须**翻译成这个端点认得的请求**。
    //
    // 这是「UI 上开了开关但模型没思考」的根因所在：
    // 混合模型（Qwen3 等）默认走非思考路径，不发参数就不思考，
    // 光靠解析 reasoning_content 是等不到内容的。
    //
    // 用 effectiveProtocol 而不是 thinkingProtocol：后者可能是 off（用户没配），
    // 前者会按模型名推断一个合理值。用户不应该为
    // 「该发 enable_thinking 还是 reasoning_effort」负责。
    switch (endpoint.effectiveProtocol) {
      case ThinkingProtocol.off:
        // 什么都不发。普通模型收到未知字段可能直接 400。
        break;
      case ThinkingProtocol.alwaysOn:
        // 模型本身总是思考，不需要请求参数。
        break;
      case ThinkingProtocol.enableThinking:
        // 布尔开关：没有档位概念。
        // 选了除 none 以外的任何档位都译成 true ——
        // 这是该协议的表达能力上限，不是偷懒。
        body['enable_thinking'] = level.isThinking;
        break;
      case ThinkingProtocol.reasoningEffort:
        // 档位制。level=none 时也不发（发了等于强制思考）。
        if (level.isThinking) {
          body['reasoning_effort'] = level.effortValue;
        }
        break;
    }

    // 发送循环：允许一次「参数被拒就去掉重发」。
    //
    // 为什么需要这个：我们按模型名推断协议，推不准是常态（中转站改了名、
    // 自建服务封了字段）。若不降级，用户会看到一个 400，
    // 而真正的原因是「App 多发了一个你不认的字段」——
    // 这不是用户的错，不该让他去排查。
    //
    // 只试一次：两次都不行说明问题不在参数，继续重试只会拖延。
    http.StreamedResponse? res;
    for (var pass = 0; pass < 2; pass++) {
      final req = http.Request('POST', endpoint.uri('chat/completions'))
        ..headers.addAll(_headers(apiKey))
        ..bodyBytes = utf8.encode(jsonEncode(body));

      final http.StreamedResponse r;
      try {
        r = await _client.send(req).timeout(timeout);
      } on TimeoutException {
        throw AiException(AiErrorKind.network, '连接 AI 端点超时', hint: '检查网络或端点地址');
      } catch (e) {
        throw AiException(AiErrorKind.network, '请求失败：$e');
      }

      if (r.statusCode == 200) {
        res = r;
        break;
      }

      // 错误响应往往是普通 JSON，不是 SSE。
      // 这里必须先判断状态码，否则会拿错误 JSON 去喂 SSE 解析器，
      // 最终报成「流解析失败」，把真正的原因（key 错了）盖掉。
      final text = await _readAll(r);

      if (pass == 0 && _isUnsupportedParam(r.statusCode, text)) {
        // 把思考参数全部摸掉，退回「什么都不发」
        final a = body.remove('enable_thinking');
        final b = body.remove('reasoning_effort');
        if (a != null || b != null) continue;
      }

      throw _mapHttpError(r.statusCode, text);
    }

    final response = res!;

    final parser = SseParser();
    var sawDone = false;

    try {
      await for (final chunk
          in response.stream.transform(utf8.decoder).timeout(timeout)) {
        // 每个网络分片都检查一次取消。
        // 放在这里而不是只在开头检查一次：模型输出可能持续几十秒，
        // 只在开头查等于「点了停止还在收完整篇」。
        if (cancelToken?.isCancelled ?? false) {
          // 主动排空并关闭，让服务端尽快停止生成
          unawaited(response.stream.drain<void>().catchError((_) {}));
          throw const CancelledException();
        }

        for (final payload in parser.push(chunk)) {
          if (payload == '[DONE]') {
            sawDone = true;
            continue;
          }
          Map<String, dynamic> json;
          try {
            final decoded = jsonDecode(payload);
            if (decoded is! Map) continue;
            json = Map<String, dynamic>.from(decoded);
          } catch (_) {
            // 单个 chunk 坏了跳过即可，不要整条流都失败
            continue;
          }

          // 有些实现在 SSE 里塞 error 对象
          final err = json['error'];
          if (err is Map) {
            final msg = err['message'] as String? ?? '服务端返回错误';
            throw AiException(AiErrorKind.serverError, msg);
          }

          final beforeContent = accumulator.content;
          final beforeReasoning = accumulator.reasoning;
          accumulator.addChunk(json);
          final afterContent = accumulator.content;
          final afterReasoning = accumulator.reasoning;

          if (afterContent.length > beforeContent.length && onDelta != null) {
            onDelta(afterContent.substring(beforeContent.length));
          }
          // 思考内容的增量单独推。
          //
          // 为什么要单独一路：正文和思考是两条并行流，
          // 用同一个回调会把「正在思考」和「正在作答」揉在一起，
          // UI 就没法分区渲染了。思考通常先来、且量大，
          // 混在一起会让正文区先刷出一大段灰字再被清掉。
          if (afterReasoning.length > beforeReasoning.length &&
              onReasoningDelta != null) {
            onReasoningDelta(afterReasoning.substring(beforeReasoning.length));
          }
        }
      }

      // 流结束，处理残留
      for (final payload in parser.flush()) {
        if (payload == '[DONE]') {
          sawDone = true;
          continue;
        }
        try {
          final decoded = jsonDecode(payload);
          if (decoded is Map) {
            accumulator.addChunk(Map<String, dynamic>.from(decoded));
          }
        } catch (_) {
          // 忽略
        }
      }
    } on CancelledException {
      // 取消不是错误，原样往上抛，别包成「读取响应失败」
      rethrow;
    } on AiException {
      rethrow;
    } on TimeoutException {
      throw AiException(AiErrorKind.network, '流式响应超时中断');
    } catch (e) {
      // 取消时底层可能抛 ClientException，这里再兜一次
      if (cancelToken?.isCancelled ?? false) {
        throw const CancelledException();
      }
      throw AiException(AiErrorKind.badStream, '读取响应失败：$e');
    }

    // 没收到 [DONE] 但也没报错：后端可能是非标准实现。
    // 只要拿到了内容就当成功，不要因为「缺结束标记」丢弃结果。
    if (!sawDone && accumulator.content.isEmpty && !accumulator.hasToolCalls) {
      throw AiException(
        AiErrorKind.badStream,
        '响应为空',
        hint: '模型可能不支持流式，或端点返回了非标准格式',
      );
    }
  }

  Future<String> _readAll(http.StreamedResponse res) async {
    try {
      return await res.stream
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      return '';
    }
  }

  /// 这个 400 是不是因为「你多发了一个我不认的字段」。
  ///
  /// 为什么触发条件收得这么窄：只有 400/422 而且错误文本提到了参数名，
  /// 才能断定是字段问题。广泛匹配「content」「model」之类的字眼会把
  /// 真正的错误（模型不存在、消息格式错）也当成参数问题去掉重发，
  /// 结果是「去掉了一个没问题的字段、真错误依然在」。
  ///
  /// 另外也要认这种没有状态码但仍是 400 的写法。
  bool _isUnsupportedParam(int status, String body) {
    if (status != 400 && status != 422) return false;
    final t = body.toLowerCase();
    final mentionsField =
        t.contains('enable_thinking') || t.contains('reasoning_effort');
    if (!mentionsField) return false;
    // “unexpected” “unsupported” “invalid” “unknown” “extra” “not permitted”
    return t.contains('unexpected') ||
        t.contains('unsupported') ||
        t.contains('invalid') ||
        t.contains('unknown') ||
        t.contains('extra') ||
        t.contains('not permitted') ||
        t.contains('not allowed') ||
        // 中文实现
        t.contains('不支持') ||
        t.contains('未知');
  }

  AiException _mapHttpError(int status, String body) {
    // 尽量从错误体里抠出可读信息，各实现格式不一
    String detail = body;
    try {
      final j = jsonDecode(body);
      if (j is Map) {
        final err = j['error'];
        if (err is Map && err['message'] is String) {
          detail = err['message'] as String;
        } else if (j['message'] is String) {
          detail = j['message'] as String;
        }
      }
    } catch (_) {
      // 保留原文
    }
    if (detail.length > 300) detail = '${detail.substring(0, 300)}…';

    switch (status) {
      case 401:
      case 403:
        return AiException(
          AiErrorKind.badKey,
          'API Key 无效：$detail',
          hint: '到设置里检查这个端点的 key',
        );
      case 404:
        return AiException(
          AiErrorKind.badRequest,
          '接口不存在（404）',
          hint: '端点地址可能少了或多了 /v1',
        );
      case 429:
        return AiException(
          AiErrorKind.rateLimited,
          '请求过于频繁或额度用尽',
          hint: '稍后再试，或换一个端点',
        );
      default:
        if (status >= 500) {
          return AiException(AiErrorKind.serverError, '服务端错误 $status：$detail');
        }
        return AiException(AiErrorKind.badRequest, '请求失败（$status）：$detail');
    }
  }
}
