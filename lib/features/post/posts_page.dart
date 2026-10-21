import 'package:flutter/material.dart';

import '../../app/i18n/l10n_scope.dart';
import '../../app/theme/app_colors.dart';
import '../../core/post/front_matter.dart';
import '../../core/post/post_transfer.dart';
import '../../core/post/post_transfer_service.dart';
import '../../core/site/site_controller.dart';
import '../../shared/widgets.dart';
import '../editor/editor_page.dart';
import '../push/push_page.dart';
import 'post_trash_page.dart';
import '../../shared/chip_editor.dart';

/// 文章列表的筛选维度
enum _Filter { all, drafts, published }

/// 文章列表。
///
/// M2：标题、摘要、日期、分类、标签全部来自 Front Matter，
/// 不再用文件名占位。
class PostsPage extends StatefulWidget {
  const PostsPage({super.key, required this.siteController});

  final SiteController siteController;

  @override
  State<PostsPage> createState() => _PostsPageState();
}

class _PostsPageState extends State<PostsPage> {
  _Filter _filter = _Filter.all;

  /// 当前选中的分类 / 标签，null 表示不过滤
  String? _category;
  String? _tag;

  /// 是否展开筛选栏
  bool _showFilters = false;

  @override
  void initState() {
    super.initState();
    widget.siteController.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.siteController.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  /// 导出全部文章为 zip 并调起系统分享。
  Future<void> _exportAll(SiteController sc) async {
    final service = PostTransferService(sc);
    try {
      final report = await service.exportAll();
      if (!mounted) return;
      _showReport(report);
    } catch (e) {
      if (!mounted) return;
      _showSnack(TP('导出失败：{}', [e]));
    }
  }

  /// 导入文章。先让用户选同名冲突策略，再选文件。
  Future<void> _importPosts(SiteController sc) async {
    final conflict = await showDialog<ImportConflict>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(context.tr(T('导入文章'))),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              context.tr(T('遇到同名文件时：')),
              style: TextStyle(fontSize: 12, color: ctx.appColors.textTertiary),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, ImportConflict.skip),
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.skip_next, size: 20),
              title: Text(context.tr(T('跳过已存在的'))),
              subtitle: Text(
                context.tr(T('保留仓库里的版本（推荐）')),
                style: TextStyle(fontSize: 11),
              ),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, ImportConflict.rename),
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.copy_all_outlined, size: 20),
              title: Text(context.tr(T('存为新文件'))),
              subtitle: Text(
                context.tr(T('自动加 -2、-3 后缀')),
                style: TextStyle(fontSize: 11),
              ),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, ImportConflict.overwrite),
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.swap_horiz, size: 20),
              title: Text(context.tr(T('覆盖已存在的'))),
              subtitle: Text(
                context.tr(T('仓库里的同名文件会被替换')),
                style: TextStyle(fontSize: 11),
              ),
            ),
          ),
        ],
      ),
    );
    if (conflict == null || !mounted) return;

    final service = PostTransferService(sc);
    try {
      final report = await service.pickAndImport(conflict: conflict);
      if (!mounted) return;
      if (report == null) return; // 用户取消选文件
      _showReport(report);
    } catch (e) {
      if (!mounted) return;
      _showSnack(TP('导入失败：{}', [e]));
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// 展示导入导出结果。
  ///
  /// 失败/跳过的明细用对话框而不是 SnackBar：
  /// 只报「失败 3 篇」等于没说，用户需要知道是哪 3 篇、为什么。
  void _showReport(TransferReport report) {
    if (report.failed.isEmpty && report.skipped.isEmpty) {
      _showSnack(report.message);
      return;
    }
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final c = ctx.appColors;
        return AlertDialog(
          title: Text(report.ok ? T('完成') : T('部分完成')),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                Text(
                  report.message,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (report.failed.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    context.tr(T('失败')),
                    style: TextStyle(fontSize: 12, color: c.danger),
                  ),
                  for (final e in report.failed.entries)
                    Text(
                      '· ${e.key}：${e.value}',
                      style: TextStyle(fontSize: 11, color: c.textSecondary),
                    ),
                ],
                if (report.skipped.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    context.tr(T('跳过')),
                    style: TextStyle(fontSize: 12, color: c.textTertiary),
                  ),
                  for (final e in report.skipped.entries)
                    Text(
                      '· ${e.key}：${e.value}',
                      style: TextStyle(fontSize: 11, color: c.textTertiary),
                    ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(context.tr(T('知道了'))),
            ),
          ],
        );
      },
    );
  }

  List<PostDocument> _visible(SiteController sc) {
    var list = sc.posts;

    switch (_filter) {
      case _Filter.drafts:
        list = list.where((p) => p.draft).toList();
      case _Filter.published:
        list = list.where((p) => !p.draft).toList();
      case _Filter.all:
        break;
    }

    final cat = _category;
    if (cat != null) {
      list = list.where((p) => p.categories.contains(cat)).toList();
    }
    final tag = _tag;
    if (tag != null) {
      list = list.where((p) => p.tags.contains(tag)).toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final sc = widget.siteController;
    final visible = _visible(sc);
    final hasActiveFilter =
        _filter != _Filter.all || _category != null || _tag != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(T('文章'))),
        actions: [
          IconButton(
            onPressed: sc.stage == SiteStage.ready
                ? () => setState(() => _showFilters = !_showFilters)
                : null,
            icon: Icon(
              _showFilters ? Icons.filter_list_off : Icons.filter_list,
            ),
            tooltip: context.tr(T('筛选')),
          ),
          IconButton(
            onPressed: sc.stage == SiteStage.ready ? sc.refresh : null,
            icon: const Icon(Icons.refresh),
            tooltip: context.tr(T('刷新')),
          ),
          IconButton(
            onPressed: sc.stage == SiteStage.ready
                ? () => _openTrash(sc)
                : null,
            icon: Icon(sc.trashCount > 0 ? Icons.delete : Icons.delete_outline),
            tooltip: sc.trashCount > 0
                ? TP('回收站（{}）', [sc.trashCount])
                : T('回收站'),
          ),
          IconButton(
            onPressed: sc.stage == SiteStage.ready ? () => _openPush(sc) : null,
            icon: const Icon(Icons.cloud_upload_outlined),
            tooltip: context.tr(T('推送到 GitHub')),
          ),
          PopupMenuButton<String>(
            tooltip: context.tr(T('导入导出')),
            enabled: sc.stage == SiteStage.ready,
            icon: const Icon(Icons.swap_vert),
            onSelected: (v) {
              if (v == 'export_all') _exportAll(sc);
              if (v == 'import') _importPosts(sc);
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'export_all',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.download_outlined, size: 20),
                  title: Text(ctx.tr(T('导出全部文章'))),
                  subtitle: Text(
                    ctx.tr(T('打包成 zip 并分享')),
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ),
              PopupMenuItem(
                value: 'import',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.upload_outlined, size: 20),
                  title: Text(ctx.tr(T('导入文章'))),
                  subtitle: Text(
                    ctx.tr(T('从 zip 或 .md 导入')),
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: AppSpace.xs),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: sc.stage == SiteStage.ready ? () => _newPost(sc) : null,
        tooltip: context.tr(T('新建文章')),
        child: const Icon(Icons.add),
      ),
      body: switch (sc.stage) {
        SiteStage.ready when sc.posts.isEmpty => EmptyState(
          icon: Icons.description_outlined,
          text: T('还没有文章'),
        ),
        SiteStage.ready => RefreshIndicator(
          onRefresh: sc.refresh,
          child: ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              if (_showFilters) ...[
                _FilterBar(
                  filter: _filter,
                  category: _category,
                  tag: _tag,
                  draftCount: sc.draftCount,
                  publishedCount: sc.publishedCount,
                  totalCount: sc.posts.length,
                  categories: sc.allCategories,
                  tags: sc.allTags,
                  countInCategory: sc.countInCategory,
                  countWithTag: sc.countWithTag,
                  onFilter: (f) => setState(() => _filter = f),
                  onCategory: (v) => setState(() => _category = v),
                  onTag: (v) => setState(() => _tag = v),
                ),
                const SizedBox(height: AppSpace.xs),
              ],
              SectionHeader(
                hasActiveFilter
                    ? TP('筛选结果 · {}', [visible.length])
                    : TP('全部 · {}', [visible.length]),
              ),
              if (hasActiveFilter)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpace.md,
                    0,
                    AppSpace.md,
                    AppSpace.xs,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _describeFilter(),
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.5,
                            color: context.appColors.textTertiary,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => setState(() {
                          _filter = _Filter.all;
                          _category = null;
                          _tag = null;
                        }),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 0),
                        ),
                        child: Text(context.tr(T('清除'))),
                      ),
                    ],
                  ),
                ),
              if (visible.isEmpty)
                EmptyState(
                  icon: Icons.filter_alt_off_outlined,
                  text: T('没有符合条件的文章'),
                )
              else
                for (var i = 0; i < visible.length; i++) ...[
                  if (i > 0) const IndentedDivider(),
                  _PostRow(
                    post: visible[i],
                    onTap: () => _open(visible[i]),
                    onLongPress: () => _showPostMenu(sc, visible[i]),
                  ),
                ],
            ],
          ),
        ),
        SiteStage.cloning => const Center(
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
        _ => EmptyState(
          icon: Icons.folder_outlined,
          text: sc.stage == SiteStage.failed
              ? T('站点接入失败，请到「站点」页重试')
              : T('请先到「站点」页接入 Git 仓库'),
        ),
      },
    );
  }

  String _describeFilter() {
    final parts = <String>[];
    if (_filter == _Filter.drafts) parts.add(T('草稿'));
    if (_filter == _Filter.published) parts.add(T('已发布'));
    if (_category != null) parts.add(TP('分类：{}', [_category]));
    if (_tag != null) parts.add(TP('标签：{}', [_tag]));
    return parts.join(' · ');
  }

  void _open(PostDocument post) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EditorPage(
          title: post.title,
          relativePath: post.relativePath,
          controller: widget.siteController,
        ),
      ),
    );
  }

  /// 打开推送页
  void _openPush(SiteController sc) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => PushPage(controller: sc)));
  }

  /// 打开回收站。
  ///
  /// 先 `await sc.loadTrash()`：回收站是惰性打开的，
  /// 直接进页面会看到空列表（数据还没从磁盘读上来）。
  Future<void> _openTrash(SiteController sc) async {
    await sc.loadTrash();
    if (!mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => PostTrashPage(controller: sc)));
  }

  /// 长按文章行的快捷菜单
  ///
  /// 为什么用长按而不是每行右侧放个「···」：
  /// 列表要保持干净（设计原则「正文优先」），而删除是低频操作，
  /// 长按藏起来足够，也不会因为手指滑错就点到删除。
  Future<void> _showPostMenu(SiteController sc, PostDocument post) async {
    final c = context.appColors;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.md,
                AppSpace.sm,
                AppSpace.md,
                4,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      post.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined, size: 20),
              title: Text(context.tr(T('打开编辑'))),
              onTap: () => Navigator.pop(ctx, 'open'),
            ),
            ListTile(
              leading: Icon(
                post.draft
                    ? Icons.public_outlined
                    : Icons.visibility_off_outlined,
                size: 20,
              ),
              title: Text(post.draft ? T('发布这篇') : T('改为草稿')),
              onTap: () => Navigator.pop(ctx, 'toggleDraft'),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, size: 20, color: c.danger),
              title: Text(
                context.tr(T('删除')),
                style: TextStyle(color: c.danger),
              ),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
            const SizedBox(height: AppSpace.xs),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;

    switch (action) {
      case 'open':
        _open(post);
      case 'toggleDraft':
        await _toggleDraft(sc, post);
      case 'delete':
        await _confirmDelete(sc, post);
    }
  }

  Future<void> _toggleDraft(SiteController sc, PostDocument post) async {
    final result = await sc.savePost(
      relativePath: post.relativePath,
      title: post.title,
      body: post.body,
      original: post,
      draft: !post.draft,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.ok
              ? (post.draft ? T('已发布') : T('已改为草稿'))
              : TP('修改失败：{}', [result.message]),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _confirmDelete(SiteController sc, PostDocument post) async {
    final c = context.appColors;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr(T('删除这篇文章？'))),
        content: Text(
          TP('{}\n{}\n\n会移到回收站，可以在回收站里恢复。', [post.title, post.relativePath]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr(T('取消'))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: c.danger),
            child: Text(context.tr(T('移到回收站'))),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final deleted = await sc.trashPost(post.relativePath);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          deleted ? T('已移到回收站') : TP('删除失败：{}', [sc.error ?? "未知错误"]),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// 新建文章：先填标题和元信息，再写入文件。
  ///
  /// 为什么不直接建空文件让用户进去改标题：Hugo 的 title 是 Front Matter
  /// 里的字段，不是文件名。先收集信息再落盘，能保证文件名和 title 一致，
  /// 避免「文件名 abc.md 但标题是《你好》」这种混乱。
  Future<void> _newPost(SiteController sc) async {
    final existingCats = sc.allCategories;
    final existingTags = sc.allTags;

    final result = await showModalBottomSheet<_NewPostResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          _NewPostSheet(categories: existingCats, tags: existingTags),
    );
    if (result == null || !mounted) return;

    final path = await sc.createPost(
      title: result.title,
      categories: result.categories,
      tags: result.tags,
      description: result.description,
      draft: result.draft,
    );

    if (!mounted) return;
    if (path == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(sc.error ?? T('创建失败'))));
      return;
    }

    // 直接进编辑器
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            EditorPage(title: result.title, relativePath: path, controller: sc),
      ),
    );
  }
}

