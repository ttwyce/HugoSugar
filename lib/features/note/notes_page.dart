import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../core/note/note.dart';
import '../../core/note/note_controller.dart';
import '../../shared/widgets.dart';
import 'note_editor_page.dart';

/// 笔记页：碎片化灵感。
///
/// 三个视图（全部 / 置顶 / 回收站）+ 搜索 + 分类过滤。
/// 置顶笔记会进 AI 的 System Prompt，所以区块标题里明确写了这一点。
class NotesPage extends StatefulWidget {
  const NotesPage({super.key, required this.controller});

  final NoteController controller;

  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> {
  final _searchCtrl = TextEditingController();
  bool _searchOpen = false;

  NoteController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.addListener(_onChanged);
  }

  @override
  void dispose() {
    c.removeListener(_onChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final notes = c.visibleNotes;
    final pinned = c.pinnedNotes;
    final others = c.unpinnedNotes;

    return Scaffold(
      appBar: AppBar(
        title: const Text('笔记'),
        actions: [
          IconButton(
            onPressed: () {
              setState(() => _searchOpen = !_searchOpen);
              if (!_searchOpen) {
                _searchCtrl.clear();
                c.setQuery('');
              }
            },
            icon: Icon(_searchOpen ? Icons.search_off : Icons.search),
            tooltip: '搜索',
          ),
          IconButton(
            onPressed: _showCategorySheet,
            icon: const Icon(Icons.folder_outlined),
            tooltip: '分类',
          ),
          const SizedBox(width: AppSpace.xs),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _newNote,
        tooltip: '新建笔记',
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          if (_searchOpen)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.md,
                AppSpace.xs,
                AppSpace.md,
                AppSpace.xs,
              ),
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                onChanged: c.setQuery,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: '搜索标题和正文',
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 18),
                  suffixIcon: c.query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          onPressed: () {
                            _searchCtrl.clear();
                            c.setQuery('');
                          },
                        ),
                ),
              ),
            ),
          _ViewTabs(controller: c),
          if (c.categoryId != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.md,
                0,
                AppSpace.md,
                AppSpace.xs,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.filter_alt,
                    size: 14,
                    color: context.appColors.accent,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '分类：${c.store.categoryById(c.categoryId)?.name ?? "未知"}',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.appColors.accent,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => c.setCategory(null),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      minimumSize: const Size(0, 0),
                      padding: EdgeInsets.zero,
                    ),
                    child: const Text('清除', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
          Expanded(
            child: notes.isEmpty
                ? _EmptyView(view: c.view, searching: c.isSearching)
                : ListView(
                    padding: const EdgeInsets.only(bottom: 96),
                    children: [
                      if (pinned.isNotEmpty) ...[
                        SectionHeader(
                          '置顶 · ${pinned.length}  ·  会注入 AI 上下文',
                        ),
                        for (final n in pinned)
                          _NoteCard(
                            note: n,
                            pinned: true,
                            onTap: () => _open(n),
                            onLongPress: () => _showActions(n),
                          ),
                      ],
                      if (others.isNotEmpty) ...[
                        SectionHeader('全部 · ${others.length}'),
                        for (final n in others)
                          _NoteCard(
                            note: n,
                            pinned: false,
                            onTap: () => _open(n),
                            onLongPress: () => _showActions(n),
                          ),
                      ],
                      if (c.view == NoteView.trashed)
                        Padding(
                          padding: const EdgeInsets.all(AppSpace.md),
                          child: OutlinedButton.icon(
                            onPressed: _purgeAll,
                            icon: const Icon(Icons.delete_forever, size: 18),
                            label: const Text('清空回收站'),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _newNote() async {
    final created = await c.createNote();
    if (!mounted) return;

    // 先记下 id，返回后判断是否仍是空笔记
    await _open(created, isNew: true);
    if (!mounted) return;

    // 新建后一个字没写就退出 → 删掉，不留垃圾
    final after = c.store.byId(created.id);
    if (after != null &&
        after.title.trim().isEmpty &&
        after.content.trim().isEmpty &&
        !after.isDeleted) {
      await c.purgeNote(created.id);
    }
  }

  Future<void> _open(Note note, {bool isNew = false}) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => NoteEditorPage(
          controller: c,
          noteId: note.id,
          isNew: isNew,
        ),
      ),
    );
    if (changed == true && mounted) setState(() {});
  }

  Future<void> _purgeAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空回收站'),
        content: Text('将永久删除 ${c.trashCount} 条笔记，无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('永久删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final n = await c.purgeAll();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已删除 $n 条')),
    );
  }

  /// 长按操作菜单
  void _showActions(Note note) {
    final inTrash = note.isDeleted;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('编辑'),
              enabled: !inTrash,
              onTap: () {
                Navigator.pop(ctx);
                _open(note);
              },
            ),
            if (!inTrash)
              ListTile(
                leading: Icon(
                  note.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                ),
                title: Text(note.pinned ? '取消置顶' : '置顶'),
                subtitle: note.pinned
                    ? null
                    : const Text('置顶后会注入 AI 的 System Prompt'),
                onTap: () {
                  Navigator.pop(ctx);
                  c.togglePin(note.id);
                },
              ),
            if (!inTrash)
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: const Text('移动到分类'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickCategory(note);
                },
              ),
            if (inTrash) ...[
              ListTile(
                leading: const Icon(Icons.restore),
                title: const Text('恢复'),
                onTap: () {
                  Navigator.pop(ctx);
                  c.restoreNote(note.id);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_forever),
                title: const Text('永久删除'),
                onTap: () {
                  Navigator.pop(ctx);
                  c.purgeNote(note.id);
                },
              ),
            ] else
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('移到回收站'),
                onTap: () {
                  Navigator.pop(ctx);
                  c.trashNote(note.id);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _pickCategory(Note note) {
    final cats = c.store.categories;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('移动到分类')),
            ListTile(
              leading: const Icon(Icons.folder_off_outlined),
              title: const Text('不分类'),
              trailing: note.categoryId == null
                  ? const Icon(Icons.check, size: 18)
                  : null,
              onTap: () async {
                Navigator.pop(ctx);
                await c.saveNote(note.copyWith(clearCategory: true));
              },
            ),
            for (final cat in cats)
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(cat.name),
                trailing: note.categoryId == cat.id
                    ? const Icon(Icons.check, size: 18)
                    : null,
                onTap: () async {
                  Navigator.pop(ctx);
                  await c.saveNote(note.copyWith(categoryId: cat.id));
                },
              ),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('新建分类'),
              onTap: () {
                Navigator.pop(ctx);
                _createCategory();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showCategorySheet() {
    final cats = c.store.categories;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('分类'),
                trailing: IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _createCategory();
                  },
                  tooltip: '新建分类',
                ),
              ),
              ListTile(
                leading: const Icon(Icons.all_inbox),
                title: const Text('全部'),
                trailing: c.categoryId == null
                    ? Icon(
                        Icons.check,
                        size: 18,
                        color: context.appColors.accent,
                      )
                    : null,
                onTap: () {
                  Navigator.pop(ctx);
                  c.setCategory(null);
                },
              ),
              for (final cat in cats)
                ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(cat.name),
                  subtitle: Text('${c.store.countInCategory(cat.id)} 条'),
                  trailing: c.categoryId == cat.id
                      ? Icon(
                          Icons.check,
                          size: 18,
                          color: context.appColors.accent,
                        )
                      : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    c.setCategory(cat.id);
                  },
                  onLongPress: () {
                    Navigator.pop(ctx);
                    _manageCategory(cat);
                  },
                ),
              if (cats.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(AppSpace.md),
                  child: Text(
                    '还没有分类。分类只是给笔记分组，和文章的 categories 无关。\n'
                    '长按分类可以重命名或删除。',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.6,
                      color: context.appColors.textTertiary,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _createCategory() async {
    final name = await _promptText('新建分类', '分类名称');
    if (name == null || name.trim().isEmpty) return;
    await c.createCategory(name.trim());
  }

  void _manageCategory(NoteCategory cat) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(cat.name)),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('重命名'),
              onTap: () async {
                Navigator.pop(ctx);
                final name =
                    await _promptText('重命名分类', '分类名称', initial: cat.name);
                if (name == null || name.trim().isEmpty) return;
                await c.renameCategory(cat.id, name.trim());
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('删除分类'),
              subtitle: const Text('笔记不会被删除，只是解除归属'),
              onTap: () {
                Navigator.pop(ctx);
                c.deleteCategory(cat.id);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _promptText(
    String title,
    String hint, {
    String initial = '',
  }) {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}

// ── 视图切换 ─────────────────────────────────────────

class _ViewTabs extends StatelessWidget {
  const _ViewTabs({required this.controller});

  final NoteController controller;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final items = <(NoteView, String, int)>[
      (NoteView.active, '全部', controller.activeCount),
      (NoteView.pinned, '置顶', controller.pinnedCount),
      (NoteView.trashed, '回收站', controller.trashCount),
    ];

    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpace.xs),
        itemBuilder: (_, i) {
          final (view, label, count) = items[i];
          final selected = controller.view == view;
          return Center(
            child: InkWell(
              onTap: () => controller.setView(view),
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.sm,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? c.accent.withValues(alpha: 0.12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  '$label $count',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected ? c.accent : c.textSecondary,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── 笔记卡片 ─────────────────────────────────────────

class _NoteCard extends StatelessWidget {
  const _NoteCard({
    required this.note,
    required this.pinned,
    required this.onTap,
    required this.onLongPress,
  });

  final Note note;
  final bool pinned;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.md,
        AppSpace.xxs,
        AppSpace.md,
        AppSpace.xs,
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          padding: const EdgeInsets.all(AppSpace.sm),
          decoration: BoxDecoration(
            color: pinned ? c.surfaceHigh : c.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      note.title.trim().isEmpty ? '无标题' : note.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                        color: note.title.trim().isEmpty
                            ? c.textTertiary
                            : c.textPrimary,
                      ),
                    ),
                  ),
                  if (note.isConverted) ...[
                    const SizedBox(width: 4),
                    Icon(
                      Icons.article_outlined,
                      size: 14,
                      color: c.accent.withValues(alpha: 0.7),
                    ),
                  ],
                  if (pinned) ...[
                    const SizedBox(width: 6),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: c.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ],
              ),
              if (note.preview.isNotEmpty) ...[
                const SizedBox(height: AppSpace.xxs),
                Text(
                  note.preview,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.55,
                    color: c.textSecondary,
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(
                    note.isDeleted ? '已删除' : note.updatedLabel,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.4,
                      color: c.textTertiary,
                    ),
                  ),
                  if (note.charCount > 0) ...[
                    const SizedBox(width: 6),
                    Text(
                      '· ${note.charCount} 字',
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.4,
                        color: c.textTertiary,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 空状态 ───────────────────────────────────────────

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.view, required this.searching});

  final NoteView view;
  final bool searching;

  @override
  Widget build(BuildContext context) {
    if (searching) {
      return const EmptyState(
        icon: Icons.search_off,
        text: '没有匹配的笔记',
      );
    }
    return switch (view) {
      NoteView.trashed => const EmptyState(
          icon: Icons.delete_outline,
          text: '回收站是空的',
        ),
      NoteView.pinned => const EmptyState(
          icon: Icons.push_pin_outlined,
          text: '还没有置顶笔记\n置顶的笔记会注入 AI 上下文',
        ),
      NoteView.active => const EmptyState(
          icon: Icons.lightbulb_outline,
          text: '还没有笔记\n随手记下灵感，之后可以一键转成文章',
        ),
    };
  }
}