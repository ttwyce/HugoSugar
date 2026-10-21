import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../core/ai/ai_controller.dart';
import '../../core/ai/skill_store.dart';
import '../../core/settings/settings_controller.dart';

/// 工具清单：名字 + 一句话作用。
///
/// 作用说明不是从 schema 里自动抽的——schema 的描述是写给模型看的
/// （强调「什么时候该调」），而用户想知道的是「这个东西会动我的文件吗」。
/// 两种话术目的不同，混用会让人不敢关也看不懂。
const List<({String name, String label, String desc, bool risky})>
kToolCatalog = [
  (name: 'list_notes', label: '列出想法', desc: '读取你的想法列表，可筛选', risky: false),
  (name: 'read_note', label: '读取想法', desc: '读某一条想法的完整内容', risky: false),
  (name: 'search_notes', label: '搜索想法', desc: '在所有想法里全文搜索', risky: false),
  (name: 'read_post', label: '读取文章', desc: '读站点里已有文章的全文', risky: false),
  (name: 'write_post', label: '写入文章', desc: '往站点写文件（需你确认 Diff）', risky: true),
  (name: 'fetch_url', label: '抓取网页', desc: '联网读取指定网址的正文', risky: true),
  (name: 'save_memory', label: '记录记忆', desc: '把你告诉它的事记进记忆库', risky: false),
  (name: 'update_memory', label: '改记忆', desc: '改写或合并已记住的内容', risky: false),
  (name: 'delete_memory', label: '删记忆', desc: '删除一条记忆', risky: false),
];

/// 工具开关面板。
///
/// 关掉的工具会从模型的 schema 里移除，不是「保留但拒绝」——
/// 保留会让模型先花一轮 token 去调用，然后拿到一个拒绝，
/// 它多半会以为是自己参数写错而反复重试。
class ToolTogglesSheet extends StatefulWidget {
  const ToolTogglesSheet({
    super.key,
    required this.settingsController,
    required this.aiController,
  });

  final SettingsController settingsController;
  final AiController aiController;

  @override
  State<ToolTogglesSheet> createState() => _ToolTogglesSheetState();
}

class _ToolTogglesSheetState extends State<ToolTogglesSheet> {
  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final off = widget.settingsController.aiDisabledTools.toSet();

    return SafeArea(
      child: SizedBox(
        width: MediaQuery.sizeOf(context).width,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.8,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '工具开关',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '关掉后模型完全看不到这个工具，不会调用也不会浪费一轮请求',
                  style: TextStyle(fontSize: 11, color: c.textTertiary),
                ),
                const SizedBox(height: 10),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final t in kToolCatalog)
                        SwitchListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          value: !off.contains(t.name),
                          onChanged: (v) async {
                            await widget.settingsController.setToolEnabled(
                              t.name,
                              v,
                            );
                            if (mounted) setState(() {});
                          },
                          title: Row(
                            children: [
                              Text(
                                t.label,
                                style: const TextStyle(fontSize: 13),
                              ),
                              if (t.risky) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: c.warning.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '会动数据',
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: c.warning,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          subtitle: Text(
                            t.desc,
                            style: TextStyle(
                              fontSize: 11,
                              color: c.textTertiary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Skill 管理页：启用 / 新建 / 编辑 / 删除。
class SkillsPage extends StatefulWidget {
  const SkillsPage({super.key, required this.controller});

  final AiController controller;

  @override
  State<SkillsPage> createState() => _SkillsPageState();
}

class _SkillsPageState extends State<SkillsPage> {
  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final store = widget.controller.skillStore;
    final all = store?.all ?? const [];
    final active = widget.controller.skillIds.toSet();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Skill / 工作模式'),
        actions: [
          IconButton(
            tooltip: '新建',
            icon: const Icon(Icons.add),
            onPressed: () => _edit(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              '启用后会追加到 System Prompt，规定这一轮「怎么做」。'
              '可以同时开多个，也能随时关掉。',
              style: TextStyle(
                fontSize: 11,
                color: c.textTertiary,
                height: 1.5,
              ),
            ),
          ),
          for (final s in all)
            ListTile(
              title: Row(
                children: [
                  Flexible(
                    child: Text(
                      s.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                  if (s.builtin) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '内置',
                        style: TextStyle(fontSize: 9, color: c.textTertiary),
                      ),
                    ),
                  ],
                ],
              ),
              subtitle: Text(
                s.description.isEmpty
                    ? s.prompt.split('\n').first
                    : s.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: c.textTertiary),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!s.builtin)
                    IconButton(
                      tooltip: '编辑',
                      icon: Icon(
                        Icons.edit_outlined,
                        size: 18,
                        color: c.textTertiary,
                      ),
                      onPressed: () => _edit(skill: s),
                    ),
                  Switch(
                    value: active.contains(s.id),
                    onChanged: (v) {
                      final next = List<String>.from(active);
                      if (v) {
                        next.add(s.id);
                      } else {
                        next.remove(s.id);
                      }
                      widget.controller.skillIds = next;
                      setState(() {});
                    },
                  ),
                ],
              ),
              onLongPress: s.builtin
                  ? null
                  : () => _confirmDelete(s.id, s.name),
            ),
        ],
      ),
    );
  }

  Future<void> _edit({Skill? skill}) async {
    final c = context.appColors;
    final nameCtrl = TextEditingController(text: skill?.name ?? '');
    final descCtrl = TextEditingController(text: skill?.description ?? '');
    final promptCtrl = TextEditingController(text: skill?.prompt ?? '');

    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text(skill == null ? '新建 Skill' : '编辑 Skill'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '名称',
                  hintText: '例如：改成口语化',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: descCtrl,
                decoration: const InputDecoration(
                  labelText: '一句话说明（可选）',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: promptCtrl,
                maxLines: 8,
                minLines: 4,
                decoration: InputDecoration(
                  labelText: '指令内容',
                  hintText:
                      '写给模型看的要求，越具体越好。\n'
                      '建议同时写清「不要做什么」。',
                  isDense: true,
                  hintStyle: TextStyle(fontSize: 11, color: c.textTertiary),
                ),
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(true),
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (ok != true) return;
    if (nameCtrl.text.trim().isEmpty || promptCtrl.text.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('名称和指令内容不能为空')));
      return;
    }

    final store = widget.controller.skillStore;
    if (store == null) return;
    if (skill == null) {
      await store.add(
        name: nameCtrl.text,
        prompt: promptCtrl.text,
        description: descCtrl.text,
      );
    } else {
      await store.update(
        skill.id,
        name: nameCtrl.text,
        prompt: promptCtrl.text,
        description: descCtrl.text,
      );
    }
    if (mounted) setState(() {});
  }

  Future<void> _confirmDelete(String id, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('删除这个 Skill？'),
        content: Text('「$name」将被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.controller.skillStore?.remove(id);
    // 删掉后如果还在启用列表里，一并清掉，否则 Prompt 会引用一个不存在的 id
    widget.controller.skillIds = widget.controller.skillIds
        .where((e) => e != id)
        .toList();
    if (mounted) setState(() {});
  }
}
