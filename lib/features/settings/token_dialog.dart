import 'package:flutter/material.dart';
import 'package:hugosugar/app/i18n/l10n_scope.dart';

import '../../app/theme/app_colors.dart';
import '../../core/site/github_api.dart';
import '../../core/site/token_store.dart';

/// 令牌状态的只读快照，供设置页副标题展示。
class TokenMask {
  const TokenMask({required this.hasToken, this.masked});

  final bool hasToken;

  /// 形如 `ghp_ab••••••xyz9`；无令牌时为 null
  final String? masked;
}

/// 读取当前保存的令牌（打码后）。
///
/// 单独抽出来是因为设置页是 AnimatedBuilder 驱动的，
/// 需要能同步拿一个「已知状态」来渲染副标题。
Future<TokenMask> loadTokenMask() async {
  final store = await TokenStore.open();
  final t = await store.read();
  if (t == null) return const TokenMask(hasToken: false);
  return TokenMask(hasToken: true, masked: maskToken(t));
}

/// 把令牌打码成可展示的短串。
///
/// 保留前 6 位（足以认出是哪个令牌）和后 4 位（便于核对），
/// 中间一律用圆点，避免截图泄露完整凭据。
String maskToken(String t) {
  if (t.length <= 10) return '••••••';
  final head = t.substring(0, 6);
  final tail = t.substring(t.length - 4);
  return '$head••••$tail';
}

/// GitHub 令牌管理对话框。
///
/// 这是**全 App 唯一的令牌入口**：站点接入、推送页、设置页都读同一份
/// 存储（TokenStore）。这里改完，其他地方立刻生效。
class TokenDialog extends StatefulWidget {
  const TokenDialog({super.key});

  @override
  State<TokenDialog> createState() => _TokenDialogState();
}

class _TokenDialogState extends State<TokenDialog> {
  final _ctrl = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _savedMask;
  String? _error;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = await TokenStore.open();
    final t = await store.read();
    if (!mounted) return;
    setState(() => _savedMask = t == null ? null : maskToken(t));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.md,
            AppSpace.sm,
            AppSpace.md,
            AppSpace.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    context.tr(T('GitHub 访问令牌')),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: c.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _busy ? null : _save,
                    child: Text(_busy ? T('校验中…') : T('保存')),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.xs),
              Text(
                context.tr(T('整个 App 只需要填这一次。站点接入和推送都会自动复用。')),
                style: TextStyle(
                  fontSize: 12,
                  height: 1.6,
                  color: c.textTertiary,
                ),
              ),
              const SizedBox(height: AppSpace.sm),

              if (_savedMask != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: AppSpace.sm),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 16,
                        color: c.accent,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          TP('已保存：{}', [_savedMask]),
                          style: TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                            color: c.textSecondary,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _busy ? null : _clear,
                        style: TextButton.styleFrom(
                          foregroundColor: c.danger,
                          visualDensity: VisualDensity.compact,
                        ),
                        child: Text(
                          context.tr(T('清除')),
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),

              TextField(
                controller: _ctrl,
                obscureText: _obscure,
                autocorrect: false,
                enableSuggestions: false,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: context.tr(T('ghp_... 或 github_pat_...')),
                  hintStyle: TextStyle(fontSize: 13, color: c.textTertiary),
                  helperText: T('需要 repo 权限（读写仓库内容）'),
                  helperStyle: TextStyle(fontSize: 11, color: c.textTertiary),
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
                      _obscure
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 18,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(fontSize: 12, height: 1.5, color: c.danger),
                ),
              ],
              if (_notice != null) ...[
                const SizedBox(height: 8),
                Text(
                  _notice!,
                  style: TextStyle(fontSize: 12, height: 1.5, color: c.accent),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    final token = _ctrl.text.trim();
    if (token.isEmpty) {
      setState(() => _error = T('请输入令牌'));
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });

    // 真正的校验：调 GitHub /user。存一个错令牌比不存更糟 ——
    // 用户会以为配好了，直到推送时才失败。
    try {
      final api = GitHubApi();
      final login = await api.validateToken(token);
      api.dispose();
      final store = await TokenStore.open();
      await store.write(token);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _savedMask = maskToken(token);
        _ctrl.clear();
        _notice = TP('已验证为 {}，已保存', [login]);
      });
    } on GitHubException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.hint == null ? e.message : '${e.message}\n${e.hint}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  Future<void> _clear() async {
    final store = await TokenStore.open();
    await store.clear();
    if (!mounted) return;
    setState(() {
      _savedMask = null;
      _notice = T('已清除令牌');
    });
  }
}
