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

    return Scaffold(
      appBar: AppBar(
        title: const Text('想法'),
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
        tooltip: '新建想法',
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
                  hintText: '搜索想法标题和正文',
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
                : _MasonryGrid(
                    notes: notes,
                    onTap: _open,
                    onLongPress: _showActions,
                    trailing: c.view == NoteView.trashed
                        ? Padding(
                            padding: const EdgeInsets.all(AppSpace.md),
                            child: OutlinedButton.icon(
                              onPressed: _purgeAll,
                              icon: const Icon(Icons.delete_forever, size: 18),
                              label: const Text('清空回收站'),
                            ),
                          )
                        : null,
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
                title: Text(note.pinned ? '取消精选' : '精选'),
                subtitle: note.pinned
                    ? null
                    : const Text('精选的想法会优先提供给 AI'),
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
                    '还没有分类。分类只是给想法分组，和文章的 categories 无关。\n'
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
              subtitle: const Text('想法不会被删除，只是解除归属'),
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

// ── 两列瀑布流 ───────────────────────────────────────

/// 两列瀑布流布局。
///
/// 为什么不用 `flutter_staggered_grid_view`：
/// 本项目对新增依赖很谨慎（AGENTS.md 明确要求先确认 Android 可用性），
/// 而瀑布流的核心只是「按列高最短优先分配」，不到 30 行。
///
/// 算法：维护两列的估算高度，每张卡片分配给当前较矮的一列。
/// 卡片高度由**内容行数**估算（标题 1 行 + 预览 N 行 + 底部信息 1 行），
/// 而不是等渲染后再测量 —— 后者需要 CustomMultiChildLayout，
/// 在长列表里会有明显的抖动。
class _MasonryGrid extends StatelessWidget {
  const _MasonryGrid({
    required this.notes,
    required this.onTap,
    required this.onLongPress,
    this.trailing,
  });

  final List<Note> notes;
  final void Function(Note) onTap;
  final void Function(Note) onLongPress;

  /// 网格之后的附加内容（回收站的「清空」按钮）
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    // 先按估算高度分列，再整体放进 ListView 一次构建。
    // 分列必须在 build 里做（依赖 notes 顺序），但计算量是 O(n)，很轻。
    final left = <Note>[];
    final right = <Note>[];
    var hLeft = 0.0;
    var hRight = 0.0;

    for (final n in notes) {
      final h = _estimateHeight(n);
      if (hLeft <= hRight) {
        left.add(n);
        hLeft += h;
      } else {
        right.add(n);
        hRight += h;
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.sm,
        0,
        AppSpace.sm,
        96,
      ),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _column(left, context)),
            const SizedBox(width: AppSpace.sm),
            Expanded(child: _column(right, context)),
          ],
        ),
        ?trailing,
      ],
    );
  }

  Widget _column(List<Note> list, BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final n in list)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.sm),
            child: _NoteCard(
              note: n,
              pinned: n.pinned,
              onTap: () => onTap(n),
              onLongPress: () => onLongPress(n),
            ),
          ),
      ],
    );
  }

  /// 估算卡片高度，只用于分列决策。
  ///
  /// 数值不需要精确，只要「长卡片 > 短卡片」的相对关系正确，
  /// 两列就能保持大致齐平。
  static double _estimateHeight(Note n) {
    const titleH = 22.0;
    const previewLineH = 21.0;
    const metaH = 18.0;
    const paddingV = AppSpace.sm * 2;
    const gapV = AppSpace.xxs + 6;

    var h = titleH + metaH + paddingV + gapV;
    if (n.preview.isNotEmpty) {
      // preview 在卡片里最多 2 行，估算按实际截断后的行数
      final lines = (n.preview.length / 18).ceil().clamp(1, 2);
      h += lines * previewLineH;
    }
    return h;
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
        text: '没有匹配的想法',
      );
    }
    return switch (view) {
      NoteView.trashed => const EmptyState(
          icon: Icons.delete_outline,
          text: '回收站是空的',
        ),
      NoteView.pinned => const EmptyState(
          icon: Icons.push_pin_outlined,
          text: '还没有精选想法\n精选的想法会优先提供给 AI',
        ),
      NoteView.active => const EmptyState(
          icon: Icons.lightbulb_outline,
          text: '还没有想法\n随手记一句，之后可以一键转成文章',
        ),
    };
  }
}