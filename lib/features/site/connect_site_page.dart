import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../core/site/github_api.dart';
import '../../core/site/site_controller.dart';
import '../../core/site/token_store.dart';
import '../../shared/widgets.dart';

/// 接入站点：两步 —— ① 填 token 拉仓库列表 ② 选一个仓库克隆。
///
/// 相比手填 URL 的好处：不用记仓库名、不用怕大小写错，
/// 而且在列表阶段就能发现「token 权限不足」这类问题。
class ConnectSitePage extends StatefulWidget {
  const ConnectSitePage({super.key, required this.controller});

  final SiteController controller;

  @override
  State<ConnectSitePage> createState() => _ConnectSitePageState();
}

class _ConnectSitePageState extends State<ConnectSitePage>
    with AutomaticKeepAliveClientMixin {
  final _tokenCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();

  bool _obscure = true;


  /// 正在校验 token / 拉列表
  bool _loading = false;

  /// token 已通过校验
  bool _verified = false;
  String? _login;

  List<GitHubRepo> _repos = const [];
  String _query = '';

  /// 正在克隆的仓库
  String? _cloningFullName;

  GitHubException? _ghError;
  String? _otherError;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // 从本地读取已保存的令牌 —— 站点页和推送页共用同一份，
    // 用户填过一次就不该在另一个页面再填一次。
    _loadSavedToken();
  }

  Future<void> _loadSavedToken() async {
    final store = await TokenStore.open();
    final saved = await store.read();
    if (!mounted || saved == null) return;
    setState(() {
      _tokenCtrl.text = saved;
    });
    // 有令牌就直接拉列表，省掉一步手动点击
    await _loadRepos();
  }

  @override
  void dispose() {
    _tokenCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── 第一步：校验 token 并拉列表 ──────────────────────

  Future<void> _loadRepos() async {
    final token = _tokenCtrl.text.trim();
    if (token.isEmpty) {
      _showError('请先填写访问令牌');
      return;
    }

    setState(() {
      _loading = true;
      _ghError = null;
      _otherError = null;
      _repos = const [];
    });

    try {
      final login = await widget.controller.verifyToken(token);
      final repos = await widget.controller.listRepos(token);

      if (!mounted) return;
      setState(() {
        _verified = true;
        _login = login;
        _repos = repos;
        _loading = false;
      });
    } on GitHubException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _verified = false;
        _ghError = e;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _otherError = '$e';
      });
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  // ── 第二步：选仓库并克隆 ────────────────────────────

  Future<void> _clone(GitHubRepo repo) async {
    if (repo.isEmpty) {
      _showError('${repo.fullName} 是空仓库，先给它加一个提交再接入');
      return;
    }
    if (repo.archived) {
      _showError('${repo.fullName} 已归档，无法推送');
      return;
    }

    setState(() => _cloningFullName = repo.fullName);

    final token = _tokenCtrl.text.trim();
    final ok = await widget.controller.connect(
      repoUrl: repo.cloneUrl,
      pat: token,
      displayName: repo.name,
      repo: repo,
    );

    // 克隆成功说明这个令牌有效 —— 立刻存起来，
    // 之后推送页直接复用，不再要求用户填第二次。
    if (ok && token.isNotEmpty) {
      final store = await TokenStore.open();
      await store.write(token);
    }

    if (!mounted) return;
    setState(() => _cloningFullName = null);

    if (ok) {
      Navigator.of(context).pop();
    } else {
      // 失败详情在站点页展示
      Navigator.of(context).pop();
    }
  }

  // ── UI ────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final c = context.appColors;

    // 克隆中：整页进度
    final cloning = widget.controller.stage == SiteStage.cloning;
    if (cloning) {
      return _CloningOverlay(
        target: _cloningFullName ?? '',
        progress: widget.controller.progress,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_verified ? '选择仓库' : '接入 GitHub'),
        actions: [
          if (_verified)
            TextButton(
              onPressed: () => setState(() {
                _verified = false;
                _repos = const [];
                _login = null;
              }),
              child: const Text('换令牌'),
            ),
        ],
      ),
      body: _verified ? _buildRepoList(c) : _buildTokenForm(c),
    );
  }

  // 令牌表单
  Widget _buildTokenForm(AppColors c) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        const SectionHeader('访问令牌'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
          child: TextField(
            controller: _tokenCtrl,
            obscureText: _obscure,
            autocorrect: false,
            enableSuggestions: false,
            enabled: !_loading,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: 'ghp_... 或 github_pat_...',
              helperText: '需要 repo 权限才能看到私有仓库',
              suffixIcon: IconButton(
                icon: Icon(
                  _obscure ? Icons.visibility_off : Icons.visibility,
                  size: 18,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            onSubmitted: (_) => _loadRepos(),
          ),
        ),

        const SizedBox(height: AppSpace.md),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _loading ? null : _loadRepos,
              child: _loading
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: c.textTertiary,
                          ),
                        ),
                        const SizedBox(width: AppSpace.xs),
                        const Text('正在读取仓库…'),
                      ],
                    )
                  : const Text('读取我的仓库'),
            ),
          ),
        ),

        if (_ghError != null) ...[
          const SizedBox(height: AppSpace.md),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
            child: _ErrorBox(
              title: _ghTitle(_ghError!),
              detail: _ghError!.message,
              hint: _ghError!.hint,
            ),
          ),
        ],
        if (_otherError != null) ...[
          const SizedBox(height: AppSpace.md),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
            child: _ErrorBox(title: '请求失败', detail: _otherError!),
          ),
        ],

        const SizedBox(height: AppSpace.lg),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
          child: Text(
            '令牌只用于本机发起 Git 请求，保存在应用私有目录，不上传任何服务器。\n'
            '在 GitHub → Settings → Developer settings → '
            'Personal access tokens 生成，勾选 repo 权限。',
            style: TextStyle(fontSize: 12, height: 1.7, color: c.textTertiary),
          ),
        ),
      ],
    );
  }

  String _ghTitle(GitHubException e) {
    switch (e.kind) {
      case GitHubErrorKind.badToken:
        return '令牌无效';
      case GitHubErrorKind.forbidden:
        return '权限不足';
      case GitHubErrorKind.notFound:
        return '仓库不存在';
      case GitHubErrorKind.network:
        return '网络错误';
      case GitHubErrorKind.unknown:
        return '请求失败';
    }
  }

  // 仓库列表
  Widget _buildRepoList(AppColors c) {
    final filtered = _query.isEmpty
        ? _repos
        : _repos
            .where((r) =>
                r.fullName.toLowerCase().contains(_query.toLowerCase()))
            .toList();

    return Column(
      children: [
        // 搜索 + 当前账号
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.md,
            AppSpace.sm,
            AppSpace.md,
            AppSpace.xs,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.person_outline, size: 16, color: c.textTertiary),
                  const SizedBox(width: AppSpace.xxs),
                  Text(
                    _login ?? '',
                    style: TextStyle(
                      fontSize: 13,
                      color: c.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: AppSpace.xs),
                  MiniTag('${_repos.length} 个仓库'),
                ],
              ),
              const SizedBox(height: AppSpace.sm),
              TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v.trim()),
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: '搜索仓库',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  isDense: true,
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _query = '');
                          },
                        ),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: filtered.isEmpty
              ? EmptyState(
                  icon: _repos.isEmpty
                      ? Icons.folder_off_outlined
                      : Icons.search_off,
                  text: _repos.isEmpty ? '这个令牌看不到任何仓库' : '没有匹配的仓库',
                )
              : ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const IndentedDivider(),
                  itemBuilder: (_, i) => _RepoRow(
                    repo: filtered[i],
                    onTap: () => _clone(filtered[i]),
                  ),
                ),
        ),
      ],
    );
  }
}

