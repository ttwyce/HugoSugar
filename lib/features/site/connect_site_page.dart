import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../core/site/git_service.dart';
import '../../core/site/site_controller.dart';
import '../../shared/widgets.dart';

/// 接入站点表单：仓库地址 + PAT + 展示名。
///
/// 提交后由 [SiteController] 负责 clone，成功后自动返回。
class ConnectSitePage extends StatefulWidget {
  const ConnectSitePage({super.key, required this.controller});

  final SiteController controller;

  @override
  State<ConnectSitePage> createState() => _ConnectSitePageState();
}

class _ConnectSitePageState extends State<ConnectSitePage> {
  final _formKey = GlobalKey<FormState>();
  final _urlCtrl = TextEditingController();
  final _patCtrl = TextEditingController();
  final _nameCtrl = TextEditingController(text: '我的站点');
  final _postsDirCtrl = TextEditingController(text: 'content/posts');

  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    // 已经连过就把地址带出来，方便「重新克隆」
    final cfg = widget.controller.config;
    if (cfg != null) {
      _urlCtrl.text = cfg.repoUrl;
      _nameCtrl.text = cfg.displayName;
      _postsDirCtrl.text = cfg.postsDir;
    }
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _patCtrl.dispose();
    _nameCtrl.dispose();
    _postsDirCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    final ok = await widget.controller.connect(
      repoUrl: _urlCtrl.text,
      pat: _patCtrl.text,
      displayName: _nameCtrl.text,
      postsDir: _postsDirCtrl.text.trim(),
    );

    if (!mounted) return;
    setState(() => _busy = false);

    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() => _error = widget.controller.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;

    return Scaffold(
      appBar: AppBar(title: const Text('接入 Git 仓库')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            const SectionHeader('仓库'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
              child: TextFormField(
                controller: _urlCtrl,
                enabled: !_busy,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: '仓库地址',
                  hintText: 'https://github.com/用户/仓库.git',
                  helperText: '必须以 .git 结尾',
                ),
                validator: GitService.validateRepoUrl,
              ),
            ),
            const SizedBox(height: AppSpace.sm),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
              child: TextFormField(
                controller: _patCtrl,
                enabled: !_busy,
                obscureText: _obscure,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: '访问令牌 (PAT)',
                  hintText: 'ghp_...',
                  helperText: '需要 repo 权限，只存在本机',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure ? Icons.visibility_off : Icons.visibility,
                      size: 18,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return '请填写访问令牌';
                  if (v.trim().length < 20) return '令牌长度不对，请检查是否复制完整';
                  return null;
                },
              ),
            ),

            const SectionHeader('站点'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
              child: TextFormField(
                controller: _nameCtrl,
                enabled: !_busy,
                decoration: const InputDecoration(labelText: '站点名称'),
              ),
            ),
            const SizedBox(height: AppSpace.sm),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
              child: TextFormField(
                controller: _postsDirCtrl,
                enabled: !_busy,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: '文章目录',
                  helperText: '克隆后会自动识别，找不到才用这个值',
                ),
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: AppSpace.md),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
                child: Container(
                  padding: const EdgeInsets.all(AppSpace.sm),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.error_outline, size: 16, color: c.danger),
                      const SizedBox(width: AppSpace.xs),
                      Expanded(
                        child: Text(
                          _error!,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.6,
                            color: c.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: AppSpace.xl),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
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
                            const Text('正在克隆…'),
                          ],
                        )
                      : const Text('开始克隆'),
                ),
              ),
            ),

            const SizedBox(height: AppSpace.md),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
              child: Text(
                '令牌只保存在本机应用私有目录，不会上传到任何服务器。\n'
                '克隆会在本机生成一份仓库副本，内存占用取决于仓库大小。',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.7,
                  color: c.textTertiary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}