import 'package:flutter/material.dart';
import 'package:hugosugar/app/i18n/l10n_scope.dart';

import '../../app/theme/app_colors.dart';
import '../../core/site/post_trash_store.dart';
import '../../core/site/site_controller.dart';
import '../../shared/widgets.dart';

/// 文章回收站。
///
/// 打开时会先确保回收站已从磁盘加载（站点可能是热启动过来的，
/// `_trash` 还是 null），所以这里显式的等一次 `open`。
class PostTrashPage extends StatefulWidget {
  const PostTrashPage({super.key, required this.controller});

  final SiteController controller;

  @override
  State<PostTrashPage> createState() => _PostTrashPageState();
}

class _PostTrashPageState extends State<PostTrashPage> {
  SiteController get sc => widget.controller;

  @override
  void initState() {
    super.initState();
    sc.addListener(_onChanged);
  }

  @override
  void dispose() {
    sc.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final items = sc.trashedPosts;

    return Scaffold(
      appBar: AppBar(
        title: Text(items.isEmpty ? T('回收站') : TP('回收站 · {}', [items.length])),
        actions: [
          if (items.isNotEmpty)
            IconButton(
              onPressed: _purgeAll,
              icon: const Icon(Icons.delete_forever),
              tooltip: context.tr(T('清空回收站')),
            ),
          const SizedBox(width: AppSpace.xs),
        ],
      ),
      body: items.isEmpty
          ? EmptyState(
              icon: Icons.delete_outline,
              text: T('回收站是空的\n删掉的文章会先放到这里'),
            )
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 32),
              itemCount: items.length,
              itemBuilder: (_, i) => _TrashTile(
                item: items[i],
                onRestore: () => _restore(items[i]),
                onPurge: () => _purge(items[i]),
              ),
            ),
    );
  }

  Future<void> _restore(TrashedPost item) async {
    final ok = await sc.restorePost(item.relativePath);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? T('已恢复') : TP('恢复失败：{}', [sc.error ?? "未知错误"])),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _purge(TrashedPost item) async {
    final c = context.appColors;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr(T('永久删除？'))),
        content: Text(TP('{}\n\n此操作不可恢复。', [item.title])),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr(T('取消'))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: c.danger),
            child: Text(context.tr(T('永久删除'))),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await sc.purgePost(item.relativePath);
  }

  Future<void> _purgeAll() async {
    final c = context.appColors;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr(T('清空回收站？'))),
        content: Text(TP('将永久删除 {} 篇文章，无法恢复。', [sc.trashCount])),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr(T('取消'))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: c.danger),
            child: Text(context.tr(T('永久删除'))),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final n = await sc.purgeAllTrashedPosts();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(TP('已永久删除 {} 篇', [n])),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

class _TrashTile extends StatelessWidget {
  const _TrashTile({
    required this.item,
    required this.onRestore,
    required this.onPurge,
  });

  final TrashedPost item;
  final VoidCallback onRestore;
  final VoidCallback onPurge;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.md,
        AppSpace.xs,
        AppSpace.md,
        AppSpace.xxs,
      ),
      child: Container(
        padding: const EdgeInsets.all(AppSpace.sm),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.title.trim().isEmpty ? T('无标题') : item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                height: 1.4,
                fontWeight: FontWeight.w500,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              item.relativePath,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: c.textTertiary),
            ),
            const SizedBox(height: 2),
            Text(
              TP('删除于 {}', [_fmt(item.deletedAt)]),
              style: TextStyle(fontSize: 11, color: c.textTertiary),
            ),
            const SizedBox(height: AppSpace.xxs),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: onRestore,
                  icon: const Icon(Icons.restore, size: 16),
                  label: Text(context.tr(T('恢复'))),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                TextButton.icon(
                  onPressed: onPurge,
                  icon: const Icon(Icons.delete_forever, size: 16),
                  label: Text(context.tr(T('永久删除'))),
                  style: TextButton.styleFrom(
                    foregroundColor: c.danger,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _fmt(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} '
        '${two(d.hour)}:${two(d.minute)}';
  }
}