// ── 筛选栏 ────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.filter,
    required this.category,
    required this.tag,
    required this.draftCount,
    required this.publishedCount,
    required this.totalCount,
    required this.categories,
    required this.tags,
    required this.countInCategory,
    required this.countWithTag,
    required this.onFilter,
    required this.onCategory,
    required this.onTag,
  });

  final _Filter filter;
  final String? category;
  final String? tag;
  final int draftCount;
  final int publishedCount;
  final int totalCount;
  final List<String> categories;
  final List<String> tags;
  final int Function(String) countInCategory;
  final int Function(String) countWithTag;
  final void Function(_Filter) onFilter;
  final void Function(String?) onCategory;
  final void Function(String?) onTag;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;

    return Container(
      color: c.surface,
      padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Rail(
            label: T('状态'),
            children: [
              _Chip(
                text: TP('全部 {}', [totalCount]),
                selected: filter == _Filter.all,
                onTap: () => onFilter(_Filter.all),
              ),
              _Chip(
                text: TP('草稿 {}', [draftCount]),
                selected: filter == _Filter.drafts,
                onTap: () => onFilter(_Filter.drafts),
              ),
              _Chip(
                text: TP('已发布 {}', [publishedCount]),
                selected: filter == _Filter.published,
                onTap: () => onFilter(_Filter.published),
              ),
            ],
          ),

          if (categories.isNotEmpty)
            _Rail(
              label: T('分类'),
              children: [
                _Chip(
                  text: T('不限'),
                  selected: category == null,
                  onTap: () => onCategory(null),
                ),
                for (final cat in categories)
                  _Chip(
                    text: '$cat ${countInCategory(cat)}',
                    selected: category == cat,
                    onTap: () => onCategory(category == cat ? null : cat),
                  ),
              ],
            ),

          if (tags.isNotEmpty)
            _Rail(
              label: T('标签'),
              children: [
                _Chip(
                  text: T('不限'),
                  selected: tag == null,
                  onTap: () => onTag(null),
                ),
                for (final t in tags)
                  _Chip(
                    text: '#$t ${countWithTag(t)}',
                    selected: tag == t,
                    onTap: () => onTag(tag == t ? null : t),
                  ),
              ],
            ),

          if (categories.isEmpty && tags.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.md,
                AppSpace.xxs,
                AppSpace.md,
                0,
              ),
              child: Text(
                T(
                  '这些文章还没有分类或标签。在文章 Front Matter 里加 categories / tags 后即可在这里筛选。',
                ),
                style: TextStyle(
                  fontSize: 12,
                  height: 1.6,
                  color: c.textTertiary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xxs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.md,
              AppSpace.xxs,
              AppSpace.md,
              2,
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                height: 1.4,
                letterSpacing: 0.4,
                color: c.textTertiary,
              ),
            ),
          ),
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
              itemCount: children.length,
              separatorBuilder: (_, _) => const SizedBox(width: AppSpace.xs),
              itemBuilder: (_, i) => Center(child: children[i]),
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.text,
    required this.selected,
    required this.onTap,
  });

  final String text;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.sm,
          vertical: 5,
        ),
        decoration: BoxDecoration(
          color: selected ? c.accent.withValues(alpha: 0.12) : c.background,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(
            color: selected ? c.accent.withValues(alpha: 0.35) : c.divider,
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            height: 1.4,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? c.accent : c.textSecondary,
          ),
        ),
      ),
    );
  }
}