// ── 仓库行 ─────────────────────────────────────────────

class _RepoRow extends StatelessWidget {
  const _RepoRow({required this.repo, required this.onTap});

  final GitHubRepo repo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final disabled = repo.isEmpty || repo.archived;

    return InkWell(
      onTap: disabled ? null : onTap,
      child: Opacity(
        opacity: disabled ? 0.45 : 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.md,
            vertical: AppSpace.sm,
          ),
          child: Row(
            children: [
              Icon(
                repo.private ? Icons.lock_outline : Icons.public,
                size: 16,
                color: c.textTertiary,
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            repo.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              height: 1.4,
                              fontWeight: FontWeight.w500,
                              color: c.textPrimary,
                            ),
                          ),
                        ),
                        if (repo.archived) ...[
                          const SizedBox(width: AppSpace.xs),
                          const MiniTag('已归档'),
                        ],
                        if (repo.isEmpty) ...[
                          const SizedBox(width: AppSpace.xs),
                          const MiniTag('空仓库'),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      repo.description.isEmpty
                          ? '${repo.owner} · ${repo.defaultBranch} · ${repo.pushedLabel}'
                          : '${repo.description} · ${repo.pushedLabel}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: c.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpace.xs),
              Icon(Icons.chevron_right, size: 18, color: c.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 克隆进度覆盖层 ─────────────────────────────────────

class _CloningOverlay extends StatelessWidget {
  const _CloningOverlay({required this.target, required this.progress});

  final String target;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final pct = progress == null ? null : (progress! * 100).round();

    return Scaffold(
      appBar: AppBar(title: const Text('正在接入')),
      body: Center(
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
                '正在克隆',
                style: TextStyle(
                  fontSize: 15,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                  color: c.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpace.xxs),
              Text(
                target,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: c.textSecondary,
                ),
              ),
              if (pct != null) ...[
                const SizedBox(height: AppSpace.xxs),
                Text(
                  '$pct%',
                  style: TextStyle(
                    fontSize: 12,
                    color: c.textTertiary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── 错误框 ─────────────────────────────────────────────

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.title, required this.detail, this.hint});

  final String title;
  final String detail;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Container(
      padding: const EdgeInsets.all(AppSpace.sm),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline, size: 16, color: c.danger),
              const SizedBox(width: AppSpace.xs),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.xxs),
          Text(
            detail,
            style: TextStyle(
              fontSize: 12,
              height: 1.6,
              color: c.textSecondary,
            ),
          ),
          if (hint != null) ...[
            const SizedBox(height: AppSpace.xxs),
            Text(
              hint!,
              style: TextStyle(
                fontSize: 12,
                height: 1.6,
                color: c.textTertiary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}