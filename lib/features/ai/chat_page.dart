import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

/// AI 对话页。
///
/// 设计要点（见设计规范 §3.4）：
/// - 工具调用折叠成一行灰条，点开才看详情
/// - 输入框上方显示「本次注入了哪些置顶笔记」，让用户知道 AI 看到了什么
class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI'),
        actions: [
          IconButton(onPressed: () {}, icon: const Icon(Icons.add_comment_outlined)),
          const SizedBox(width: AppSpace.xs),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.md,
                vertical: AppSpace.sm,
              ),
              children: [
                _AssistantBubble(
                  child: Text(
                    '我已经读过你置顶的两条笔记：《写作偏好》《常用术语》。'
                    '想写什么？给我一个主题，或者一个可以参考的网址。',
                    style: TextStyle(fontSize: 15, height: 1.7, color: c.textPrimary),
                  ),
                ),
                const SizedBox(height: AppSpace.md),
                _UserBubble(
                  child: Text(
                    '写一篇关于 Hugo Deploy Hook 的短文，800 字左右',
                    style: TextStyle(fontSize: 15, height: 1.7, color: c.textPrimary),
                  ),
                ),
                const SizedBox(height: AppSpace.md),
                const _ToolStrip(
                  icon: Icons.description_outlined,
                  label: '读了「Hugo + Vercel 的极简部署流程」',
                ),
                const _ToolStrip(
                  icon: Icons.lightbulb_outline,
                  label: '搜索笔记「Deploy」',
                ),
                const SizedBox(height: AppSpace.xs),
                _AssistantBubble(
                  child: Text(
                    '好，我按你置顶笔记里的偏好来写：短段落、中英加空格。'
                    '下面是草稿，确认后我会写入 content/posts/。',
                    style: TextStyle(fontSize: 15, height: 1.7, color: c.textPrimary),
                  ),
                ),
              ],
            ),
          ),
          _ContextHint(),
          _InputBar(controller: _input),
        ],
      ),
    );
  }
}

/// 输入框上方的上下文提示：告诉用户 AI 现在看到了什么
class _ContextHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.md,
        vertical: AppSpace.xs,
      ),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.divider, width: 1)),
      ),
      child: Row(
        children: [
          Icon(Icons.push_pin_outlined, size: 13, color: c.textTertiary),
          const SizedBox(width: AppSpace.xxs),
          Expanded(
            child: Text(
              '已注入 2 条置顶笔记',
              style: TextStyle(fontSize: 11, height: 1.4, color: c.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.sm,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 5,
                style: TextStyle(fontSize: 15, height: 1.5, color: c.textPrimary),
                decoration: const InputDecoration(hintText: '说点什么…'),
              ),
            ),
            const SizedBox(width: AppSpace.xs),
            SizedBox(
              width: 44,
              height: 44,
              child: Material(
                color: c.accent,
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  onTap: () {},
                  child: Icon(
                    Icons.arrow_upward,
                    size: 20,
                    color: Theme.of(context).brightness == Brightness.light
                        ? Colors.white
                        : c.background,
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

class _AssistantBubble extends StatelessWidget {
  const _AssistantBubble({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          margin: const EdgeInsets.only(top: 2),
          decoration: BoxDecoration(
            color: c.accentSoft,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Icon(Icons.auto_awesome, size: 14, color: c.accent),
        ),
        const SizedBox(width: AppSpace.xs),
        Flexible(
          child: Container(
            padding: const EdgeInsets.all(AppSpace.sm),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: child,
          ),
        ),
      ],
    );
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Flexible(
          child: Container(
            padding: const EdgeInsets.all(AppSpace.sm),
            decoration: BoxDecoration(
              color: c.accentSoft,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: child,
          ),
        ),
      ],
    );
  }
}

/// 工具调用：折叠成一行，点击展开
class _ToolStrip extends StatefulWidget {
  const _ToolStrip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  State<_ToolStrip> createState() => _ToolStripState();
}

class _ToolStripState extends State<_ToolStrip> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Padding(
      padding: const EdgeInsets.only(left: 32, bottom: AppSpace.xxs),
      child: InkWell(
        onTap: () => setState(() => _open = !_open),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(widget.icon, size: 13, color: c.textTertiary),
                  const SizedBox(width: AppSpace.xxs),
                  Flexible(
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: c.textTertiary,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpace.xxs),
                  AnimatedRotation(
                    turns: _open ? 0.25 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.chevron_right, size: 14, color: c.textTertiary),
                  ),
                ],
              ),
            ),
            if (_open)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: AppSpace.xxs),
                padding: const EdgeInsets.all(AppSpace.xs),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Text(
                  '（这里显示工具返回的摘要）',
                  style: TextStyle(fontSize: 12, height: 1.5, color: c.textSecondary),
                ),
              ),
          ],
        ),
      ),
    );
  }
}