import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../core/ai/agent_runner.dart';
import '../../core/ai/ai_controller.dart';
import '../../core/ai/ai_endpoint.dart';
import '../../core/ai/chat_store.dart';
import 'ai_endpoints_page.dart';
import 'model_switcher_sheet.dart';
import 'write_approval_sheet.dart';
import 'chat_markdown.dart';
import 'thinking_block.dart';

/// AI 对话页。
///
/// 之前这一页是硬编码的假消息（「我已经读过你置顶的两条笔记」），
/// 现在接的是真实的 Agent 循环：流式输出、6 个工具、Diff 审批、撤销。
class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.controller});

  final AiController controller;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    setState(() {});
    // 流式输出时要跟着滚到底
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    final entries = ctrl.session?.entries ?? const <ChatEntry>[];

    return Scaffold(
      appBar: AppBar(
        // 标题区直接做成「端点 · 模型」的按钮：
        // 换模型是高频操作，不该藏在二级页里。
        title: InkWell(
          onTap: ctrl.busy ? null : _openSwitcher,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        ctrl.session?.title ?? 'AI',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.expand_more,
                      size: 15,
                      color: context.appColors.textTertiary,
                    ),
                  ],
                ),
                // 第二行常显当前端点与模型，一眼知道自己在跟谁说话
                Text(
                  _modelLabel(ctrl),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: context.appColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: '端点管理',
            onPressed: _openEndpoints,
            icon: const Icon(Icons.smart_toy_outlined),
          ),
          IconButton(
            tooltip: '历史对话',
            onPressed: _openHistory,
            icon: const Icon(Icons.history),
          ),
          IconButton(
            tooltip: '新对话',
            onPressed: ctrl.busy ? null : _newChat,
            icon: const Icon(Icons.add_comment_outlined),
          ),
          const SizedBox(width: AppSpace.xs),
        ],
      ),
      body: ctrl.config.endpoints.isEmpty
          ? _NeedEndpoint(onAdd: _openEndpoints)
          : Column(
              children: [
                Expanded(
                  child: entries.isEmpty && ctrl.streamingText == null
                      ? _EmptyChat(
                          model: ctrl.activeEndpoint?.model ?? '',
                          endpoint: ctrl.activeEndpoint?.name ?? '',
                        )
                      : ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpace.md,
                            vertical: AppSpace.sm,
                          ),
                          itemCount:
                              entries.length +
                              (ctrl.streamingText != null ? 1 : 0),
                          itemBuilder: (_, i) {
                            if (i < entries.length) {
                              return _EntryView(
                                entry: entries[i],
                                busy: ctrl.busy,
                                onRollback: () => _rollback(entries[i]),
                                onRecall: () => _recall(entries[i]),
                                onResend: () => _resend(entries[i]),
                                onRegenerate: () => _regenerate(entries[i]),
                                onEdit: () => _editEntry(entries[i]),
                                onDelete: () => _deleteEntry(entries[i]),
                              );
                            }
                            return _StreamingBubble(
                              text: ctrl.streamingText ?? '',
                              runningTool: ctrl.runningTool,
                              reasoning: ctrl.streamingReasoning,
                            );
                          },
                        ),
                ),
                // 错误必须可见。
                //
                // 之前 AiController.lastError 只被赋值、从没被渲染，
                // 所以「模型没选」「key 错了」「网络失败」这些情况
                // 在界面上完全看不出来，用户只看到「发了没反应」。
                if (ctrl.lastError != null && !ctrl.busy)
                  _ErrorBar(
                    message: ctrl.lastError!,
                    onDismiss: ctrl.clearError,
                  ),
                _ContextBar(controller: ctrl, onTap: _openScope),
                // 底部再来一个常驻的模型切换入口。
                //
                // 顶栏虽然也能点，但它在屏幕最上方，单手够不到；
                // 输入框旁边才是拇指区，换模型后紧接着打字是最自然的流程。
                _ModelBar(
                  label: _modelLabel(ctrl),
                  busy: ctrl.busy,
                  onTap: _openSwitcher,
                  entryCount: ctrl.currentEntryCount,
                  threshold: ctrl.settings?.aiCompressThreshold ?? 20,
                  compressed: ctrl.lastCompressed,
                  onContextTap: _showContextDetail,
                  thinkingLevel: ctrl.thinkingLevel,
                  thinkingHint: ctrl.thinkingHint,
                  onThinkingTap: _pickThinkingLevel,
                ),
                _InputBar(
                  controller: _input,
                  busy: ctrl.busy,
                  onSend: _send,
                  onCancel: ctrl.cancel,
                ),
              ],
            ),
    );
  }

  /// 选择思考档位。
  ///
  /// ## 为什么必须限制高度 + 可滚动
  ///
  /// 上一版是 5 个 ListTile（每个约 72 高）直接堆在 Column 里，
  /// 总高超过了 showModalBottomSheet 默认的最大高度（屏幕 9/16），
  /// 于是报 `BOTTOM OVERFLOWED BY 1.2 PIXELS`。
  ///
  /// 现在的做法：
  /// - 外层 `ConstrainedBox(maxHeight: 屏高 * 0.72)` 留出安全边距
  /// - 内容放进 `SingleChildScrollView`
  /// - 档位改成横向胶囊网格，整体高度从 ~400 压到 ~200
  ///
  /// 网格比 ListTile 更好：一屏看全 5 个档位，不用滚，
  /// 也更容易点（每格都是完整按钮，不是一行细文字）。
  void _pickThinkingLevel() {
    final ctrl = widget.controller;
    final hint = ctrl.thinkingHint;
    final screenH = MediaQuery.sizeOf(context).height;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) {
        final c = sheetCtx.appColors;
        return SafeArea(
          // 不给死高度：内容少时自然贴合，内容多时封顶并滚动。
          // 封顶值取 0.72 而不是 0.9，是因为键盘还没算进来 ——
          // 留出余量可以避免任何情况的 1~2px 溢出。
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: screenH * 0.72),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 拖动条：暗示这是可下拉的弹窗
                    Center(
                      child: Container(
                        width: 32,
                        height: 3,
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: c.divider,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Text(
                          '思考档位',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: c.textPrimary,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: c.surface,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            ctrl.thinkingProtocol.label,
                            style: TextStyle(
                              fontSize: 10,
                              color: c.textTertiary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (hint != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: c.warning.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 12,
                              color: c.warning,
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                hint,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: c.warning,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    // 横向等宽胶囊：一行两个，5 个档位占三行
                    for (var i = 0; i < ThinkingLevel.values.length; i += 2)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: _LevelOption(
                                level: ThinkingLevel.values[i],
                                selected:
                                    ctrl.thinkingLevel ==
                                    ThinkingLevel.values[i],
                                onTap: () {
                                  ctrl.setThinkingLevel(
                                    ThinkingLevel.values[i],
                                  );
                                  Navigator.of(sheetCtx).pop();
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (i + 1 < ThinkingLevel.values.length)
                              Expanded(
                                child: _LevelOption(
                                  level: ThinkingLevel.values[i + 1],
                                  selected:
                                      ctrl.thinkingLevel ==
                                      ThinkingLevel.values[i + 1],
                                  onTap: () {
                                    ctrl.setThinkingLevel(
                                      ThinkingLevel.values[i + 1],
                                    );
                                    Navigator.of(sheetCtx).pop();
                                  },
                                ),
                              )
                            else
                              const Spacer(),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 上下文详情：点占用条时弹出，解释这些数字从哪来。
  void _showContextDetail() {
    final ctrl = widget.controller;
    final threshold = ctrl.settings?.aiCompressThreshold ?? 20;
    final keep = ctrl.settings?.aiKeepRecent ?? 8;
    final count = ctrl.currentEntryCount;
    final compressed = ctrl.lastCompressed;
    final dropped = ctrl.lastDroppedCount;

    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        final c = ctx.appColors;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '上下文',
                  style: TextStyle(fontSize: 15, color: c.textPrimary),
                ),
                const SizedBox(height: 12),
                _kv(c, '当前消息', '$count 条'),
                _kv(c, '压缩阈值', '$threshold 条'),
                _kv(c, '保留最近', '$keep 条'),
                if (compressed) _kv(c, '上次请求', '已折叠 $dropped 条��消息'),
                if (ctrl.lastSentTokens > 0)
                  _kv(c, '上次估算 token', '约 ${ctrl.lastSentTokens}'),
                const SizedBox(height: 12),
                Text(
                  '超过阈值后，较早的消息会被折叠成一段摘要，'
                  '最近 $keep 条原样保留。\n\n'
                  '阈值可以在「设置 → AI → 上下文压缩阈值」里调整。',
                  style: TextStyle(
                    fontSize: 11,
                    color: c.textTertiary,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _kv(AppColors c, String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text(k, style: TextStyle(fontSize: 12, color: c.textTertiary)),
          const Spacer(),
          Text(v, style: TextStyle(fontSize: 12, color: c.textSecondary)),
        ],
      ),
    );
  }

  // ── 操作 ────────────────────────────────────────────

  Future<void> _send() async {
    final text = _input.text;
    if (text.trim().isEmpty) return;

    // 先问一句「能不能发」，不能发就**不要清空输入框**。
    //
    // 之前是先 clear 再调 send，而 send 的前置检查失败时只往
    // controller.lastError 写一行字、界面上不显示，结果就是
    // 用户打的话凭空消失、又没有任何提示。
    final reason = widget.controller.validateSend();
    if (reason != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(reason)));
      return;
    }

    _input.clear();

    final started = await widget.controller.send(
      text,
      onApproval: _askApproval,
    );

    // send 还有一道 validateSend 覆盖不到的检查：API Key 是异步读的。
    // 没填 key 时 send 会早退、输入已经被 clear 掉了。
    // 这里把话还给用户 —— 重新打一遍比什么都不剩好得多。
    if (!started && mounted && _input.text.isEmpty) {
      _input.text = text;
    }
  }

  Future<void> _newChat() async {
    await widget.controller.newSession();
    if (mounted) setState(() {});
  }

  Future<void> _openEndpoints() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AiEndpointsPage(controller: widget.controller),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openSwitcher() async {
    if (widget.controller.busy) return;
    await showModelSwitcher(context, widget.controller);
    if (mounted) setState(() {});
  }

  /// AppBar 第二行文字：`端点 · 模型`
  String _modelLabel(AiController ctrl) {
    final ep = ctrl.activeEndpoint;
    if (ep == null) return '未配置端点';
    final model = ep.model.trim();
    return model.isEmpty ? '${ep.name} · 未选模型' : '${ep.name} · $model';
  }

  Future<void> _openHistory() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _HistorySheet(controller: widget.controller),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openScope() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (_) => _ScopeSheet(controller: widget.controller),
    );
    if (mounted) setState(() {});
  }

  Future<void> _rollback(ChatEntry entry) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('撤销这次写入'),
        content: Text(
          '将恢复：\n${entry.backups.map((b) => b.relPath).join('\n')}\n\n'
          '这会覆盖当前文件内容，不可再撤销。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('撤销'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final done = await widget.controller.rollback(entry);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(done ? '已恢复' : '撤销失败')));
  }

  /// 撤回：先算出「会被删掉的消息里一共涉及哪些文件」，
  /// 再让用户决定是否一并回滚。
  ///
  /// 为什么要先算文件：用户看不到 backups 的存在，
  /// 如果只问「要回滚文件吗」，他根本不知道会动哪些文件。
  Future<void> _recall(ChatEntry entry) async {
    final ctrl = widget.controller;
    final session = ctrl.session;
    if (session == null) return;

    final idx = session.entries.indexOf(entry);
    if (idx < 0) return;

    // user 消息撤回「这条及之后」，assistant 消息只撤回「这条」
    final isUser = entry.isUser;
    final removed = isUser ? session.entries.sublist(idx) : [entry];

    final files = <String>{
      for (final e in removed)
        for (final b in e.backups) b.relPath,
    };

    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('撤回对话'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isUser
                  ? '将删除这条提问及其之后的 ${removed.length} 条消息。'
                  : '将只删除这条回复，上面的提问会保留。',
              style: const TextStyle(fontSize: 13, height: 1.5),
            ),
            if (files.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                '这段对话写过 ${files.length} 个文件：',
                style: TextStyle(
                  fontSize: 12,
                  color: ctx.appColors.textTertiary,
                ),
              ),
              const SizedBox(height: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 120),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final f in files)
                        Text(
                          '· $f',
                          style: const TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('取消'),
          ),
          if (files.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('keep'),
              child: const Text('只删对话'),
            ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop('rollback'),
            child: Text(files.isEmpty ? '撤回' : '对话和文件一起回滚'),
          ),
        ],
      ),
    );

    if (choice == null) return;

    final rolledBack = await ctrl.recallFromEntry(
      entry,
      rollbackFiles: choice == 'rollback',
      single: !isUser,
    );
    if (!mounted) return;

    if (rolledBack < 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('撤回失败')));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          choice == 'rollback' && rolledBack > 0
              ? '已撤回对话，并恢复 $rolledBack 个文件'
              : '已撤回对话',
        ),
      ),
    );
  }

  /// 原样重发。
  ///
  /// 和「编辑后重发」分开问，因为这里的 diff 是零 ——
  /// 用户想要的只是「同样的问法，让模型再答一次」。
  /// 再生成一次：保留这条旧回答，重新回答同一个问题。
  ///
  /// 与「原样重发」的区别是语义上的，必须说清楚：
  /// - 重发：旧回答没了（被撤回），文件也回滚
  /// - 再生成：旧回答还在，文件不动，新回答追加在后面
  ///
  /// 所以这里不给确认弹窗 —— 它不删任何东西，没有破坏性。
  Future<void> _regenerate(ChatEntry entry) async {
    if (entry.isUser) return;
    final ctrl = widget.controller;
    if (ctrl.busy) return;

    final ok = await ctrl.regenerate(onApproval: _askApproval);
    if (!ok && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法重新生成：没有可重答的提问')));
    }
  }

  Future<void> _resend(ChatEntry entry) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重新发送'),
        content: const Text(
          '会撤回这条提问及其后的全部对话，然后原样再问一次。\n'
          '这段对话写过的文件会一并回滚。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('重发'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    await widget.controller.resend(entry, onApproval: _askApproval);
    if (mounted) setState(() {});
  }

  /// 编辑用户消息后重发。
  Future<void> _editEntry(ChatEntry entry) async {
    final ctrl = TextEditingController(text: entry.text);

    final newText = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑后重发'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '保存后会撤回这条及之后的对话，并回滚相关文件，再按新内容提问。',
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: ctx.appColors.textTertiary,
              ),
            ),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: TextField(
                controller: ctrl,
                maxLines: null,
                minLines: 4,
                autofocus: true,
                style: const TextStyle(fontSize: 14, height: 1.6),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text),
            child: const Text('保存并重发'),
          ),
        ],
      ),
    );

    ctrl.dispose();
    if (newText == null) return;
    if (newText.trim().isEmpty) return;
    if (newText.trim() == entry.text.trim()) {
      // 内容没变就别白白回滚文件
      await _resend(entry);
      return;
    }

    await widget.controller.editAndResend(
      entry,
      newText,
      onApproval: _askApproval,
    );
    if (mounted) setState(() {});
  }

  Future<void> _deleteEntry(ChatEntry entry) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这条'),
        content: const Text('只从对话里移除，不改动任何文件。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: context.appColors.danger,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.controller.deleteEntry(entry);
    if (mounted) setState(() {});
  }

  /// 写盘审批回调抽出来，供 send / resend / editAndResend 共用。
  Future<ApprovalDecision?> _askApproval(ApprovalRequest req) async {
    if (!mounted) return ApprovalDecision.reject;
    final result = await showModalBottomSheet<ApprovalDecision>(
      context: context,
      isScrollControlled: true,
      // 写盘的确认不允许点外部关闭：误触等于默认拒绝，
      // 但用户会以为「点了就写了」，反而更困惑
      isDismissible: false,
      enableDrag: false,
      builder: (_) => WriteApprovalSheet(request: req),
    );
    return result ?? ApprovalDecision.reject;
  }
}

