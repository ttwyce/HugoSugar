import 'package:flutter/material.dart';
import 'package:hugosugar/app/i18n/l10n_scope.dart';

import '../../app/theme/app_colors.dart';
import '../../core/site/commit_message.dart';
import '../../core/site/git_change.dart';
import '../../core/site/site_controller.dart';
import '../../core/site/token_store.dart';
import '../../shared/widgets.dart';

/// 推送页（M4）：变更列表 → commit message → push → Deploy Hook。
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
                    body: T('远端有本地没有的改动。直接推送会被拒绝，请先到「站点」页重新克隆同步。'),
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

  Future<void> _push() async {
    // 决定用哪个 token：输入框优先，否则读已保存的
    var token = _tokenCtrl.text.trim();
    if (token.isEmpty) {
      final store = await TokenStore.open();
      token = await store.read() ?? '';
    }
    if (token.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr(T('请先填写 GitHub 访问令牌')))),
      );
      return;
    }

    // 顺手把新输入的 token 存起来，下次不用再填
    if (_tokenCtrl.text.trim().isNotEmpty) {
      final store = await TokenStore.open();
      await store.write(token);
      _tokenCtrl.clear();
      await _loadToken();
    }

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(outcome.message ?? T('推送失败')),
          duration: const Duration(seconds: 4),
        ),
      );
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
