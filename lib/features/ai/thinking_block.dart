import 'package:flutter/material.dart';
import 'package:hugosugar/app/i18n/l10n_scope.dart';

import '../../app/theme/app_colors.dart';

/// 模型的思考过程（DeepSeek-R1 等推理模型的 `reasoning_content`）。
///
/// ## 为什么默认折叠
///
/// 思考过程往往很长（R1 动辄几千字），而且它是**中间产物**：
/// 用户真正要看的是最终答案。全部铺开会把回答挤到屏幕外，
/// 反而更难读。但也不能不显示 —— 模型写偏了的时候，
/// 思考过程是唯一能看出「它在想什么」的地方。
///
/// 折中是：默认收起成一行，点开看全文。
///
/// ## 为什么流式时要自动展开
///
/// 生成中，正文还没出来，屏幕上如果一片空白，用户会怀疑是不是卡住了。
/// 这时思考过程正好充当「正在工作」的证据。等正文开始输出再自动收起。
class ThinkingBlock extends StatefulWidget {
  const ThinkingBlock({super.key, required this.text, this.streaming = false});

  /// 思考内容。空串时不渲染任何东西。
  final String text;

  /// 是否仍在生成中
  final bool streaming;

  @override
  State<ThinkingBlock> createState() => _ThinkingBlockState();
}

class _ThinkingBlockState extends State<ThinkingBlock> {
  bool? _expandedOverride;

  /// 用户点过就以用户的为准；否则流式中展开，结束后收起
  bool get _expanded => _expandedOverride ?? widget.streaming;

  @override
  void didUpdateWidget(ThinkingBlock old) {
    super.didUpdateWidget(old);
    // 从「生成中」变成「已结束」时，如果用户没手动点过，
    // 就跟着收起来 —— 把决定权还给默认行为
    if (old.streaming && !widget.streaming) {
      _expandedOverride = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.text.trim().isEmpty) return const SizedBox.shrink();

    final c = context.appColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: Container(
        decoration: BoxDecoration(
          color: c.surface.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: c.divider, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () => setState(() => _expandedOverride = !_expanded),
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.sm,
                  vertical: 6,
                ),
                child: Row(
                  children: [
                    Icon(
                      widget.streaming
                          ? Icons.psychology
                          : Icons.psychology_outlined,
                      size: 13,
                      color: widget.streaming ? c.accent : c.textTertiary,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        widget.streaming ? T('正在思考…') : T('思考过程'),
                        style: TextStyle(
                          fontSize: 11,
                          color: widget.streaming ? c.accent : c.textTertiary,
                        ),
                      ),
                    ),
                    Text(
                      TP('{} 字', [widget.text.characters.length]),
                      style: TextStyle(fontSize: 10, color: c.textTertiary),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      size: 15,
                      color: c.textTertiary,
                    ),
                  ],
                ),
              ),
            ),
            if (_expanded)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.sm,
                  0,
                  AppSpace.sm,
                  AppSpace.sm,
                ),
                child: Text(
                  widget.text,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.6,
                    color: c.textSecondary,
                    // 等宽字更接近「模型内部独白」的观感，
                    // 也和正文形成视觉区分
                    fontFamily: 'monospace',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