// ── 子组件 ──────────────────────────────────────────

class _NeedEndpoint extends StatelessWidget {
  const _NeedEndpoint({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.smart_toy_outlined, size: 44, color: c.textTertiary),
            const SizedBox(height: AppSpace.md),
            Text(
              '先配置一个 AI 端点',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpace.xs),
            Text(
              '兼容 OpenAI 协议的地址都可以，\n可以配多个随时切换。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.6,
                color: c.textTertiary,
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            FilledButton(onPressed: onAdd, child: const Text('去配置')),
          ],
        ),
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat({required this.model, required this.endpoint});

  final String model;
  final String endpoint;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome, size: 32, color: c.accent),
            const SizedBox(height: AppSpace.md),
            Text(
              '开始一次对话',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpace.xs),
            Text(
              model.isEmpty ? '未选择模型' : '$endpoint · $model',
              style: TextStyle(fontSize: 11, color: c.textTertiary),
            ),
            const SizedBox(height: AppSpace.lg),
            Text(
              '试试：「根据我的想法写一篇关于 XX 的短文」\n'
              '或直接把一个网址发给我',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.7,
                color: c.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EntryView extends StatelessWidget {
  const _EntryView({
    required this.entry,
    required this.onRollback,
    required this.onRecall,
    required this.onResend,
    required this.onRegenerate,
    required this.onEdit,
    required this.onDelete,
    required this.busy,
  });

  final ChatEntry entry;
  final VoidCallback onRollback;
  final VoidCallback onRecall;
  final VoidCallback onResend;

  /// 保留旧回答，再生成一次
  final VoidCallback onRegenerate;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  /// 生成中时禁用一切改写操作：
  /// 撤回/重发会把正在进行的那一轮的上下文抽走。
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final isUser = entry.isUser;

    final row = Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: Column(
        crossAxisAlignment: isUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          if (!isUser)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  margin: const EdgeInsets.only(top: 2),
                  decoration: BoxDecoration(
                    color: entry.isError
                        ? c.danger.withValues(alpha: 0.12)
                        : c.accentSoft,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Icon(
                    entry.isError ? Icons.error_outline : Icons.auto_awesome,
                    size: 13,
                    color: entry.isError ? c.danger : c.accent,
                  ),
                ),
                const SizedBox(width: AppSpace.xs),
                Flexible(child: _body(context, entry)),
              ],
            )
          else
            // 这里不能用 Flexible：
            // ListView 的 item 纵向无界，Column 里带 flex 的子项会抛
            // "incoming height constraints are unbounded"，导致整条
            // 消息画不出来（用户看到的现象就是「发的消息不显示」）。
            _body(context, entry),
        ],
      ),
    );

    if (busy) return row;

    // 长按弹菜单。不带「点按」—— 点消息体应该还能选中文字，
    // 加 onTap 会和文本选择手势打架。
    return GestureDetector(
      onLongPress: () => _showActions(context),
      behavior: HitTestBehavior.translucent,
      child: row,
    );
  }

  void _showActions(BuildContext context) {
    final c = context.appColors;

    showModalBottomSheet<void>(
      context: context,
      builder: (sheetCtx) => SafeArea(
        child: SizedBox(
          width: MediaQuery.sizeOf(sheetCtx).width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.md,
                  AppSpace.md,
                  AppSpace.md,
                  AppSpace.xs,
                ),
                child: Text(
                  entry.isUser ? '这条提问' : '这条回复',
                  style: TextStyle(fontSize: 11, color: c.textTertiary),
                ),
              ),
              if (entry.isUser) ...[
                ListTile(
                  leading: const Icon(Icons.edit_outlined, size: 20),
                  title: const Text('编辑后重发'),
                  subtitle: Text(
                    '改完会撤回这条及之后的对话，并回滚相关文件',
                    style: TextStyle(fontSize: 11, color: c.textTertiary),
                  ),
                  onTap: () {
                    Navigator.of(sheetCtx).pop();
                    onEdit();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.refresh, size: 20),
                  title: const Text('原样重发'),
                  subtitle: Text(
                    '撤回这条及之后，再问一次',
                    style: TextStyle(fontSize: 11, color: c.textTertiary),
                  ),
                  onTap: () {
                    Navigator.of(sheetCtx).pop();
                    onResend();
                  },
                ),
              ],
              if (!entry.isUser)
                ListTile(
                  leading: const Icon(Icons.autorenew, size: 20),
                  title: const Text('再生成一次'),
                  subtitle: Text(
                    '保留这条回答，重新问一遍（不回滚文件）',
                    style: TextStyle(fontSize: 11, color: c.textTertiary),
                  ),
                  onTap: () {
                    Navigator.of(sheetCtx).pop();
                    onRegenerate();
                  },
                ),
              // 撤回：user 消息撤回「这条之后」；assistant 消息撤回「这条」
              ListTile(
                leading: const Icon(Icons.history_toggle_off, size: 20),
                title: Text(entry.isUser ? '撤回这条及之后' : '撤回这条'),
                subtitle: Text(
                  entry.isUser ? '删掉这条提问及其后的全部对话' : '只删掉这条回复',
                  style: TextStyle(fontSize: 11, color: c.textTertiary),
                ),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  onRecall();
                },
              ),
              if (entry.canRollback)
                ListTile(
                  leading: Icon(Icons.undo, size: 20, color: c.accent),
                  title: Text('撤销写入（${entry.backups.length} 个文件）'),
                  subtitle: Text(
                    '把这条回复写过的文件恢复原样，对话保留',
                    style: TextStyle(fontSize: 11, color: c.textTertiary),
                  ),
                  onTap: () {
                    Navigator.of(sheetCtx).pop();
                    onRollback();
                  },
                ),
              ListTile(
                leading: Icon(Icons.delete_outline, size: 20, color: c.danger),
                title: Text('删除这条', style: TextStyle(color: c.danger)),
                subtitle: Text(
                  '不动文件，只从对话里移除',
                  style: TextStyle(fontSize: 11, color: c.textTertiary),
                ),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  onDelete();
                },
              ),
              const SizedBox(height: AppSpace.sm),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, ChatEntry e) {
    final c = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 历史里的思考过程：默认收起，点开看全文。
        // 放在消息体上方，与流式时的顺序保持一致。
        if (!e.isUser && e.reasoning.trim().isNotEmpty)
          ThinkingBlock(text: e.reasoning),
        Container(
          padding: const EdgeInsets.all(AppSpace.sm),
          decoration: BoxDecoration(
            color: e.isUser
                ? c.accentSoft
                : (e.isError ? c.danger.withValues(alpha: 0.08) : c.surface),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: e.isUser || e.isError
              ? SelectableText(
                  e.text.isEmpty ? '…' : e.text,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.7,
                    color: e.isError ? c.danger : c.textPrimary,
                  ),
                )
              : ChatMarkdown(e.text.isEmpty ? '…' : e.text),
        ),

        // 工具调用：折叠成一行
        for (final t in e.toolCalls) _ToolStrip(record: t),

        if (e.canRollback)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: onRollback,
                  icon: const Icon(Icons.undo, size: 14),
                  label: Text(
                    '撤销写入（${e.backups.length} 个文件）',
                    style: const TextStyle(fontSize: 11),
                  ),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: c.textSecondary,
                  ),
                ),
              ],
            ),
          ),

        if (e.promptTokens != null || e.completionTokens != null)
          Padding(
            padding: const EdgeInsets.only(top: 2, left: 2),
            child: Text(
              // 服务端给了 usage 才是真值；没给是我们按字数估的。
              // 必须标出来 —— 把估算值当精确统计展示是误导。
              '${e.promptTokens ?? 0} 入 / ${e.completionTokens ?? 0} 出 token'
              '${e.usageIsExact ? '' : '（估算）'}',
              style: TextStyle(fontSize: 10, color: c.textTertiary),
            ),
          ),
      ],
    );
  }
}

