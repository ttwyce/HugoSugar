import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../core/ai/agent_runner.dart';
import '../../core/ai/ai_controller.dart';
import '../../core/ai/chat_store.dart';
import 'ai_endpoints_page.dart';
import 'model_switcher_sheet.dart';
import 'write_approval_sheet.dart';
import 'chat_markdown.dart';

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
                          itemCount: entries.length +
                              (ctrl.streamingText != null ? 1 : 0),
                          itemBuilder: (_, i) {
                            if (i < entries.length) {
                              return _EntryView(
                                entry: entries[i],
                                onRollback: () => _rollback(entries[i]),
                              );
                            }
                            return _StreamingBubble(
                              text: ctrl.streamingText ?? '',
                              runningTool: ctrl.runningTool,
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(reason)),
      );
      return;
    }

    _input.clear();

    final started = await widget.controller.send(
      text,
      onApproval: (req) async {
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
      },
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(done ? '已恢复' : '撤销失败')),
    );
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
  const _EntryView({required this.entry, required this.onRollback});

  final ChatEntry entry;
  final VoidCallback onRollback;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final isUser = entry.isUser;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
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
                    color: entry.isError ? c.danger.withValues(alpha: 0.12) : c.accentSoft,
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
  }

  Widget _body(BuildContext context, ChatEntry e) {
    final c = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
                Icon(
                  _icon,
                  size: 12,
                  color: r.ok ? c.textTertiary : c.danger,
                ),
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
  const _StreamingBubble({required this.text, required this.runningTool});

  final String text;
  final String? runningTool;

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
  });

  final String label;
  final bool busy;
  final VoidCallback onTap;

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
        child: Row(
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
      padding: const EdgeInsets.fromLTRB(
        AppSpace.md,
        6,
        AppSpace.xs,
        6,
      ),
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
                enabled: !busy,
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
              ctrl.readNotes
                  ? '读取全部想法（在想法页指定分组可缩小范围）'
                  : '不读取任何想法',
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
    final sessions = widget.controller.sessions;

    // 三处结构性修正（都是真机上会出问题的地方）：
    //
    // 1. Column 的横向约束。弹窗 builder 拿到的是无界宽度，
    //    ListTile / IconButton 在这种环境下再叠一层无界就可能
    //    触发布局断言 —— 和端点弹窗是同一类问题。
    //    用 SizedBox 钉死宽度。
    //
    // 2. 高度。原来只有内层 ListView 限了 360，外层 Column
    //    是 mainAxisSize.min，会话一多整体会超出屏幕且**不能滚动**，
    //    底部条目永远点不到。改成外层可滚动 + 高度上限。
    //
    // 3. 空态。用 Center + 固定高度，避免极小高度下只剩一条缝。
    return SafeArea(
      child: SizedBox(
        width: MediaQuery.sizeOf(context).width,
        child: ConstrainedBox(
          // 最多占屏幕高度的 70%，保证底部按钮和内容都够用
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
                        '历史对话',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: c.textPrimary,
                        ),
                      ),
                    ),
                    if (sessions.isNotEmpty)
                      Text(
                        '${sessions.length} 个',
                        style: TextStyle(
                          fontSize: 11,
                          color: c.textTertiary,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpace.sm),
                if (sessions.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpace.lg),
                    child: SizedBox(
                      width: double.infinity,
                      child: Text(
                        '还没有历史对话',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: c.textTertiary),
                      ),
                    ),
                  )
                else
                  // Flexible 而不是固定高度：会话少时按内容撑开，
                  // 多时才滚动，不会出现大片空白。
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: sessions.length,
                      itemBuilder: (_, i) {
                        final s = sessions[i];
                        final active = s.id == widget.controller.session?.id;
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            active
                                ? Icons.chat_bubble
                                : Icons.chat_bubble_outline,
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
                            style: TextStyle(
                              fontSize: 11,
                              color: c.textTertiary,
                            ),
                          ),
                          trailing: IconButton(
                            icon: Icon(
                              Icons.delete_outline,
                              size: 16,
                              color: c.textTertiary,
                            ),
                            onPressed: () async {
                              await widget.controller.deleteSession(s.id);
                              if (context.mounted) setState(() {});
                            },
                          ),
                          onTap: () async {
                            await widget.controller.openSession(s.id);
                            if (context.mounted) Navigator.of(context).pop();
                          },
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