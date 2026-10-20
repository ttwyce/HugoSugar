import 'package:flutter/material.dart';

import '../app/theme/app_colors.dart';

/// 分类 / 标签编辑区。
///
/// 为什么抽到 shared：新建文章、编辑器信息面板原先各写了一套，
/// 结果「已选」和「可添加」在新建页长得一模一样 ——
/// `ActionChip` 带 `onPressed`，Material 会把它当「可选中的」，
/// 配上我们的 chipTheme 后与 `InputChip` 撞色，用户分不清哪个已经加了。
///
/// 现在的视觉规则（两处统一）：
/// - **已选**：实心 chip（accentSoft 底 + accent 字）+ 叉号删除
/// - **可添加**：描边小方块 + `+ 名称` 前缀，暗示「点了会新增」
class ChipEditor extends StatelessWidget {
  const ChipEditor({
    super.key,
    required this.values,
    required this.allValues,
    required this.hint,
    required this.controller,
    required this.onChanged,
    this.maxSuggestions = 8,
  });

  /// 当前已选中的项
  final List<String> values;

  /// 站点里出现过的全部候选值
  final List<String> allValues;

  final String hint;
  final TextEditingController controller;
  final ValueChanged<List<String>> onChanged;
  final int maxSuggestions;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;

    // 已选的从候选里剔掉，避免同一个词出现两遍
    final suggestions =
        allValues.where((v) => !values.contains(v)).take(maxSuggestions).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (values.isNotEmpty)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final v in values)
                InputChip(
                  label: Text(v, style: const TextStyle(fontSize: 12)),
                  onDeleted: () =>
                      onChanged(values.where((e) => e != v).toList()),
                  deleteIcon: const Icon(Icons.close, size: 14),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
            ],
          ),
        if (values.isNotEmpty) const SizedBox(height: 6),

        TextField(
          controller: controller,
          style: const TextStyle(fontSize: 13),
          textInputAction: TextInputAction.done,
          onSubmitted: (v) => _commitInput(v),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(fontSize: 13, color: c.textTertiary),
            isDense: true,
            filled: true,
            fillColor: c.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              borderSide: BorderSide.none,
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            suffixIcon: IconButton(
              icon: const Icon(Icons.add, size: 18),
              onPressed: () => _commitInput(controller.text),
            ),
          ),
        ),

        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            '点选已有',
            style: TextStyle(
              fontSize: 11,
              height: 1.4,
              color: c.textTertiary,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final v in suggestions)
                GestureDetector(
                  onTap: () => onChanged([...values, v]),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(color: c.divider),
                    ),
                    child: Text(
                      '+ $v',
                      style: TextStyle(
                        fontSize: 11,
                        color: c.textSecondary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  /// 提交输入框内容。支持逗号（中英文）分隔一次加多个。
  void _commitInput(String raw) {
    final parts = raw
        .split(RegExp(r'[,，]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      controller.clear();
      return;
    }

    final next = [...values];
    for (final p in parts) {
      if (!next.contains(p)) next.add(p);
    }
    if (next.length != values.length) onChanged(next);
    controller.clear();
  }
}