class _ToolStrip extends StatefulWidget {
  const _ToolStrip({required this.record});

  final ToolCallRecord record;

  @override
  State<_ToolStrip> createState() => _ToolStripState();
}

class _ToolStripState extends State<_ToolStrip> {
  bool _open = false;

  IconData get _icon => switch (widget.record.name) {
    'list_notes' || 'search_notes' => Icons.lightbulb_outline,
    'read_note' => Icons.sticky_note_2_outlined,
    'read_post' => Icons.description_outlined,
    'write_post' => Icons.edit_note,
    'fetch_url' => Icons.link,
    _ => Icons.build_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final r = widget.record;

    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 3),
      child: InkWell(
        onTap: () => setState(() => _open = !_open),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_icon, size: 12, color: r.ok ? c.textTertiary : c.danger),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    r.summary.isEmpty ? r.name : r.summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: r.ok ? c.textTertiary : c.danger,
                    ),
                  ),
                ),
                AnimatedRotation(
                  turns: _open ? 0.25 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(
                    Icons.chevron_right,
                    size: 13,
                    color: c.textTertiary,
                  ),
                ),
              ],
            ),
            if (_open)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 3, bottom: 2),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: SelectableText(
                  '参数：${r.arguments}\n\n${r.detail}',
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.5,
                    fontFamily: 'monospace',
                    color: c.textSecondary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StreamingBubble extends StatelessWidget {
  const _StreamingBubble({
    required this.text,
    required this.runningTool,
    this.reasoning,
  });

  final String text;
  final String? runningTool;

  /// 思考过程。null 或空表示该模型不返回思考内容。
  final String? reasoning;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              color: c.accentSoft,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(Icons.auto_awesome, size: 13, color: c.accent),
          ),
          const SizedBox(width: AppSpace.xs),
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(AppSpace.sm),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (reasoning != null && reasoning!.trim().isNotEmpty)
                    ThinkingBlock(text: reasoning!, streaming: true),
                  if (runningTool != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 10,
                            height: 10,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: c.accent,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _toolLabel(runningTool!),
                            style: TextStyle(
                              fontSize: 11,
                              color: c.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  SelectableText(
                    text.isEmpty ? '…' : text,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.7,
                      color: c.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _toolLabel(String name) => switch (name) {
    'list_notes' => '正在列出想法…',
    'read_note' => '正在读取想法…',
    'search_notes' => '正在搜索想法…',
    'read_post' => '正在读取文章…',
    'write_post' => '准备写入文章…',
    'fetch_url' => '正在抓取网页…',
    _ => '正在执行 $name…',
  };
}

/// 输入框上方：当前端点 · 模型，点击打开快速切换。
class _ModelBar extends StatelessWidget {
  const _ModelBar({
    required this.label,
    required this.busy,
    required this.onTap,
    required this.entryCount,
    required this.threshold,
    required this.compressed,
    required this.onContextTap,
    required this.thinkingLevel,
    required this.thinkingHint,
    required this.onThinkingTap,
  });

  final String label;
  final bool busy;
  final VoidCallback onTap;

  /// 当前会话消息条数
  final int entryCount;

  /// 压缩阈值
  final int threshold;

  /// 上次请求是否发生了压缩
  final bool compressed;

  final VoidCallback onContextTap;

  /// 当前思考档位
  final ThinkingLevel thinkingLevel;

  /// 档位在当前端点上是否生效（null = 生效）
  final String? thinkingHint;

  final VoidCallback onThinkingTap;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return InkWell(
      // 生成中不允许切换：请求已经带着旧端点飞出去了，
      // 中途换模型会让这一轮的记录和实际请求对不上。
      onTap: busy ? null : onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.md,
          vertical: 5,
        ),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: c.divider, width: 1)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.bolt,
                  size: 12,
                  color: busy ? c.textTertiary : c.accent,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    busy ? '$label（生成中，暂不可切换）' : label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: busy ? c.textTertiary : c.textSecondary,
                    ),
                  ),
                ),
                Icon(Icons.swap_horiz, size: 13, color: c.textTertiary),
                const SizedBox(width: 3),
                Text(
                  '切换',
                  style: TextStyle(fontSize: 10, color: c.textTertiary),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: _ContextMeter(
                    entryCount: entryCount,
                    threshold: threshold,
                    compressed: compressed,
                    onTap: onContextTap,
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                _ThinkingChip(
                  level: thinkingLevel,
                  hint: thinkingHint,
                  onTap: onThinkingTap,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 上下文占用条。
///
/// ## 为什么分母是「压缩阈值」而不是模型窗口
///
/// 用户接的端点可能是 64K 也可能是 8K，我们不知道。
/// 但「离触发压缩还有多远」是确定的，也是用户唯一能据此行动的数字 ——
/// 快满了就主动开个新对话，而不是等模型报超限。
///
/// ## 为什么显示条数而不是 token
///
/// token 是估算值（见 estimateTokens 的注释），拿估算值当精确数字展示
/// 会误导用户。条数是确定的事实，阈值也是条数，两者能直接比。
class _ContextMeter extends StatelessWidget {
  const _ContextMeter({
    required this.entryCount,
    required this.threshold,
    required this.compressed,
    required this.onTap,
  });

  final int entryCount;
  final int threshold;
  final bool compressed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final ratio = threshold <= 0
        ? 0.0
        : (entryCount / threshold).clamp(0.0, 1.0);

    // 三档：宽裕 / 接近阈值 / 已压缩过
    final color = compressed
        ? c.danger
        : ratio >= 0.8
        ? c.warning
        : c.accent;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 1),
        child: Row(
          children: [
            Icon(
              Icons.donut_small,
              size: 10,
              color: compressed ? c.danger : c.textTertiary,
            ),
            const SizedBox(width: 4),
            Text(
              compressed ? '已压缩' : '上下文',
              style: TextStyle(fontSize: 10, color: c.textTertiary),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 3,
                  backgroundColor: c.divider,
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '$entryCount / $threshold 条',
              style: TextStyle(
                fontSize: 10,
                color: compressed ? c.danger : c.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 单个档位选项（弹窗里的胶囊）。
///
/// 高度固定 60：足够放下「名称 + 一句说明」两行，
/// 也超过 Material 的 48px 最小触控尺寸，不会误触。
class _LevelOption extends StatelessWidget {
  const _LevelOption({
    required this.level,
    required this.selected,
    required this.onTap,
  });

  final ThinkingLevel level;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Container(
        constraints: const BoxConstraints(minHeight: 60),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? c.accentSoft : c.surface.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(
            color: selected ? c.accent.withValues(alpha: 0.5) : c.divider,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 13,
                  color: selected ? c.accent : c.textTertiary,
                ),
                const SizedBox(width: 4),
                Text(
                  level.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected ? c.accent : c.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              level.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9.5,
                height: 1.25,
                color: c.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 思考档位胶囊按钮。
///
/// 放在对话页而不是设置页，因为它是每一轮都可能变的选项：
/// 这一句想问深一点，下一句只是查个事实。
///
/// ## 尺寸
///
/// 视觉高度与命中区域都是 44px。上一版是 fontSize 10 的纯文字
/// （实测只有 29px 高），远小于 Material 建议的 48px，
/// 拇指很难按准；44 是「好点」与「不挤占工具栏」的折中。
class _ThinkingChip extends StatelessWidget {
  const _ThinkingChip({
    required this.level,
    required this.hint,
    required this.onTap,
  });

  final ThinkingLevel level;

  /// 非 null 表示当前端点无法完整表达这个档位
  final String? hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final active = level.isThinking;
    // 端点不支持时用灰色，避免让人以为已经生效
    final effective = hint == null;
    final fg = !effective
        ? c.textTertiary
        : (active ? c.accent : c.textSecondary);

    return Semantics(
      button: true,
      label: '思考档位：${level.label}，点击切换',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: active && effective
                ? c.accentSoft
                : c.surface.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
              color: active && effective
                  ? c.accent.withValues(alpha: 0.35)
                  : c.divider,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                active ? Icons.psychology : Icons.psychology_outlined,
                size: 15,
                color: fg,
              ),
              const SizedBox(width: 5),
              Text(
                level.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: active && effective
                      ? FontWeight.w600
                      : FontWeight.w400,
                  color: fg,
                ),
              ),
              if (!effective) ...[
                const SizedBox(width: 3),
                Icon(Icons.info_outline, size: 11, color: c.textTertiary),
              ],
              const SizedBox(width: 1),
              Icon(Icons.arrow_drop_down, size: 18, color: fg),
            ],
          ),
        ),
      ),
    );
  }
}

/// 输入框上方：显示本次会注入哪些想法
class _ContextBar extends StatelessWidget {
  const _ContextBar({required this.controller, required this.onTap});

  final AiController controller;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final sel = controller.lastContext;
    final String label;
    if (sel == null) {
      label = '尚未发送，想法读取范围未生效';
    } else {
      label = sel.describe();
    }

    // 上下文压缩提示。
    //
    // 用户需要知道「模型已经看不到最早那几轮了」——
    // 否则会觉得「我明明说过，它怎么忘了」。
    final compressed = controller.lastCompressed;
    final dropped = controller.lastDroppedCount;

    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.md,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: c.divider, width: 1)),
        ),
        child: Row(
          children: [
            Icon(Icons.lightbulb_outline, size: 12, color: c.textTertiary),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: c.textTertiary),
              ),
            ),
            if (compressed) ...[
              const SizedBox(width: 6),
              Icon(Icons.compress, size: 11, color: c.textTertiary),
              const SizedBox(width: 3),
              Text(
                '已折叠 $dropped 条',
                style: TextStyle(fontSize: 10, color: c.textTertiary),
              ),
            ],
            const SizedBox(width: 6),
            Icon(Icons.tune, size: 12, color: c.textTertiary),
          ],
        ),
      ),
    );
  }
}

