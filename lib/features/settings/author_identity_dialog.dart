import 'package:flutter/material.dart';
import 'package:hugosugar/app/i18n/l10n_scope.dart';

import '../../app/theme/app_colors.dart';
import '../../core/settings/settings_controller.dart';
import 'author_suggestion.dart';

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
    this.suggestions,
    this.required = false,
  });

  final SettingsController controller;

  /// 自动推断结果的 Future。
  ///
  /// 传 **Future 而不是已解析的值**，是为了让弹窗立刻出现：
  /// 这个查询要走两次 GitHub API，网络慢时可能要几秒甚至超时。
  /// 它只影响输入框的灰色占位提示，绝不该阻塞用户输入。
  /// 未来完成时会自动刷新占位文案；用户可能早就填完保存了，
  /// 那种情况下这个值直接被丢弃，不会造成任何影响。
  final Future<AuthorSuggestion?>? suggestions;

  /// 是否为「必须填写」模式。
  ///
  /// 首次用令牌登录时，如果自动获取账号资料失败，就没有任何可用的
  /// 作者身份 —— 此时必须让用户填完才能继续，否则后续每次提交都会
  /// 落到 `noreply@localhost` 这种不关联账号的身份上，而且用户
  /// 完全不知道原因。
  ///
  /// 开启后：
  /// - 隐藏「恢复自动」按钮（没有自动可用）
  /// - 名和邮箱都必填
  /// - 不允许通过返回键 / 点击遮罩关闭
  final bool required;

  @override
  State<AuthorIdentityDialog> createState() => _AuthorIdentityDialogState();
}

class _AuthorIdentityDialogState extends State<AuthorIdentityDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _emailCtrl;
  String? _error;

  /// 推断结果，回来之前是 null（显示通用占位文案）
  AuthorSuggestion? _suggestion;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.controller.authorName);
    _emailCtrl = TextEditingController(text: widget.controller.authorEmail);

    // 不 await，让 UI 先渲染出来。回来时如果用户已经关掉弹窗，
    // then 里查 mounted 直接跳过。
    //
    // 注意 `Completer` 已经完成的情况：then 会**同步**执行，
    // 此时还是 initState 阶段，直接 setState 会抛
    // "setState() called during build"。所以先只赋值，
    // 只在需要时（已挂载且已过首帧）才 setState。
    widget.suggestions?.then((s) {
      if (!mounted || s == null) return;
      setState(() => _suggestion = s);
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();

    // 必填模式下两个都要有，且邮箱格式要正确。
    // 这里不用「留空则自动推断」那套，因为自动推断已经失败过了，
    // 留空等于让用户带着一个不关联账号的身份去做提交。
    if (widget.required) {
      if (name.isEmpty) {
        setState(() => _error = T('请填写作者名'));
        return;
      }
      if (email.isEmpty) {
        setState(() => _error = T('请填写作者邮箱'));
        return;
      }
    }

    if (email.isNotEmpty && !_looksLikeEmail(email)) {
      setState(() => _error = T('邮箱格式不对'));
      return;
    }

    await widget.controller.setAuthorIdentity(name: name, email: email);
    if (mounted) Navigator.of(context).pop(true);
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
    final s = _suggestion;

    // 注意：这里必须用 helperText 而不是 hintText 来展示建议值。
    // Material 的 hintText 只在「输入框为空 **且** 处于聚焦状态」时显示，
    // 而 labelText 在未聚焦时会浮在框内挡住它 —— 结果就是用户根本
    // 看不到建议值。helperText 则始终显示在输入框下方。
    final nameHelper = widget.required
        ? T('必填')
        : (s?.name ?? '').isEmpty
        ? T('留空则用 GitHub 登录名')
        : TP('留空则用 {}', [s!.name]);
    final emailHelper = widget.required
        ? T('必填，用于把提交关联到你的 GitHub 账号')
        : (s?.email ?? '').isEmpty
        ? T('留空则自动推断')
        : TP('留空则用 {}', [s!.email]);

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
            context.tr(T('提交作者')),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpace.xs),
          Text(
            T('GitHub 靠邮箱把提交关联到你的账号。邮箱不对的话，提交会显示成陌生名字，贡献格子也不会亮。'),
            style: TextStyle(fontSize: 12, height: 1.55, color: c.textTertiary),
          ),
          const SizedBox(height: AppSpace.md),

          TextField(
            controller: _nameCtrl,
            decoration: InputDecoration(
              labelText: context.tr(T('作者名')),
              helperText: nameHelper,
              helperMaxLines: 2,
              helperStyle: TextStyle(fontSize: 11, color: c.textTertiary),
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: context.tr(T('作者邮箱')),
              helperText: emailHelper,
              helperMaxLines: 2,
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
              if (!widget.required) ...[
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
                    child: Text(context.tr(T('恢复自动'))),
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
              ],
              Expanded(
                child: FilledButton(
                  onPressed: _save,
                  child: Text(widget.required ? T('继续') : T('保存')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
