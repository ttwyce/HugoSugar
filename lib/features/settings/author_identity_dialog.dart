import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../core/settings/settings_controller.dart';

/// 提交作者身份设置。
///
/// 为什么需要这一页：
/// git commit 里的 author 是「名字 + 邮箱」两个字符串，GitHub 靠
/// **邮箱**把提交关联到你的账号。邮箱不对 → 提交显示为陌生名字，
/// 贡献格子也不会亮。
///
/// App 能自动查到的只有：
/// - `/user` 的公开邮箱（多数人没公开，是 null）
/// - `/user/emails`（需要 `user:email` 授权，多数 classic token 没勾）
/// - 兜底拼 `<id>+<login>@users.noreply.github.com`
///
/// 你的真实邮箱只有你知道，所以必须留一个手填入口。
class AuthorIdentityDialog extends StatefulWidget {
  const AuthorIdentityDialog({
    super.key,
    required this.controller,
    this.suggestedName,
    this.suggestedEmail,
  });

  final SettingsController controller;

  /// 令牌解析出的登录名，作为占位提示
  final String? suggestedName;

  /// 自动推断到的邮箱，作为占位提示
  final String? suggestedEmail;

  @override
  State<AuthorIdentityDialog> createState() => _AuthorIdentityDialogState();
}

class _AuthorIdentityDialogState extends State<AuthorIdentityDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _emailCtrl;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.controller.authorName);
    _emailCtrl = TextEditingController(text: widget.controller.authorEmail);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final email = _emailCtrl.text.trim();
    if (email.isNotEmpty && !_looksLikeEmail(email)) {
      setState(() => _error = '邮箱格式不对');
      return;
    }
    await widget.controller.setAuthorIdentity(
      name: _nameCtrl.text,
      email: email,
    );
    if (mounted) Navigator.of(context).pop();
  }

  /// 宽松校验：只挡住明显错的东西，不做完整 RFC 校验。
  /// 过于严格的正则会误杀合法地址，反而惹麻烦。
  bool _looksLikeEmail(String s) {
    final at = s.indexOf('@');
    if (at <= 0) return false;
    if (at == s.length - 1) return false;
    if (s.contains(' ')) return false;
    return s.substring(at + 1).contains('.');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final namePlaceholder =
        (widget.suggestedName ?? '').isEmpty ? 'GitHub 登录名' : widget.suggestedName!;
    final emailPlaceholder = (widget.suggestedEmail ?? '').isEmpty
        ? '自动推断的 noreply 地址'
        : widget.suggestedEmail!;

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpace.md,
        right: AppSpace.md,
        top: AppSpace.sm,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpace.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '提交作者',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpace.xs),
          Text(
            'GitHub 靠邮箱把提交关联到你的账号。邮箱不对的话，'
            '提交会显示成陌生名字，贡献格子也不会亮。',
            style: TextStyle(
              fontSize: 12,
              height: 1.55,
              color: c.textTertiary,
            ),
          ),
          const SizedBox(height: AppSpace.md),

          TextField(
            controller: _nameCtrl,
            decoration: InputDecoration(
              labelText: '作者名',
              hintText: namePlaceholder,
              helperText: '留空则用 GitHub 登录名',
              helperStyle: TextStyle(fontSize: 11, color: c.textTertiary),
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: '作者邮箱',
              hintText: emailPlaceholder,
              helperText: '留空则自动推断',
              helperStyle: TextStyle(fontSize: 11, color: c.textTertiary),
              errorText: _error,
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),

          const SizedBox(height: AppSpace.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    // 清空 = 恢复自动推断
                    await widget.controller.setAuthorIdentity(
                      name: '',
                      email: '',
                    );
                    if (context.mounted) Navigator.of(context).pop();
                  },
                  child: const Text('恢复自动'),
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: FilledButton(
                  onPressed: _save,
                  child: const Text('保存'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}