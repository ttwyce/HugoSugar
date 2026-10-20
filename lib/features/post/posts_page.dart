import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../core/post/front_matter.dart';
import '../../core/site/site_controller.dart';
import '../../shared/widgets.dart';
import '../editor/editor_page.dart';

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
    final hasActiveFilter = _filter != _Filter.all ||
        _category != null ||
        _tag != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('文章'),
        actions: [
          IconButton(
            onPressed: sc.stage == SiteStage.ready
                ? () => setState(() => _showFilters = !_showFilters)
                : null,
            icon: Icon(
              _showFilters ? Icons.filter_list_off : Icons.filter_list,
            ),
            tooltip: '筛选',
          ),
          IconButton(
            onPressed: sc.stage == SiteStage.ready ? sc.refresh : null,
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
          ),
          const SizedBox(width: AppSpace.xs),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: sc.stage == SiteStage.ready ? () {} : null,
        tooltip: '新建文章',
        child: const Icon(Icons.add),
      ),
      body: switch (sc.stage) {
        SiteStage.ready when sc.posts.isEmpty => const EmptyState(
            icon: Icons.description_outlined,
            text: '还没有文章',
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
                      ? '筛选结果 · ${visible.length}'
                      : '全部 · ${visible.length}',
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
                          child: const Text('清除'),
                        ),
                      ],
                    ),
                  ),
                if (visible.isEmpty)
                  const EmptyState(
                    icon: Icons.filter_alt_off_outlined,
                    text: '没有符合条件的文章',
                  )
                else
                  for (var i = 0; i < visible.length; i++) ...[
                    if (i > 0) const IndentedDivider(),
                    _PostRow(
                      post: visible[i],
                      onTap: () => _open(visible[i]),
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
                ? '站点接入失败，请到「站点」页重试'
                : '请先到「站点」页接入 Git 仓库',
          ),
      },
    );
  }

  String _describeFilter() {
    final parts = <String>[];
    if (_filter == _Filter.drafts) parts.add('草稿');
    if (_filter == _Filter.published) parts.add('已发布');
    if (_category != null) parts.add('分类：$_category');
    if (_tag != null) parts.add('标签：$_tag');
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
            label: '状态',
            children: [
              _Chip(
                text: '全部 $totalCount',
                selected: filter == _Filter.all,
                onTap: () => onFilter(_Filter.all),
              ),
              _Chip(
                text: '草稿 $draftCount',
                selected: filter == _Filter.drafts,
                onTap: () => onFilter(_Filter.drafts),
              ),
              _Chip(
                text: '已发布 $publishedCount',
                selected: filter == _Filter.published,
                onTap: () => onFilter(_Filter.published),
              ),
            ],
          ),

          if (categories.isNotEmpty)
            _Rail(
              label: '分类',
              children: [
                _Chip(
                  text: '不限',
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
              label: '标签',
              children: [
                _Chip(
                  text: '不限',
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
                '这些文章还没有分类或标签。'
                '在文章 Front Matter 里加 categories / tags 后即可在这里筛选。',
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
  const _PostRow({required this.post, required this.onTap});

  final PostDocument post;
  final VoidCallback onTap;

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
                  const MiniTag('草稿'),
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