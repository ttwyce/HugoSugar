import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../core/site/site_controller.dart';
import '../../shared/widgets.dart';
import '../editor/editor_page.dart';

/// 文章列表。
///
/// M1 阶段只做到「从站点仓库真实读出去重的文件名」，标题/摘要/时间
/// 等 Front Matter 解析留到 M2。站点未接入时给出引导，不再展示假数据。
class PostsPage extends StatefulWidget {
  const PostsPage({super.key, required this.siteController});

  final SiteController siteController;

  @override
  State<PostsPage> createState() => _PostsPageState();
}

class _PostsPageState extends State<PostsPage> {
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

  @override
  Widget build(BuildContext context) {
    final sc = widget.siteController;
    final posts = sc.posts;

    return Scaffold(
      appBar: AppBar(
        title: const Text('文章'),
        actions: [
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
        SiteStage.ready when posts.isEmpty => const EmptyState(
            icon: Icons.description_outlined,
            text: '还没有文章',
          ),
        SiteStage.ready => RefreshIndicator(
            onRefresh: sc.refresh,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                SectionHeader('全部 · ${posts.length}'),
                for (var i = 0; i < posts.length; i++) ...[
                  if (i > 0) const IndentedDivider(),
                  _PostRow(
                    fileName: posts[i],
                    postsDir: sc.config?.postsDir ?? '',
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
}

class _PostRow extends StatelessWidget {
  const _PostRow({required this.fileName, required this.postsDir});

  final String fileName;
  final String postsDir;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final title = fileName.replaceFirst(RegExp(r'\.md$'), '');

    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => EditorPage(title: title)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.md,
          vertical: AppSpace.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 16,
                height: 1.4,
                fontWeight: FontWeight.w500,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpace.xxs),
            Text(
              postsDir.isEmpty ? fileName : '$postsDir/$fileName',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: c.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}