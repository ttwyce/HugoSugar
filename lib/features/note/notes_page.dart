import 'package:flutter/material.dart';
import 'package:hugosugar/app/i18n/l10n_scope.dart';

import '../../app/theme/app_colors.dart';
import '../../core/ai/note_context.dart';
import '../../core/note/note.dart';
import '../../core/note/note_controller.dart';
import '../../core/settings/settings_controller.dart';
import '../../shared/widgets.dart';
import 'note_editor_page.dart';

/// 笔记页：碎片化灵感。
///
/// 三个视图（全部 / 置顶 / 回收站）+ 搜索 + 分类过滤。
/// 置顶笔记会进 AI 的 System Prompt，所以区块标题里明确写了这一点。
class NotesPage extends StatefulWidget {
  const NotesPage({
    super.key,
    required this.controller,
    this.settingsController,
  });

  final NoteController controller;

  /// 用于读写「AI 是否可以读取想法」。
  ///
  /// 可空：外壳之外的测试或预览可以只传笔记控制器。
  final SettingsController? settingsController;

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
        title: Text(context.tr(T('想法'))),
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
            tooltip: context.tr(T('搜索')),
          ),
          // 回收站移到右上角：它是「低频但有明确去处」的功能，
          // 和搜索并列比混在下面的视图 tab 里更符合导航直觉。
          // 放在 tab 里还占掉一个筛选位，让「置顶」显得和它同级。
          IconButton(
            onPressed: () => c.setView(
              c.view == NoteView.trashed ? NoteView.active : NoteView.trashed,
            ),
            icon: Icon(
              c.view == NoteView.trashed ? Icons.delete : Icons.delete_outline,
            ),
            tooltip: c.trashCount > 0
                ? TP('回收站（{}）', [c.trashCount])
                : T('回收站'),
          ),
          // AI 读取范围设置。入口放在这里而不是设置页：
          // 分组数据只有本页有，跨页传控制器只为渲染一个多选列表不值得。
          if (widget.settingsController != null)
            IconButton(
              onPressed: _showAiScopeSheet,
              icon: Icon(
                widget.settingsController!.aiReadNotes
                    ? Icons.psychology
                    : Icons.psychology_outlined,
              ),
              tooltip: context.tr(T('AI 读取范围')),
            ),
          const SizedBox(width: AppSpace.xs),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _newNote,
        tooltip: context.tr(T('新建想法')),
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
                  hintText: context.tr(T('搜索想法标题和正文')),
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
          // 分类条放在视图 tab 之后、列表之前。
          // 它是一个常驻的横向筛选行，而不是藏在弹窗里：
          // 分组是想法的主要组织方式，藏起来等于让用户忘记它存在。
          if (c.view != NoteView.trashed)
            _CategoryBar(
              controller: c,
              onCreate: _createCategory,
              onManage: _manageCategory,
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
                              label: Text(context.tr(T('清空回收站'))),
                            ),
                          )
                        : null,
                  ),
          ),
        ],
      ),
    );
  }

  /// AI 读取范围设置面板。
  ///
  /// 这个面板同时承担两件事：
  /// 1. 总开关（和设置页那个是同一个值，两处都能改）
  /// 2. 限定分组（只有这里有数据，所以只能在这里做）
  ///
  /// 底部的说明行会实时显示「当前实际会读到多少条」，
  /// 让开关的效果是**可见的**，而不是改完不知道该期待什么。
  Future<void> _showAiScopeSheet() async {
    final sc = widget.settingsController;
    if (sc == null) return;
    final colors = context.appColors;
    final builder = const NoteContextBuilder();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final cats = c.store.categories;
          final selected = sc.aiNoteCategoryIds.toSet();
          final preview = builder.buildFromSettings(
            allNotes: c.store.all,
            enabled: sc.aiReadNotes,
            categoryIds: selected,
          );

          return SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpace.md,
                      AppSpace.md,
                      AppSpace.md,
                      AppSpace.xs,
                    ),
                    child: Text(
                      context.tr(T('AI 读取范围')),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  SwitchListTile(
                    value: sc.aiReadNotes,
                    onChanged: (v) async {
                      await sc.setAiReadNotes(enabled: v);
                      setSheet(() {});
                      if (mounted) setState(() {});
                    },
                    secondary: const Icon(Icons.psychology_outlined),
                    title: Text(context.tr(T('允许 AI 读取想法'))),
                    subtitle: Text(
                      context.tr(T('关闭时 AI 看不到任何想法，除非你在对话里指定')),
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textTertiary,
                      ),
                    ),
                  ),
                  if (sc.aiReadNotes) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpace.md,
                        AppSpace.xs,
                        AppSpace.md,
                        AppSpace.xxs,
                      ),
                      child: Text(
                        context.tr(T('限定分组（不选 = 全部）')),
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textTertiary,
                        ),
                      ),
                    ),
                    for (final cat in cats)
                      CheckboxListTile(
                        value: selected.contains(cat.id),
                        onChanged: (v) async {
                          final next = Set<String>.of(selected);
                          if (v == true) {
                            next.add(cat.id);
                          } else {
                            next.remove(cat.id);
                          }
                          await sc.setAiNoteCategories(next.toList());
                          setSheet(() {});
                          if (mounted) setState(() {});
                        },
                        dense: true,
                        title: Text(cat.name),
                        subtitle: Text(
                          TP('{} 条', [c.store.countInCategory(cat.id)]),
                          style: TextStyle(
                            fontSize: 11,
                            color: colors.textTertiary,
                          ),
                        ),
                      ),
                    if (cats.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(AppSpace.md),
                        child: Text(
                          context.tr(T('还没有分组。可以在想法页新建分组后再回来限定范围。')),
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.textTertiary,
                          ),
                        ),
                      ),
                  ],
                  // 实时反馈：让用户看到规则生效后的实际结果
                  Padding(
                    padding: const EdgeInsets.all(AppSpace.md),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppSpace.sm),
                      decoration: BoxDecoration(
                        color: colors.surfaceHigh,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Text(
                        preview.describe(),
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
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
        builder: (_) =>
            NoteEditorPage(controller: c, noteId: note.id, isNew: isNew),
      ),
    );
    if (changed == true && mounted) setState(() {});
  }

  Future<void> _purgeAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr(T('清空回收站'))),
        content: Text(TP('将永久删除 {} 条笔记，无法恢复。', [c.trashCount])),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr(T('取消'))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.tr(T('永久删除'))),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final n = await c.purgeAll();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(TP('已删除 {} 条', [n]))));
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
              title: Text(context.tr(T('编辑'))),
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
                title: Text(note.pinned ? T('取消精选') : T('精选')),
                subtitle: note.pinned
                    ? null
                    : Text(context.tr(T('精选的想法会优先提供给 AI'))),
                onTap: () {
                  Navigator.pop(ctx);
                  c.togglePin(note.id);
                },
              ),
            if (!inTrash)
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(context.tr(T('移动到分类'))),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickCategory(note);
                },
              ),
            if (inTrash) ...[
              ListTile(
                leading: const Icon(Icons.restore),
                title: Text(context.tr(T('恢复'))),
                onTap: () {
                  Navigator.pop(ctx);
                  c.restoreNote(note.id);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_forever),
                title: Text(context.tr(T('永久删除'))),
                onTap: () {
                  Navigator.pop(ctx);
                  c.purgeNote(note.id);
                },
              ),
            ] else
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: Text(context.tr(T('移到回收站'))),
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
            ListTile(title: Text(context.tr(T('移动到分类')))),
            ListTile(
              leading: const Icon(Icons.folder_off_outlined),
              title: Text(context.tr(T('不分类'))),
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
              title: Text(context.tr(T('新建分类'))),
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

  Future<void> _createCategory() async {
    final name = await _promptText(context.tr(T('新建分类')), T('分类名称'));
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
              title: Text(context.tr(T('重命名'))),
              onTap: () async {
                Navigator.pop(ctx);
                final name = await _promptText(
                  context.tr(T('重命名分类')),
                  T('分类名称'),
                  initial: cat.name,
                );
                if (name == null || name.trim().isEmpty) return;
                await c.renameCategory(cat.id, name.trim());
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(context.tr(T('删除分类'))),
              subtitle: Text(context.tr(T('想法不会被删除，只是解除归属'))),
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
            child: Text(context.tr(T('取消'))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: Text(context.tr(T('确定'))),
          ),
        ],
      ),
    );
  }
}

