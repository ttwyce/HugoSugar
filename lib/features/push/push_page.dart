import 'package:flutter/material.dart';
import 'package:hugosugar/app/i18n/l10n_scope.dart';

import '../../app/theme/app_colors.dart';
import '../../core/site/commit_message.dart';
import '../../core/site/git_change.dart';
import '../../core/site/site_controller.dart';
import '../../core/site/token_store.dart';
import '../../shared/widgets.dart';

/// 推送页（M4）：变更列表 → commit message → commit + push。
///
/// Deploy Hook 已移除：推送成功后由平台监听仓库自动构建，不需要 App 侧触发。
/// commit 与 push 都走后台 isolate（`GitService.commitAndPush`），
/// 避免 libgit2 的同步 FFI 阻塞 UI。
///
/// 设计取舍：
/// - 变更列表**只读**，不支持勾选部分文件。原因：文章编辑的改动天然是
///   一组（改 Front Matter 会同时动 date/draft），让用户拆开提交容易产生
///   半成品状态。要排除某个文件，应该先把它还原。
/// - 冲突文件用醒目颜色单列，并在顶部直接拦截推送。
class PushPage extends StatefulWidget {
  const PushPage({super.key, required this.controller});

  final SiteController controller;

  @override
  State<PushPage> createState() => _PushPageState();
}

class _PushPageState extends State<PushPage> {
  final _msgCtrl = TextEditingController();
  final _tokenCtrl = TextEditingController();

  List<GitChange> _changes = const [];
  bool _loading = true;
  bool _busy = false;
  bool _obscureToken = true;
  String? _tokenMask;

  /// 执行日志，倒序显示（最新的在上面）
  final List<String> _log = [];

  @override
  void initState() {
    super.initState();
    _refresh();
    _loadToken();
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadToken() async {
    final store = await TokenStore.open();
    final saved = await store.read();
    if (!mounted) return;
    setState(() {
      _tokenMask = saved == null
          ? null
          : '${saved.substring(0, (saved.length * 0.3).ceil())}••••'
                '${saved.substring(saved.length - 4)}';
    });
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final changes = widget.controller.changes;
    if (!mounted) return;
    setState(() {
      _changes = changes;
      _loading = false;
      // 只在用户还没改过 message 时自动填
      if (_msgCtrl.text.trim().isEmpty) {
        _msgCtrl.text = CommitMessage.suggest(
          changes.map((e) => e.path).toList(),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final conflicts = _changes.where((e) => e.isConflict).toList();
    final div = widget.controller.divergence;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(T('推送到 GitHub'))),
        actions: [
          IconButton(
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh, size: 20),
            tooltip: context.tr(T('重新读取变更')),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2.5))
          : ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                if (div != null && div.behind > 0)
                  _banner(
                    context,
                    icon: Icons.warning_amber_outlined,
                    color: c.danger,
                    title: TP('落后远端 {} 个提交', [div.behind]),
                    body: T('远端有本地没有的改动。直接推送会被拒绝，需要先拉取同步。'),
                    action: OutlinedButton.icon(
                      onPressed: _busy ? null : _pull,
                      icon: const Icon(Icons.download_outlined, size: 16),
                      label: Text(context.tr(T('拉取远端更新'))),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: c.danger,
                        side: BorderSide(color: c.danger.withValues(alpha: 0.4)),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                if (conflicts.isNotEmpty)
                  _banner(
                    context,
                    icon: Icons.error_outline,
                    color: c.danger,
                    title: TP('{} 个文件存在合并冲突', [conflicts.length]),
                    body: T('冲突未解决前无法提交。请在电脑上处理冲突，或重新克隆一份干净的仓库。'),
                  ),

                SectionHeader(T('变更')),
                if (_changes.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpace.md,
                      AppSpace.sm,
                      AppSpace.md,
                      AppSpace.md,
                    ),
                    child: Text(
                      context.tr(T('没有未提交的改动。')),
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.6,
                        color: c.textTertiary,
                      ),
                    ),
                  )
                else ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpace.md,
                      0,
                      AppSpace.md,
                      AppSpace.xs,
                    ),
                    child: Text(
                      TP('共 {} 个文件', [_changes.length]),
                      style: TextStyle(fontSize: 12, color: c.textTertiary),
                    ),
                  ),
                  for (final ch in _changes) _changeRow(context, ch),
                ],

                SectionHeader(T('提交说明')),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.md,
                    vertical: AppSpace.xs,
                  ),
                  child: TextField(
                    controller: _msgCtrl,
                    maxLines: 3,
                    minLines: 2,
                    style: const TextStyle(fontSize: 14, height: 1.5),
                    decoration: InputDecoration(
                      hintText: context.tr(T('这次改了什么')),
                      hintStyle: TextStyle(fontSize: 13, color: c.textTertiary),
                      filled: true,
                      fillColor: c.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                  ),
                ),

