import 'dart:async';

import 'ai_client.dart';
import 'ai_endpoint.dart';
import 'cancel_token.dart';
import 'ai_message.dart';
import 'chat_store.dart';
import 'tools/ai_tool.dart';

/// 用户对一次写盘请求的决定
enum ApprovalDecision {
  /// 同意，写盘
  approve,

  /// 拒绝，告诉模型别写了
  reject,

  /// 拒绝并中止整个循环
  abort,
}

/// 审批请求：交给 UI 弹出 Diff
class ApprovalRequest {
  const ApprovalRequest({
    required this.toolName,
    required this.path,
    required this.newContent,
    required this.oldContent,
  });

  final String toolName;
  final String path;

  /// 将写入的新内容
  final String newContent;

  /// 现有内容；null 表示新建
  final String? oldContent;

  bool get isNew => oldContent == null;
}

/// Agent 循环的回调集合。
///
/// 用回调而不是让循环直接操作 UI，是为了能单测：
/// 测试里给一个「总是 approve」的回调就能跑完整流程。
class AgentCallbacks {
  const AgentCallbacks({
    required this.onTextDelta,
    required this.onToolStart,
    required this.onToolDone,
    required this.requestApproval,
    this.onReasoningDelta,
    this.onReasoningDone,
  });

  /// 流式文本增量
  final void Function(String delta) onTextDelta;

  /// 思考过程增量。模型不返回思考内容时不会触发。
  final void Function(String delta)? onReasoningDelta;

  /// 一个回合的思考结束时回调（正文开始前），供 UI 收起思考区
  final void Function()? onReasoningDone;

  /// 工具开始执行
  final void Function(String toolName, Map<String, dynamic> args) onToolStart;

  /// 工具执行完成
  final void Function(ToolCallRecord record) onToolDone;

  /// 需要用户批准（只有 requiresApproval 的工具会触发）
  final Future<ApprovalDecision> Function(ApprovalRequest req) requestApproval;
}

/// 一轮对话的结果
class AgentTurnResult {
  const AgentTurnResult({
    required this.text,
    required this.toolCalls,
    required this.promptTokens,
    required this.completionTokens,
    required this.usageIsExact,
    required this.backups,
    this.aborted = false,
    this.reasoning = '',
  });

  final String text;

  /// 模型的思考过程（DeepSeek-R1 等）。空串表示该模型不返回。
  final String reasoning;
  final List<ToolCallRecord> toolCalls;

  /// 所有轮次累加
  final int promptTokens;
  final int completionTokens;

  /// true 表示 token 来自服务端 usage，false 表示是估算
  final bool usageIsExact;

  /// 本次轮次产生的写盘备份（供回滚）
  final List<WriteBackup> backups;

  final bool aborted;
}

/// AI Agent 循环。
///
/// ```
/// 用户消息 (+ system prompt 含想法上下文)
///   → 调 LLM（stream）
///   → 有 tool_calls：
///        ├─ 只读工具 → 直接执行 → 回灌 → 继续
///        └─ write_post → 暂停等审批 → 批准才执行 → 回灌 → 继续
///   → 无 tool_call → 结束
/// ```
class AgentRunner {
  AgentRunner({
    required this.client,
    required this.tools,
    required this.readPost,
    this.maxToolRounds = 8,
    this.maxTokensPerRound = 120000,
  });

  final AiClient client;
  final List<AiTool> tools;

  /// 读取站点里一篇文章的当前内容，读不到返回 null。
  ///
  /// 两个用途，必须是同一份「读」的实现：
  /// 1. 审批时给用户看 Diff 的旧内容
  /// 2. 写盘前做回滚备份
  ///
  /// 如果这两处各读一次、甚至各用一套路径拼接，会出现
  /// 「Diff 显示的是 A 文件，实际改的是 B 文件」这种极难查的问题。
  final Future<String?> Function(String relPath) readPost;

  /// 单轮最多几轮工具调用。防止模型陷入「调工具 → 结果不满意 →
  /// 再调同一个工具」的死循环把额度烧光。
  final int maxToolRounds;

  /// 单轮 token 上限（估算 + 实际取大者）
  final int maxTokensPerRound;