// ── 分类条 ───────────────────────────────────────────

/// 常驻的横向分类筛选条。
///
/// 交互设计：
/// - 点「全部」= 清除分类过滤
/// - 点某个分类 = 只看它
/// - 点「+」= 新建分组
/// - 长按分类 = 重命名 / 删除
///
/// 之所以做成一整行而不是下拉弹窗：分类是想法的主要组织维度，
/// 每次切换都要开弹窗选一次，等于让它变成「隐藏功能」。
class _CategoryBar extends StatelessWidget {
  const _CategoryBar({
    required this.controller,
    required this.onCreate,
    required this.onManage,
  });

  final NoteController controller;
  final VoidCallback onCreate;
  final void Function(NoteCategory) onManage;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final cats = controller.store.categories;

    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
        children: [
          _chip(
            context: context,
            label: T('全部'),
            selected: controller.categoryId == null,
            onTap: () => controller.setCategory(null),
          ),
          for (final cat in cats) ...[
            const SizedBox(width: AppSpace.xs),
            GestureDetector(
              onLongPress: () => onManage(cat),
              child: _chip(
                context: context,
                label: cat.name,
                selected: controller.categoryId == cat.id,
                onTap: () => controller.setCategory(
                  controller.categoryId == cat.id ? null : cat.id,
                ),
              ),
            ),
          ],
          const SizedBox(width: AppSpace.xs),
          Center(
            child: InkWell(
              onTap: onCreate,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.xs,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: c.divider),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Icon(Icons.add, size: 15, color: c.textSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip({
    required BuildContext context,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final c = context.appColors;
    return Center(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.sm,
            vertical: 4,
          ),
          decoration: BoxDecoration(
            color: selected
                ? c.accent.withValues(alpha: 0.12)
                : Colors.transparent,
            border: Border.all(
              color: selected ? Colors.transparent : c.divider,
            ),
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? c.accent : c.textSecondary,
            ),
          ),
        ),
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
      (NoteView.active, T('全部'), controller.activeCount),
      (NoteView.pinned, T('置顶'), controller.pinnedCount),
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
      padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, 96),
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
            padding: const EdgeInsets.only(top: AppSpace.xs),
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
    // 注意：这里**不能**加横向外边距。
    // 两列布局下卡片由外层 _MasonryGrid 的 Expanded 定宽，
    // 再加一层左右 padding 会让每列实际内容只有屏宽的 1/3 左右，
    // 视觉上显得非常局促。列间距由 grid 的 SizedBox 统一控制。
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.xs),
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
                      note.title.trim().isEmpty ? T('无标题') : note.title,
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
                    note.isDeleted ? T('已删除') : note.updatedLabel,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.4,
                      color: c.textTertiary,
                    ),
                  ),
                  if (note.charCount > 0) ...[
                    const SizedBox(width: 6),
                    Text(
                      TP('· {} 字', [note.charCount]),
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
      return EmptyState(icon: Icons.search_off, text: T('没有匹配的想法'));
    }
    return switch (view) {
      NoteView.trashed => EmptyState(
        icon: Icons.delete_outline,
        text: T('回收站是空的'),
      ),
      NoteView.pinned => EmptyState(
        icon: Icons.push_pin_outlined,
        text: T('还没有精选想法\n精选的想法会优先提供给 AI'),
      ),
      NoteView.active => EmptyState(
        icon: Icons.lightbulb_outline,
        text: T('还没有想法\n随手记一句，之后可以一键转成文章'),
      ),
    };
  }
}