                SectionHeader(T('访问令牌')),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.md,
                    vertical: AppSpace.xs,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_tokenMask != null && _tokenCtrl.text.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            TP('已保存：{}（点下方输入框可替换）', [_tokenMask]),
                            style: TextStyle(
                              fontSize: 12,
                              color: c.textTertiary,
                            ),
                          ),
                        ),
                      TextField(
                        controller: _tokenCtrl,
                        obscureText: _obscureToken,
                        style: const TextStyle(fontSize: 13),
                        decoration: InputDecoration(
                          hintText: _tokenMask == null
                              ? T('ghp_... 需要 repo 权限')
                              : T('留空则使用已保存的令牌'),
                          hintStyle: TextStyle(
                            fontSize: 13,
                            color: c.textTertiary,
                          ),
                          filled: true,
                          fillColor: c.surface,
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureToken
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              size: 18,
                            ),
                            onPressed: () =>
                                setState(() => _obscureToken = !_obscureToken),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                if (_log.isNotEmpty) ...[
                  SectionHeader(T('执行记录')),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: AppSpace.md),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final line in _log.reversed)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              line,
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.5,
                                fontFamily: 'monospace',
                                color: c.textSecondary,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: AppSpace.md),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed:
                          (_busy || _changes.isEmpty || conflicts.isNotEmpty)
                          ? null
                          : _push,
                      child: _busy
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(context.tr(T('提交并推送'))),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _banner(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String body,
    Widget? action,
  }) {
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpace.md,
        AppSpace.sm,
        AppSpace.md,
        0,
      ),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.55,
                    color: context.appColors.textSecondary,
                  ),
                ),
                if (action != null) ...[
                  const SizedBox(height: 8),
                  action,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _changeRow(BuildContext context, GitChange ch) {
    final c = context.appColors;
    final color = switch (ch.kind) {
      GitChangeKind.added => c.accent,
      GitChangeKind.deleted => c.danger,
      GitChangeKind.conflicted => c.danger,
      _ => c.textSecondary,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              ch.kind.badge,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                fontFamily: 'monospace',
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              ch.path,
              style: TextStyle(
                fontSize: 12,
                height: 1.6,
                fontFamily: 'monospace',
                color: ch.isConflict ? c.danger : c.textPrimary,
              ),
            ),
          ),
          if (ch.isConflict)
            Text(
              context.tr(T('冲突')),
              style: TextStyle(fontSize: 11, color: c.danger),
            ),
        ],
      ),
    );
  }

  /// 拉取远端更新。
  ///
  /// 工作区有未提交改动时必须先让用户明确同意丢弃 —— fast-forward 用的是
  /// hard reset，那些改动会连同未保存的正文一起没掉。这是唯一一处
  /// 「可能弄丢用户输入」的操作，所以确认弹窗必须列出受影响文件，
  /// 而不是一句笼统的「确定吗」。
  Future<void> _pull() async {
    final token = await _resolveToken();
    if (token == null || !mounted) return;

    var discard = false;
    if (_changes.isNotEmpty) {
      final names = _changes.take(5).map((e) => e.path).toList();
      final more = _changes.length - names.length;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(context.tr(T('本地有未提交的改动'))),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr(T('拉取会先丢弃这些改动再同步远端，丢弃后无法恢复。')),
                style: const TextStyle(fontSize: 13, height: 1.6),
              ),
              const SizedBox(height: 10),
              for (final n in names)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    '· $n',
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              if (more > 0)
                Text(
                  TP('· 另外 {} 个文件', [more]),
                  style: const TextStyle(fontSize: 12),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(context.tr(T('取消'))),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(context.tr(T('丢弃并拉取'))),
            ),
          ],
        ),
      );
      if (ok != true) return;
      discard = true;
    }

    setState(() {
      _busy = true;
      _log.clear();
    });

    final outcome = await widget.controller.pull(
      pat: token,
      discardLocalChanges: discard,
      onStep: (s) {
        if (!mounted) return;
        setState(() => _log.add(s));
      },
    );

    if (!mounted) return;
    setState(() => _busy = false);

    // 拉取改了工作区，无论成败都重新读一次变更，避免界面停在旧状态
    await _refresh();
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          outcome.message ?? context.tr(outcome.ok ? '拉取完成' : '拉取失败'),
        ),
        duration: Duration(seconds: outcome.ok ? 3 : 6),
      ),
    );
  }

  /// 取本次操作用的 token：输入框优先，其次已保存的。
  /// 顺手把新输入的值存起来。返回 null 表示用户还没配 token。
  Future<String?> _resolveToken() async {
    var token = _tokenCtrl.text.trim();
    final typed = token.isNotEmpty;
    if (token.isEmpty) {
      final store = await TokenStore.open();
      token = await store.read() ?? '';
    }
    if (!mounted) return null;
    if (token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr(T('请先填写 GitHub 访问令牌')))),
      );
      return null;
    }
    if (typed) {
      final store = await TokenStore.open();
      await store.write(token);
      _tokenCtrl.clear();
      await _loadToken();
    }
    return token;
  }

  Future<void> _push() async {
    final token = await _resolveToken();
    if (token == null || !mounted) return;

    setState(() {
      _busy = true;
      _log.clear();
    });

    final outcome = await widget.controller.push(
      pat: token,
      commitMessage: _msgCtrl.text,
      onStep: (s) {
        if (!mounted) return;
        setState(() => _log.add(s));
      },
    );

    if (!mounted) return;
    setState(() {
      _busy = false;
    });

    if (outcome.ok) {
      // 推送成功后变更列表已清空，刷新一次让 UI 反映真实状态
      await _refresh();
      if (!mounted) return;
      _showResultDialog(outcome);
    } else {
      // 被拒原因是「落后远端」时，直接给一个可点的拉取入口 ——
      // 只说「请先拉取」而页面上没有拉取按钮，等于把用户卡在死路上。
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(outcome.message ?? context.tr(T('推送失败'))),
          duration: const Duration(seconds: 6),
          action: outcome.needsPull
              ? SnackBarAction(
                  label: context.tr(T('拉取')),
                  onPressed: _pull,
                )
              : null,
        ),
      );
      // 失败后也刷新一次：落后状态可能在这次尝试中变化
      await _refresh();
    }
  }

  void _showResultDialog(PushOutcome outcome) {
    final c = context.appColors;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr(T('推送成功'))),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              TP('提交 {}', [outcome.commitSha]),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
            const SizedBox(height: 8),
            Text(
              T('已推送到 GitHub。如果你的站点由 Vercel 等平台托管，平台会监听仓库自动开始构建，无需手动触发。'),
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: c.textSecondary,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.tr(T('好'))),
          ),
        ],
      ),
    );
  }
}
