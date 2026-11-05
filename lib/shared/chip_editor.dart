import 'package:flutter/material.dart';

import '../app/theme/app_colors.dart';

/// 按输入内容收窄候选列表。
///
/// 规则：
/// - [typed] 为空 → 原样返回（调用方给的顺序就是使用频率序）
/// - 已选中的项从候选中剔除，避免同一个词出现两遍
/// - **前缀匹配优先于包含匹配**：输入 `flu` 时用户多半想要 `flutter`，
///   而不是 `kotlin-fluent`
///
/// 抽成顶层函数是为了能直接单测——这套排序规则是 Hugo taxonomy 的
/// 使用体验关键：拼错一个字就会多出一个分类页，而内置候选是唯一
/// 能让用户对准既有拼写的手段。
List<String> filterSuggestions({
  required List<String> all,
  required List<String> selected,
  required String typed,
}) {
  final pool = all.where((v) => !selected.contains(v)).toList();
  // 归一化放在函数内部：调用方（ChipEditor）其实已经转小写，
  // 但这是 public 函数，漏转一次就会让「输入大写搜不到东西」
  // 这种 bug 极难发现。
  final needle = typed.trim().toLowerCase();
  if (needle.isEmpty) return pool;

  final prefix = <String>[];
  final contains = <String>[];
  for (final v in pool) {
    final lv = v.toLowerCase();
    if (lv.startsWith(needle)) {
      prefix.add(v);
    } else if (lv.contains(needle)) {
      contains.add(v);
    }
  }
  return [...prefix, ...contains];
}

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

        // 候选随输入实时收窄。
        //
        // 为什么必须过滤：`allValues` 是站点里出现过的全部标签，按使用
        // 频次排序后只取前 8 个展示。Hugo 的 taxonomy 对拼写极敏感——
        // 打错一个字就多出一个分类页，而用户根本看不到「自己以前用的是
        // 哪个词」，只能凭记忆重打。有了过滤，输两个字就能对准。
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) {
            final typed = value.text.trim().toLowerCase();
            final matched = filterSuggestions(
              all: allValues,
              selected: values,
              typed: typed,
            );
            final suggestions = matched.take(maxSuggestions).toList();
            if (suggestions.isEmpty && typed.isEmpty) {
              return const SizedBox.shrink();
            }

            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    typed.isEmpty
                        ? '点选已有'
                        : suggestions.isEmpty
                            ? '没有匹配的标签，按 + 直接新增'
                            : '匹配到 ${matched.length} 个',
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.4,
                      color: c.textTertiary,
                    ),
                  ),
                  if (suggestions.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final v in suggestions)
                          GestureDetector(
                            // 点选后清空输入框：否则过滤词还留在里面，
                            // 列表继续被收窄，看起来像「没点成功」。
                            onTap: () {
                              controller.clear();
                              onChanged([...values, v]);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                borderRadius:
                                    BorderRadius.circular(AppRadius.sm),
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
              ),
            );
          },
        ),
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