/// 一条可见的错误提示。
///
/// 存在的理由：`AiController.lastError` 之前只被赋值、从没被渲染，
/// 所以模型配置不全、网络失败、key 错误这些情况在界面上完全看不出，
/// 用户只能看到「发了没反应」。
class _ErrorBar extends StatelessWidget {
  const _ErrorBar({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Container(
      width: double.infinity,
      color: c.danger.withValues(alpha: 0.08),
      padding: const EdgeInsets.fromLTRB(AppSpace.md, 6, AppSpace.xs, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(Icons.error_outline, size: 13, color: c.danger),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 11, height: 1.5, color: c.danger),
            ),
          ),
          SizedBox(
            width: 28,
            height: 24,
            child: InkWell(
              onTap: onDismiss,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: Icon(Icons.close, size: 13, color: c.danger),
            ),
          ),
        ],
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.busy,
    required this.onSend,
    required this.onCancel,
  });

  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSend;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.md,
          AppSpace.xs,
          AppSpace.md,
          AppSpace.sm,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 5,
                // 生成中也允许打字。
                //
                // 之前是 enabled: !busy，理由是「避免用户在等待时误发」。
                // 但实际体验很差：模型输出要几十秒，这段时间用户
                // 既不能整理思路，也不能先打好下一句 —— 而打字
                // 根本不会干扰正在进行的那一轮（发送按钮此时是停止键）。
                // 真正需要防的是「误触发送」，那由按钮状态负责。
                style: TextStyle(fontSize: 14, color: c.textPrimary),
                decoration: const InputDecoration(hintText: '说点什么…'),
              ),
            ),
            const SizedBox(width: AppSpace.xs),
            SizedBox(
              width: 44,
              height: 44,
              child: Material(
                color: busy ? c.surface : c.accent,
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  onTap: busy ? onCancel : onSend,
                  child: Icon(
                    busy ? Icons.stop : Icons.arrow_upward,
                    size: 20,
                    color: busy
                        ? c.textSecondary
                        : (Theme.of(context).brightness == Brightness.light
                              ? Colors.white
                              : c.background),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 读取范围设置
class _ScopeSheet extends StatefulWidget {
  const _ScopeSheet({required this.controller});

  final AiController controller;

  @override
  State<_ScopeSheet> createState() => _ScopeSheetState();
}

class _ScopeSheetState extends State<_ScopeSheet> {
  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final ctrl = widget.controller;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'AI 读取想法的范围',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpace.xs),
            Text(
              '想法是私人内容，默认不读。打开后才允许读取。',
              style: TextStyle(fontSize: 12, color: c.textTertiary),
            ),
            const SizedBox(height: AppSpace.sm),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('允许读取想法', style: TextStyle(fontSize: 14)),
              value: ctrl.readNotes,
              onChanged: (v) {
                ctrl.setReadScope(enabled: v);
                setState(() {});
              },
            ),
            Text(
              ctrl.readNotes ? '读取全部想法（在想法页指定分组可缩小范围）' : '不读取任何想法',
              style: TextStyle(fontSize: 11, color: c.textTertiary),
            ),
            const SizedBox(height: AppSpace.md),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('完成'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 历史对话
class _HistorySheet extends StatefulWidget {
  const _HistorySheet({required this.controller});

  final AiController controller;

  @override
  State<_HistorySheet> createState() => _HistorySheetState();
}

class _HistorySheetState extends State<_HistorySheet> {
  /// 当前标签页：0 = 活跃，1 = 已归档
  ///
  /// 用「归档」单独一个页签而不是同一列表里的折叠区：
  /// 归档的目的是「眼不见心不烦」，混在活跃列表里每次都要划过去，
  /// 等于没归档。
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final ctrl = widget.controller;
    final activeCount = ctrl.activeSessions.length;
    final archivedCount = ctrl.archivedSessions.length;

    return SafeArea(
      child: SizedBox(
        width: MediaQuery.sizeOf(context).width,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.75,
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '历史对话',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: c.textPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '管理分组',
                      icon: Icon(
                        Icons.create_new_folder_outlined,
                        size: 18,
                        color: c.textTertiary,
                      ),
                      onPressed: () => _openGroupManager(context),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.xs),
                // 两个页签：活跃 / 已归档
                Row(
                  children: [
                    _tabButton('活跃 $activeCount', 0, c),
                    const SizedBox(width: 8),
                    _tabButton('已归档 $archivedCount', 1, c),
                  ],
                ),
                const SizedBox(height: AppSpace.sm),
                if (_tab == 0)
                  Flexible(child: _buildActiveList(c))
                else
                  Flexible(child: _buildArchivedList(c)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tabButton(String label, int index, AppColors c) {
    final selected = _tab == index;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => setState(() => _tab = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? c.accent.withValues(alpha: 0.12) : c.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? c.accent : c.divider,
            width: selected ? 1 : 0.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: selected ? c.accent : c.textTertiary,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  /// 活跃列表：按分组分段
  Widget _buildActiveList(AppColors c) {
    final ctrl = widget.controller;
    final groups = ctrl.groups;
    final ungrouped = ctrl.ungroupedSessions;

    if (ctrl.activeSessions.isEmpty) {
      return _emptyHint('还没有历史对话', c);
    }

    // 先算好所有段落，再一次性展开成 sliver 列表。
    // 直接用 Column 会在会话多时把高度顶爆（和当初端点弹窗同一个坑），
    // 所以整体走 ListView。
    final rows = <Widget>[];
    for (final g in groups) {
      final list = ctrl.sessionsInGroup(g.id);
      if (list.isEmpty) continue;
      rows.add(_sectionHeader(g.name, list.length, c, groupId: g.id));
      for (final s in list) {
        rows.add(_sessionTile(s, c, archived: false));
      }
    }
    if (ungrouped.isNotEmpty) {
      rows.add(_sectionHeader('未分组', ungrouped.length, c));
      for (final s in ungrouped) {
        rows.add(_sessionTile(s, c, archived: false));
      }
    }

    return ListView(shrinkWrap: true, children: rows);
  }

  Widget _buildArchivedList(AppColors c) {
    final list = widget.controller.archivedSessions;
    if (list.isEmpty) {
      return _emptyHint('没有已归档的对话', c);
    }
    return ListView(
      shrinkWrap: true,
      children: [for (final s in list) _sessionTile(s, c, archived: true)],
    );
  }

  Widget _emptyHint(String text, AppColors c) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.lg),
      child: SizedBox(
        width: double.infinity,
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: c.textTertiary, height: 1.5),
        ),
      ),
    );
  }

  Widget _sectionHeader(
    String name,
    int count,
    AppColors c, {
    String? groupId,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: Row(
        children: [
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: c.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text('$count', style: TextStyle(fontSize: 10, color: c.textTertiary)),
          const Spacer(),
          if (groupId != null)
            InkWell(
              onTap: () => _openGroupActions(groupId),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(Icons.more_horiz, size: 14, color: c.textTertiary),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sessionTile(ChatSession s, AppColors c, {required bool archived}) {
    final active = s.id == widget.controller.session?.id;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        active ? Icons.chat_bubble : Icons.chat_bubble_outline,
        size: 16,
        color: active ? c.accent : c.textTertiary,
      ),
      title: Text(
        s.title.isEmpty ? '未命名' : s.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13,
          color: active ? c.accent : c.textPrimary,
        ),
      ),
      subtitle: Text(
        '${s.entries.length} 条 · ${_fmtTime(s.updatedAt)}',
        style: TextStyle(fontSize: 11, color: c.textTertiary),
      ),
      // 长按移动分组：只加长按不加按钮，
      // 因为每行已经有两个按钮（归档/删除），再加一个太挤。
      // 长按也是系统里「更多操作」的惯例位置。
      onLongPress: archived ? null : () => _moveToGroup(s),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!archived)
            IconButton(
              tooltip: '归档',
              icon: Icon(
                Icons.archive_outlined,
                size: 16,
                color: c.textTertiary,
              ),
              onPressed: () async {
                await widget.controller.archiveSession(s.id);
                if (context.mounted) setState(() {});
              },
            )
          else ...[
            IconButton(
              tooltip: '恢复',
              icon: Icon(
                Icons.unarchive_outlined,
                size: 16,
                color: c.textTertiary,
              ),
              onPressed: () async {
                await widget.controller.unarchiveSession(s.id);
                if (context.mounted) setState(() {});
              },
            ),
            IconButton(
              tooltip: '彻底删除',
              icon: Icon(Icons.delete_outline, size: 16, color: c.danger),
              onPressed: () => _confirmDelete(s),
            ),
          ],
        ],
      ),
      onTap: () async {
        // 先取到 Navigator，再 await：
        // await 之后 context 可能已失效，那时再读 context 就是跨异步间隙。
        final nav = Navigator.of(context);
        await widget.controller.openSession(s.id);
        nav.pop();
      },
    );
  }

  /// 长按会话：选一个分组移过去（含「未分组」）。
  Future<void> _moveToGroup(ChatSession s) async {
    final c = context.appColors;
    final groups = widget.controller.groups;
    final picked = await showModalBottomSheet<String?>(
      context: context,
      builder: (bctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '移动到分组',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                  ),
                ),
              ),
            ),
            // 空串代表「移回未分组」，与 null（取消）区分开
            ListTile(
              dense: true,
              leading: Icon(
                Icons.inbox_outlined,
                size: 18,
                color: c.textTertiary,
              ),
              title: const Text('未分组', style: TextStyle(fontSize: 13)),
              trailing: s.groupId.isEmpty
                  ? Icon(Icons.check, size: 16, color: c.accent)
                  : null,
              onTap: () => Navigator.of(bctx).pop(''),
            ),
            if (groups.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '还没有分组，点右上角文件夹图标新建',
                  style: TextStyle(fontSize: 12, color: c.textTertiary),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: groups.length,
                  itemBuilder: (_, i) {
                    final g = groups[i];
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        Icons.folder_outlined,
                        size: 18,
                        color: c.textTertiary,
                      ),
                      title: Text(
                        g.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                      trailing: s.groupId == g.id
                          ? Icon(Icons.check, size: 16, color: c.accent)
                          : null,
                      onTap: () => Navigator.of(bctx).pop(g.id),
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked == null) return;
    await widget.controller.moveToGroup(s.id, picked);
    if (mounted) setState(() {});
  }

  Future<void> _confirmDelete(ChatSession s) async {
    final c = context.appColors;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('彻底删除这个对话？'),
        content: Text(
          '「${s.title.isEmpty ? '未命名' : s.title}」将被永久删除，无法恢复。',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(true),
            child: Text('删除', style: TextStyle(color: c.danger)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.controller.deleteSession(s.id);
    if (mounted) setState(() {});
  }

  Future<void> _openGroupManager(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _GroupSheet(controller: widget.controller),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openGroupActions(String groupId) async {
    final c = context.appColors;
    final group = widget.controller.groups.firstWhere(
      (g) => g.id == groupId,
      orElse: () => ChatGroup(id: groupId, name: ''),
    );
    await showModalBottomSheet<void>(
      context: context,
      builder: (bctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined, size: 18),
              title: const Text('重命名分组', style: TextStyle(fontSize: 13)),
              onTap: () {
                Navigator.of(bctx).pop();
                _renameGroup(group);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, size: 18, color: c.danger),
              title: Text(
                '删除分组',
                style: TextStyle(fontSize: 13, color: c.danger),
              ),
              subtitle: const Text(
                '不删除对话，只把它们移回未分组',
                style: TextStyle(fontSize: 11),
              ),
              onTap: () {
                Navigator.of(bctx).pop();
                widget.controller.deleteGroup(groupId);
              },
            ),
          ],
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _renameGroup(ChatGroup g) async {
    final ctrl = TextEditingController(text: g.name);
    final name = await showDialog<String>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('重命名分组'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(isDense: true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(ctrl.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (name != null) {
      await widget.controller.renameGroup(g.id, name);
      if (mounted) setState(() {});
    }
  }

  String _fmtTime(DateTime t) {
    final now = DateTime.now();
    final diff = now.difference(t);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
    if (diff.inDays < 1) return '${diff.inHours} 小时前';
    if (diff.inDays < 30) return '${diff.inDays} 天前';
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-'
        '${t.day.toString().padLeft(2, '0')}';
  }
}

/// 分组管理：新建 / 重命名 / 删除
class _GroupSheet extends StatefulWidget {
  const _GroupSheet({required this.controller});
  final AiController controller;
  @override
  State<_GroupSheet> createState() => _GroupSheetState();
}

class _GroupSheetState extends State<_GroupSheet> {
  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final groups = widget.controller.groups;
    return SafeArea(
      child: SizedBox(
        width: MediaQuery.sizeOf(context).width,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.7,
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '对话分组',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: c.textPrimary,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('新建', style: TextStyle(fontSize: 12)),
                      onPressed: () => _create(context),
                    ),
                  ],
                ),
                if (groups.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpace.lg),
                    child: SizedBox(
                      width: double.infinity,
                      child: Text(
                        '还没有分组',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: c.textTertiary,
                          height: 1.5,
                        ),
                      ),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: groups.length,
                      itemBuilder: (_, i) {
                        final g = groups[i];
                        final count = widget.controller
                            .sessionsInGroup(g.id)
                            .length;
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            Icons.folder_outlined,
                            size: 16,
                            color: c.textTertiary,
                          ),
                          title: Text(
                            g.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                          subtitle: Text(
                            '$count 个对话',
                            style: TextStyle(
                              fontSize: 11,
                              color: c.textTertiary,
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(
                                  Icons.edit_outlined,
                                  size: 16,
                                  color: c.textTertiary,
                                ),
                                onPressed: () => _rename(context, g),
                              ),
                              IconButton(
                                icon: Icon(
                                  Icons.delete_outline,
                                  size: 16,
                                  color: c.danger,
                                ),
                                onPressed: () async {
                                  await widget.controller.deleteGroup(g.id);
                                  if (mounted) setState(() {});
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _create(BuildContext context) async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('新建分组'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '例如：写作辅助', isDense: true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(ctrl.text),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      await widget.controller.addGroup(name);
      if (mounted) setState(() {});
    }
  }

  Future<void> _rename(BuildContext context, ChatGroup g) async {
    final ctrl = TextEditingController(text: g.name);
    final name = await showDialog<String>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('重命名分组'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(isDense: true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(ctrl.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (name != null) {
      await widget.controller.renameGroup(g.id, name);
      if (mounted) setState(() {});
    }
  }
}