  /// 执行一次完整对话轮次。
  ///
  /// [baseMessages] 是历史（不含本次用户消息）；
  /// [userText] 是本次输入。
  Future<AgentTurnResult> run({
    required AiEndpoint endpoint,
    required String apiKey,
    required List<AiMessage> baseMessages,
    required String userText,
    required AgentCallbacks callbacks,
    String systemPrompt = '',
    List<Map<String, dynamic>> extraTools = const [],
    CancelToken? cancelToken,
  }) async {
    final messages = <AiMessage>[];
    if (systemPrompt.trim().isNotEmpty) {
      messages.add(AiMessage(role: 'system', content: systemPrompt));
    }
    messages.addAll(baseMessages);
    messages.add(AiMessage(role: 'user', content: userText));

    final toolSchemas = [
      ...tools.map((t) => t.toApiJson()),
      ...extraTools,
    ];

    final collected = <ToolCallRecord>[];
    final backups = <WriteBackup>[];
    final textBuf = StringBuffer();
    final reasoningBuf = StringBuffer();

    var totalPrompt = 0;
    var totalCompletion = 0;
    var exact = false;
    var rounds = 0;

    while (true) {
      cancelToken?.throwIfCancelled();

      if (rounds > 0) {
        // 累计 token 保护
        final sofar = totalPrompt + totalCompletion;
        if (sofar > maxTokensPerRound) {
          throw AiException(
            AiErrorKind.rateLimited,
            '本轮 token 已用 $sofar，超过上限 $maxTokensPerRound',
            hint: '换个更短的问题，或清理对话历史',
          );
        }
      }

      rounds++;
      if (rounds > maxToolRounds + 1) {
        // +1 是留给最后一次「无工具调用的收尾回答」
        throw AiException(
          AiErrorKind.badRequest,
          '工具调用超过 $maxToolRounds 轮，已中止',
          hint: '问题可能太复杂，拆成几步问',
        );
      }

      final acc = StreamAccumulator();
      await client.streamChat(
        endpoint: endpoint,
        apiKey: apiKey,
        messages: messages,
        accumulator: acc,
        tools: toolSchemas,
        onDelta: callbacks.onTextDelta,
        onReasoningDelta: callbacks.onReasoningDelta,
        cancelToken: cancelToken,
      );

      // 本回合的思考内容。多轮工具循环里每轮都可能带思考，
      // 这里累积起来，最终供 ChatEntry 保存与 UI 折叠展示。
      if (acc.hasReasoning) {
        reasoningBuf.write(acc.reasoning);
        callbacks.onReasoningDone?.call();
      }

      // usage：服务端给了就是精确值
      if (acc.promptTokens != null || acc.completionTokens != null) {
        exact = true;
        totalPrompt += acc.promptTokens ?? 0;
        totalCompletion += acc.completionTokens ?? 0;
      } else {
        totalPrompt += estimateMessagesTokens(messages);
        totalCompletion += estimateTokens(acc.content);
      }

      textBuf.write(acc.content);

      if (!acc.hasToolCalls) {
        // 没有工具调用 → 本轮结束
        break;
      }

      final calls = acc.toolCalls;

      // assistant 的 tool_calls 必须先入历史，否则后面的 tool 消息
      // 找不到对应的 tool_call_id，服务端会直接 400
      messages.add(AiMessage(
        role: 'assistant',
        content: acc.content,
        toolCalls: calls,
      ));

      for (final call in calls) {
        // 每个工具执行前都检查取消。
        //
        // 为什么必须在这里查：`streamChat` 只在收分片时检查取消，
        // 而工具执行阶段没有任何网络活动。用户点了停止之后，
        // 模型排队的 6 个工具**仍会依次跑完** —— 其中包括 write_post
        // 写盘。现象是「点了停止，界面不动了，但文件还是被改了」，
        // 比单纯的停不下来更糟。
        cancelToken?.throwIfCancelled();

        final tool = _findTool(call.name);
        final args = tryDecodeArgs(call.arguments) ?? const {};

        if (tool == null) {
          final rec = ToolCallRecord(
            id: call.id,
            name: call.name,
            arguments: call.arguments,
            ok: false,
            summary: '未知工具 ${call.name}',
            detail: '模型调用了一个不存在的工具',
          );
          collected.add(rec);
          callbacks.onToolDone(rec);
          messages.add(AiMessage(
            role: 'tool',
            toolCallId: call.id,
            name: call.name,
            content: '错误：没有名为 ${call.name} 的工具',
          ));
          continue;
        }

        callbacks.onToolStart(call.name, args);

        // 参数 JSON 坏了：把解析错误回灌，让模型自己修
        if (tryDecodeArgs(call.arguments) == null) {
          final rec = ToolCallRecord(
            id: call.id,
            name: call.name,
            arguments: call.arguments,
            ok: false,
            summary: '参数不是合法 JSON',
            detail: call.arguments,
          );
          collected.add(rec);
          callbacks.onToolDone(rec);
          messages.add(AiMessage(
            role: 'tool',
            toolCallId: call.id,
            name: call.name,
            content: '错误：arguments 不是合法 JSON，请重新生成。'
                '原文：${call.arguments}',
          ));
          continue;
        }

        // 需要审批的工具：暂停
        if (tool.requiresApproval) {
          final path = args['path'] as String? ?? '';
          final newContent = args['content'] as String? ?? '';

          // 先读旧内容：既能给 Diff，也能做回滚备份。
          // 只读一次，避免两处不一致。
          final oldContent = await _readExisting(path);

          final decision = await callbacks.requestApproval(
            ApprovalRequest(
              toolName: call.name,
              path: path,
              newContent: newContent,
              oldContent: oldContent,
            ),
          );

          if (decision == ApprovalDecision.abort) {
            return AgentTurnResult(
              text: textBuf.toString(),
              toolCalls: collected,
              promptTokens: totalPrompt,
              completionTokens: totalCompletion,
              usageIsExact: exact,
              backups: backups,
              aborted: true,
              reasoning: reasoningBuf.toString(),
            );
          }

          if (decision == ApprovalDecision.reject) {
            final rec = ToolCallRecord(
              id: call.id,
              name: call.name,
              arguments: call.arguments,
              ok: false,
              summary: '用户拒绝了写入 $path',
              detail: '用户没有批准这次写入',
              approved: false,
            );
            collected.add(rec);
            callbacks.onToolDone(rec);
            messages.add(AiMessage(
              role: 'tool',
              toolCallId: call.id,
              name: call.name,
              content: '用户拒绝了这次写入。不要重复尝试，'
                  '如果要调整，先询问用户想要什么改动。',
            ));
            continue;
          }

          // 批准：先记录备份，再写盘。
          //
          // 顺序不能反：写完再备份，备份里的「原内容」就已经是新内容，
          // 回滚等于什么都没做。
          backups.add(WriteBackup(
            relPath: path,
            previous: oldContent,
            at: DateTime.now(),
          ));

          final result = await tool.execute(args);
          final rec = ToolCallRecord(
            id: call.id,
            name: call.name,
            arguments: call.arguments,
            ok: result.ok,
            summary: result.detail.isEmpty ? call.name : result.detail,
            detail: result.text,
            approved: true,
          );
          collected.add(rec);
          callbacks.onToolDone(rec);

          messages.add(AiMessage(
            role: 'tool',
            toolCallId: call.id,
            name: call.name,
            content: result.text,
          ));
          continue;
        }

        // 只读工具：执行前再看一眼取消状态。
        // fetch_url 最长 15 秒，用户在这期间点停止是合理操作。
        cancelToken?.throwIfCancelled();

        ToolResult result;
        try {
          result = await tool.execute(args).timeout(
                const Duration(seconds: 15),
              );
        } on TimeoutException {
          result = ToolResult.fail('工具执行超时（15 秒）');
        } catch (e) {
          result = ToolResult.fail('工具执行出错：$e');
        }

        final rec = ToolCallRecord(
          id: call.id,
          name: call.name,
          arguments: call.arguments,
          ok: result.ok,
          summary: result.detail.isEmpty ? call.name : result.detail,
          detail: result.text,
        );
        collected.add(rec);
        callbacks.onToolDone(rec);

        messages.add(AiMessage(
          role: 'tool',
          toolCallId: call.id,
          name: call.name,
          content: result.text,
        ));
      }
    }

    return AgentTurnResult(
      text: textBuf.toString(),
      toolCalls: collected,
      promptTokens: totalPrompt,
      completionTokens: totalCompletion,
      usageIsExact: exact,
      backups: backups,
      reasoning: reasoningBuf.toString(),
    );
  }

  AiTool? _findTool(String name) {
    for (final t in tools) {
      if (t.name == name) return t;
    }
    return null;
  }

  /// 读一篇文章的现有内容。
  ///
  /// 失败一律按「不存在」处理（返回 null），理由：
  /// - 审批时读不到旧内容，Diff 会退化成「全文新增」，用户仍能看清要点
  /// - 备份时读不到，回滚会把文件删掉而不是恢复 —— 这个代价可接受，
  ///   因为「读不到」几乎只发生在文件本来就不存在时
  ///
  /// 绝不能因为这里抛异常就把整个对话搞崩。
  Future<String?> _readExisting(String relPath) async {
    if (relPath.trim().isEmpty) return null;
    try {
      return await readPost(relPath);
    } catch (_) {
      return null;
    }
  }
}