// ── 文章行 ────────────────────────────────────────────

class _PostRow extends StatelessWidget {
  const _PostRow({
    required this.post,
    required this.onTap,
    required this.onLongPress,
  });

  final PostDocument post;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;

    // 副标题：日期 + 分类，都是 Front Matter 里的真实信息
    final meta = <String>[
      if (post.dateLabel.isNotEmpty) post.dateLabel,
      if (post.categories.isNotEmpty) post.categories.join(' / '),
    ].join(' · ');

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.md,
          vertical: AppSpace.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    post.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.4,
                      fontWeight: FontWeight.w500,
                      color: c.textPrimary,
                    ),
                  ),
                ),
                if (post.draft) ...[
                  const SizedBox(width: AppSpace.xs),
                  MiniTag(T('草稿')),
                ],
              ],
            ),

            if (post.excerpt.isNotEmpty) ...[
              const SizedBox(height: AppSpace.xxs),
              Text(
                post.excerpt,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.55,
                  color: c.textSecondary,
                ),
              ),
            ],

            if (meta.isNotEmpty || post.tags.isNotEmpty) ...[
              const SizedBox(height: AppSpace.xs),
              Wrap(
                spacing: AppSpace.xs,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (meta.isNotEmpty)
                    Text(
                      meta,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: c.textTertiary,
                      ),
                    ),
                  for (final t in post.tags.take(3))
                    Text(
                      '#$t',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: c.accent.withValues(alpha: 0.85),
                      ),
                    ),
                  if (post.tags.length > 3)
                    Text(
                      '+${post.tags.length - 3}',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: c.textTertiary,
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── 新建文章表单 ───────────────────────────────────────

class _NewPostResult {
  const _NewPostResult({
    required this.title,
    required this.categories,
    required this.tags,
    required this.description,
    required this.draft,
  });

  final String title;
  final List<String> categories;
  final List<String> tags;
  final String description;
  final bool draft;
}

class _NewPostSheet extends StatefulWidget {
  const _NewPostSheet({required this.categories, required this.tags});

  /// 站点里已有的分类，用于快捷选择
  final List<String> categories;

  /// 站点里已有的标签
  final List<String> tags;

  @override
  State<_NewPostSheet> createState() => _NewPostSheetState();
}

class _NewPostSheetState extends State<_NewPostSheet> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _catInputCtrl = TextEditingController();
  final _tagInputCtrl = TextEditingController();

  List<String> _categories = <String>[];
  List<String> _tags = <String>[];
  bool _draft = true;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _catInputCtrl.dispose();
    _tagInputCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.tr(T('请填写标题')))));
      return;
    }
    Navigator.of(context).pop(
      _NewPostResult(
        title: title,
        categories: List.of(_categories),
        tags: List.of(_tags),
        description: _descCtrl.text.trim(),
        draft: _draft,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.md,
            AppSpace.xs,
            AppSpace.md,
            AppSpace.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr(T('新建文章')),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: c.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpace.md),

              // 标题
              TextField(
                controller: _titleCtrl,
                autofocus: true,
                style: const TextStyle(fontSize: 15),
                decoration: InputDecoration(
                  hintText: context.tr(T('标题')),
                  isDense: true,
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: AppSpace.sm),

              // 简介
              TextField(
                controller: _descCtrl,
                style: const TextStyle(fontSize: 14),
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: context.tr(T('简介（可选，会写进 description）')),
                  isDense: true,
                ),
              ),
              const SizedBox(height: AppSpace.sm),

              // 分类
              Text(
                context.tr(T('分类')),
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: c.textTertiary,
                ),
              ),
              const SizedBox(height: 4),
              ChipEditor(
                values: _categories,
                allValues: widget.categories,
                hint: T('添加分类，回车确认（可逗号分隔）'),
                controller: _catInputCtrl,
                onChanged: (v) => setState(() => _categories = v),
              ),
              const SizedBox(height: AppSpace.sm),

              // 标签
              Text(
                context.tr(T('标签')),
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: c.textTertiary,
                ),
              ),
              const SizedBox(height: 4),
              ChipEditor(
                values: _tags,
                allValues: widget.tags,
                hint: T('添加标签，回车确认（可逗号分隔）'),
                controller: _tagInputCtrl,
                onChanged: (v) => setState(() => _tags = v),
              ),
              const SizedBox(height: AppSpace.sm),

              // 草稿开关
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr(T('保存为草稿')),
                          style: TextStyle(fontSize: 14, color: c.textPrimary),
                        ),
                        Text(
                          context.tr(T('草稿不会出现在站点上，可在编辑器里随时转为发布')),
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.5,
                            color: c.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _draft,
                    onChanged: (v) => setState(() => _draft = v),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.md),

              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submit,
                  child: Text(context.tr(T('创建并开始写'))),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
