import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../core/ai/ai_controller.dart';
import '../../core/ai/memory_store.dart';

/// 记忆库管理页。
///
/// ## 为什么这个页面必须存在
///
/// 记忆是模型**自己**写的。如果用户看不到里面有什么，
/// 那么「AI 越来越懂我」和「AI 越来越偏执」在体验上是同一件事 ——
/// 差别只在于能不能查、能不能改。
///
/// 所以这个页面的定位不是「高级设置」，而是**审计入口**：
/// 每条记忆都得能读、能改、能删，而且一眼能看出它是什么时候写的。
class MemoryPage extends StatefulWidget {
  const MemoryPage({super.key, required this.controller});

  final AiController controller;

  @override
  State<MemoryPage> createState() => _MemoryPageState();
}

class _MemoryPageState extends State<MemoryPage> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final store = widget.controller.memoryStore;
    final all = store?.all ?? const <Memory>[];

    final list = _filter.trim().isEmpty
        ? all
        : all
            .where((m) =>
                m.content.contains(_filter) ||
                MemoryCategory.label(m.category).contains(_filter))
            .toList();

    // 按分类分组展示：模型读的是分组后的 Prompt，
    // 用户在这里看到的也应该是同一形状。
    final grouped = <String, List<Memory>>{};
    for (final m in list) {
      grouped.putIfAbsent(m.category, () => []).add(m);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('记忆库（${all.length}）'),
        actions: [
          if (all.isNotEmpty)
            IconButton(
              tooltip: '清空',
              icon: const Icon(Icons.delete_sweep_outlined, size: 20),
              onPressed: _confirmClearAll,
            ),
        ],
      ),
      body: all.isEmpty
          ? _empty(c)
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: '搜索记忆…',
                      isDense: true,
                      prefixIcon: Icon(Icons.search, size: 18),
                    ),
                    style: const TextStyle(fontSize: 14),
                    onChanged: (v) => setState(() => _filter = v),
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    children: [
                      for (final cat in MemoryCategory.all)
                        if (grouped[cat]?.isNotEmpty ?? false) ...[
                          Padding(
                            padding: const EdgeInsets.only(top: 12, bottom: 4),
                            child: Text(
                              MemoryCategory.label(cat),
                              style: TextStyle(
                                fontSize: 12,
                                color: c.textTertiary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          for (final m in grouped[cat]!) _tile(m),
                        ],
                      const SizedBox(height: 16),
                      Text(
                        '这些内容会加进每次对话的 System Prompt。\n'
                        '记忆是「关于你的事实」，不是给 AI 的指令 —— '
                        '发现写成命令的（如「你要…」），建议删掉。',
                        style: TextStyle(fontSize: 11, color: c.textTertiary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _empty(AppColors c) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.psychology_outlined, size: 40, color: c.textTertiary),
            const SizedBox(height: 12),
            Text(
              '还没有记忆',
              style: TextStyle(fontSize: 14, color: c.textSecondary),
            ),
            const SizedBox(height: 8),
            Text(
              '和 AI 聊几次，它会自己记下你的写作风格、\n'
              '性格偏好和工作习惯。也可以在对话里直接说\n'
              '「记住我喜欢…」。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: c.textTertiary, height: 1.6),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(Memory m) {
    final c = context.appColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    m.content,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: c.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _fmtDate(m.updatedAt),
                    style: TextStyle(fontSize: 10, color: c.textTertiary),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 16),
              tooltip: '编辑',
              onPressed: () => _edit(m),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 16),
              tooltip: '删除',
              onPressed: () => _delete(m),
            ),
          ],
        ),
      ),
    );
  }

  static String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _edit(Memory m) async {
    final ctrl = TextEditingController(text: m.content);
    var category = m.category;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('编辑记忆'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                minLines: 2,
                maxLines: 5,
                autofocus: true,
                decoration: const InputDecoration(hintText: '关于用户的事实'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: category,
                decoration: const InputDecoration(labelText: '分类'),
                items: [
                  for (final cat in MemoryCategory.all)
                    DropdownMenuItem(
                      value: cat,
                      child: Text(MemoryCategory.label(cat)),
                    ),
                ],
                onChanged: (v) => setSt(() => category = v ?? category),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );

    if (ok != true) return;
    final text = ctrl.text.trim();
    if (text.isEmpty) return;
    await widget.controller.memoryStore?.update(
      m.id,
      content: text,
      category: category,
    );
    if (mounted) setState(() {});
  }

  Future<void> _delete(Memory m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这条记忆？'),
        content: Text(m.content, style: const TextStyle(fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.controller.memoryStore?.remove(m.id);
    if (mounted) setState(() {});
  }

  Future<void> _confirmClearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空全部记忆？'),
        content: const Text('AI 将不再记得你的偏好。此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.controller.memoryStore?.removeAll();
    if (mounted) setState(() {});
  }
}