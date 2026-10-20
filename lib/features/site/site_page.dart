import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../core/site/git_service.dart';
import '../../core/site/site_config.dart';
import '../../core/site/site_controller.dart';
import '../../shared/widgets.dart';
import 'connect_site_page.dart';

/// 站点页：当前站点信息 + Git 状态 + 发布入口。
///
/// 四种形态：未接入（引导）/ 克隆中（进度）/ 失败（报错+重试）/ 已就绪（信息卡）
class SitePage extends StatefulWidget {
  const SitePage({super.key, required this.controller});

  final SiteController controller;

  @override
  State<SitePage> createState() => _SitePageState();
}

class _SitePageState extends State<SitePage> {
  GitStatusSummary? _status;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    _refreshStatus();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    setState(() {});
    _refreshStatus();
  }

  /// 读 git 状态。只在切页/状态变化时读一次，不做轮询。
  void _refreshStatus() {
    final path = widget.controller.repoPath;
    if (path == null || widget.controller.stage != SiteStage.ready) {
      if (_status != null) setState(() => _status = null);
      return;
    }
    final s = GitService.readStatus(path);
    if (s != _status) setState(() => _status = s);
  }

  Future<void> _openConnect() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ConnectSitePage(controller: widget.controller),
      ),
    );
    if (mounted) {
      setState(() {});
      _refreshStatus();
    }
  }

  Future<void> _confirmDisconnect() async {
    final c = context.appColors;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('解绑站点'),
        content: const Text('会删除本地已克隆的仓库副本，远端仓库不受影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('解绑', style: TextStyle(color: c.danger)),
          ),
        ],
      ),
    );
    if (ok == true) await widget.controller.disconnect();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final cfg = c.config;

    return Scaffold(
      appBar: AppBar(title: const Text('站点')),
      body: switch (c.stage) {
        SiteStage.empty => _EmptyView(onConnect: _openConnect),
        SiteStage.cloning => _CloningView(
            progress: c.progress,
          ),
        SiteStage.failed => _FailedView(
            error: c.error ?? '未知错误',
            onRetry: _openConnect,
          ),
        SiteStage.ready => RefreshIndicator(
            onRefresh: c.refresh,
            child: _ReadyView(
              config: cfg!,
              status: _status,
              posts: c.posts,
              onReconnect: _openConnect,
              onDisconnect: _confirmDisconnect,
            ),
          ),
      },
    );
  }
}

// ── 未接入 ─────────────────────────────────────────────

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.onConnect});

  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_outlined, size: 48, color: c.textTertiary),
            const SizedBox(height: AppSpace.md),
            Text(
              '还没有接入站点',
              style: TextStyle(
                fontSize: 16,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpace.xs),
            Text(
              '接入 Hugo 站点仓库后，就能在这里管理文章并推送到 GitHub。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.6,
                color: c.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpace.xl),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onConnect,
                child: const Text('接入 Git 仓库'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 克隆中 ─────────────────────────────────────────────

class _CloningView extends StatelessWidget {
  const _CloningView({required this.progress});

  final double? progress;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final pct = progress == null ? null : (progress! * 100).round();
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                value: progress,
                color: c.accent,
              ),
            ),
            const SizedBox(height: AppSpace.md),
            Text(
              '正在克隆仓库',
              style: TextStyle(
                fontSize: 15,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpace.xxs),
            Text(
              pct == null ? '连接中…' : '$pct%',
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: c.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpace.sm),
            Text(
              '首次克隆可能要几十秒，请保持网络畅通。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.6,
                color: c.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 失败 ───────────────────────────────────────────────

class _FailedView extends StatelessWidget {
  const _FailedView({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 40, color: c.danger),
            const SizedBox(height: AppSpace.md),
            Text(
              '接入失败',
              style: TextStyle(
                fontSize: 16,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpace.xs),
            Container(
              padding: const EdgeInsets.all(AppSpace.sm),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Text(
                error,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.6,
                  color: c.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: AppSpace.xl),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onRetry,
                child: const Text('重新接入'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 已就绪 ─────────────────────────────────────────────

class _ReadyView extends StatelessWidget {
  const _ReadyView({
    required this.config,
    required this.status,
    required this.posts,
    required this.onReconnect,
    required this.onDisconnect,
  });

  final SiteConfig config;
  final GitStatusSummary? status;
  final List<String> posts;
  final VoidCallback onReconnect;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        const SectionHeader('当前站点'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
          child: Container(
            padding: const EdgeInsets.all(AppSpace.md),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.folder_outlined, size: 18, color: c.accent),
                    const SizedBox(width: AppSpace.xs),
                    Expanded(
                      child: Text(
                        config.displayName,
                        style: TextStyle(
                          fontSize: 16,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                          color: c.textPrimary,
                        ),
                      ),
                    ),
                    const MiniTag('已连接', emphasized: true),
                  ],
                ),
                const SizedBox(height: AppSpace.sm),
                _InfoRow(label: '仓库', value: config.repoSlug),
                _InfoRow(
                  label: '分支',
                  value: status?.branch ?? config.branch,
                ),
                _InfoRow(label: '文章目录', value: config.postsDir),
                _InfoRow(label: '文章数', value: '${posts.length} 篇'),
                _InfoRow(
                  label: '本地变更',
                  value: status?.label ?? '读取中…',
                  highlight: status != null && !status!.isClean,
                ),
              ],
            ),
          ),
        ),

        const SectionHeader('发布'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
          child: Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: null,
                  child: const Text('提交并推送'),
                ),
              ),
              const SizedBox(height: AppSpace.xs),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: null,
                  child: const Text('触发 Vercel 部署'),
                ),
              ),
              const SizedBox(height: AppSpace.xs),
              Text(
                '发布功能在 M4 开放',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: c.textTertiary,
                ),
              ),
            ],
          ),
        ),

        if (posts.isNotEmpty) ...[
          SectionHeader('文章 · ${posts.length}'),
          for (var i = 0; i < posts.length; i++) ...[
            if (i > 0) const IndentedDivider(),
            ListTile(
              dense: true,
              leading: Icon(
                Icons.description_outlined,
                size: 18,
                color: c.textTertiary,
              ),
              title: Text(
                posts[i].replaceFirst(RegExp(r'\.md$'), ''),
                style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: c.textPrimary,
                ),
              ),
              subtitle: Text(
                '${config.postsDir}/${posts[i]}',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.5,
                  color: c.textTertiary,
                ),
              ),
            ),
          ],
        ],

        const SectionHeader('站点管理'),
        ListTile(
          leading: const Icon(Icons.sync),
          title: const Text('重新克隆'),
          subtitle: const Text('用新地址覆盖本地副本'),
          trailing: const Icon(Icons.chevron_right, size: 18),
          onTap: onReconnect,
        ),
        const IndentedDivider(),
        ListTile(
          leading: Icon(Icons.delete_outline, color: c.danger),
          title: Text('解绑站点', style: TextStyle(color: c.danger)),
          subtitle: const Text('删除本地副本，远端不受影响'),
          onTap: onDisconnect,
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: TextStyle(fontSize: 13, height: 1.5, color: c.textTertiary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: highlight ? c.warning : c.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}