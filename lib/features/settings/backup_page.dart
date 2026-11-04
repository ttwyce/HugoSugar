import 'package:flutter/material.dart';

import '../../app/i18n/l10n_scope.dart';
import '../../app/theme/app_colors.dart';
import '../../core/backup/backup_config.dart';
import '../../core/backup/backup_service.dart';
import '../../core/note/note_controller.dart';
import '../../shared/widgets.dart';

/// 想法备份（WebDAV + 客户端加密）设置页。
///
/// 三个分区的顺序是有意的：
/// 1. 服务器 —— 先能连上
/// 2. 口令 —— 再决定用什么加密
/// 3. 操作 —— 最后才是备份/恢复
///
/// 顺序反过来会让用户在没配好服务器时点备份，得到一串没意义的报错。
class BackupPage extends StatefulWidget {
  const BackupPage({super.key, required this.noteController});

  final NoteController noteController;

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  final _serverCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _pwdCtrl = TextEditingController();
  final _dirCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  BackupConfigStore? _store;
  BackupConfig _config = const BackupConfig();
  bool _loading = true;
  bool _busy = false;
  bool _obscurePwd = true;
  bool _obscurePass = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _serverCtrl.dispose();
    _userCtrl.dispose();
    _pwdCtrl.dispose();
    _dirCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final store = await BackupConfigStore.open();
    final config = await store.load();
    if (!mounted) return;
    setState(() {
      _store = store;
      _config = config;
      _serverCtrl.text = config.serverUrl;
      _userCtrl.text = config.username;
      _pwdCtrl.text = config.password;
      _dirCtrl.text = config.remoteDir;
      _passCtrl.text = config.passphrase;
      _confirmCtrl.text = config.passphrase;
      _loading = false;
    });
  }

  // ── 保存 ────────────────────────────────────────────

  /// 校验表单并落盘。校验失败返回 null（已弹提示）。
  Future<BackupConfig?> _persist({
    bool? autoDaily,
    bool? rememberPassphrase,
    bool? allowBadCertificate,
    bool? allowInsecureHttp,
  }) async {
    final server = _serverCtrl.text.trim();
    if (server.isNotEmpty &&
        !server.toLowerCase().startsWith('http://') &&
        !server.toLowerCase().startsWith('https://')) {
      _snack(T('服务器地址要填完整，以 https:// 开头'));
      return null;
    }

    final pass = _passCtrl.text;
    if (pass.isNotEmpty) {
      if (pass.length < BackupService.minPassphraseLength) {
        _snack(T('备份口令至少 10 位'));
        return null;
      }
      if (pass != _confirmCtrl.text) {
        _snack(T('两次输入的口令不一致'));
        return null;
      }
    }

    final remember = rememberPassphrase ?? _config.rememberPassphrase;
    if (remember && pass.isEmpty) {
      // 勾了「记住」却没有口令可记：自动备份会因缺口令永远不执行，
      // 与其让用户以为开了，不如当面拦住
      _snack(T('请先设置备份口令'));
      return null;
    }
    final dir = _dirCtrl.text.trim();
    final config = _config.copyWith(
      serverUrl: server,
      username: _userCtrl.text.trim(),
      password: _pwdCtrl.text,
      remoteDir: dir.isEmpty ? 'HugoSugar' : dir,
      // 不勾「记住口令」时，口令只存在于本次输入框里，不落盘
      passphrase: remember ? pass : '',
      rememberPassphrase: remember,
      autoDaily: autoDaily,
      allowBadCertificate: allowBadCertificate,
      allowInsecureHttp: allowInsecureHttp,
    );
    await _store?.save(config);
    if (mounted) setState(() => _config = config);
    return config;
  }

  BackupService _service(BackupConfig config) => BackupService(
        store: widget.noteController.store,
        config: config,
      );

  // ── 动作 ────────────────────────────────────────────

  Future<void> _testConnection() async {
    final config = await _persist();
    if (config == null) return;
    setState(() => _busy = true);
    final error = await _service(config).testConnection();
    if (!mounted) return;
    setState(() => _busy = false);
    _snack(error ?? T('连接成功'));
  }

  Future<void> _backupNow() async {
    final config = await _persist();
    if (config == null) return;
    final passphrase = _passCtrl.text;
    if (passphrase.isEmpty) {
      _snack(T('请先设置备份口令'));
      return;
    }

    setState(() => _busy = true);
    final outcome = await _service(config).backupNow(passphrase: passphrase);
    if (!mounted) return;
    setState(() => _busy = false);

    if (!outcome.ok) {
      _snack(outcome.message ?? T('备份失败'));
      return;
    }

    final updated = config.copyWith(
      lastBackupAt: DateTime.now(),
      lastBackupNoteCount: outcome.noteCount,
    );
    await _store?.save(updated);
    if (!mounted) return;
    setState(() => _config = updated);
    _snack(
      TP('备份成功：{} 条想法，{}', [
        outcome.noteCount,
        _formatBytes(outcome.bytes),
      ]),
    );
  }

  Future<void> _restore() async {
    final config = await _persist();
    if (config == null) return;
    final passphrase = _passCtrl.text;
    if (passphrase.isEmpty) {
      _snack(T('请先输入备份口令'));
      return;
    }

    // 先只读元数据：解密失败在这里就拦住，不会动本地数据
    setState(() => _busy = true);
    final peek = await _service(config).peek(passphrase: passphrase);
    if (!mounted) return;
    setState(() => _busy = false);

    final preview = peek.preview;
    if (preview == null) {
      _snack(peek.error ?? T('读取备份失败'));
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr(T('从备份恢复'))),
        content: Text(
          TP('备份时间：{}\n活跃想法 {} 条，回收站 {} 条，分类 {} 个\n\n将与本地合并：同一条取较新的版本，本地独有的想法会保留。', [
            _formatTime(preview.exportedAt),
            preview.noteCount,
            preview.trashedCount,
            preview.categoryCount,
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(ctx.tr(T('取消'))),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(ctx.tr(T('合并'))),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    final outcome = await _service(config).restoreMerge(passphrase: passphrase);
    if (!mounted) return;
    setState(() => _busy = false);

    if (!outcome.ok) {
      _snack(outcome.message ?? T('恢复失败'));
      return;
    }
    // 合并直接改了 NoteStore，需要让页面重建列表
    widget.noteController.notifyExternalChange();
    final report = outcome.report;
    _snack(
      report == null
          ? T('恢复完成')
          : TP('恢复完成：新增 {} 条，更新 {} 条，保留本地较新 {} 条', [
              report.added,
              report.updated,
              report.kept,
            ]),
    );
  }

  // ── 渲染 ────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr(T('想法备份')))),
      body: _loading
          ? const SizedBox.shrink()
          : ListView(
              padding: const EdgeInsets.only(bottom: 40),
              children: [
                if (_busy) const LinearProgressIndicator(minHeight: 2),
                _introCard(),
                SectionHeader(context.tr(T('WebDAV 服务器'))),
                _field(
                  label: T('服务器地址'),
                  controller: _serverCtrl,
                  hint: 'https://dav.jianguoyun.com/dav',
                  helper: T('填 WebDAV 根地址，不是网页登录地址'),
                ),
                _field(
                  label: T('账号'),
                  controller: _userCtrl,
                  helper: T('多数网盘用邮箱'),
                ),
                _field(
                  label: T('密码'),
                  controller: _pwdCtrl,
                  obscure: _obscurePwd,
                  onToggleObscure: () =>
                      setState(() => _obscurePwd = !_obscurePwd),
                  helper: T('这是 WebDAV 账号密码，不是下方用于加密的备份口令'),
                ),
                _field(
                  label: T('远端目录'),
                  controller: _dirCtrl,
                  hint: 'HugoSugar',
                  helper: T('不存在会自动创建'),
                ),
                SwitchListTile(
                  value: _config.allowBadCertificate,
                  onChanged: (v) => _persist(allowBadCertificate: v),
                  secondary: const Icon(Icons.verified_user_outlined, size: 20),
                  title: Text(context.tr(T('允许自签证书'))),
                  subtitle: Text(
                    T('群晖、自建服务器常用自签证书。打开后才连得上，但无法验证服务器身份'),
                    style: TextStyle(
                      fontSize: 12,
                      color: context.appColors.textTertiary,
                    ),
                  ),
                ),
                SwitchListTile(
                  value: _config.allowInsecureHttp,
                  onChanged: (v) => _persist(allowInsecureHttp: v),
                  secondary: Icon(
                    Icons.warning_amber_outlined,
                    size: 20,
                    color: context.appColors.warning,
                  ),
                  title: Text(context.tr(T('允许明文连接（http）'))),
                  subtitle: Text(
                    T('警告：密码和备份文件会在链路上裸奔。除非走内网，否则不要打开'),
                    style: TextStyle(
                      fontSize: 12,
                      color: context.appColors.warning,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpace.md,
                    AppSpace.sm,
                    AppSpace.md,
                    0,
                  ),
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _testConnection,
                    icon: const Icon(Icons.wifi_tethering, size: 18),
                    label: Text(context.tr(T('测试连接'))),
                  ),
                ),

                SectionHeader(context.tr(T('加密口令'))),
                _field(
                  label: T('备份口令'),
                  controller: _passCtrl,
                  hint: T('至少 10 位'),
                  obscure: _obscurePass,
                  onToggleObscure: () =>
                      setState(() => _obscurePass = !_obscurePass),
                  helper: T('想法在手机上压缩并加密后才上传，服务器只能看到密文'),
                ),
                _field(
                  label: T('再输一次'),
                  controller: _confirmCtrl,
                  obscure: _obscurePass,
                  helper: T('口令不会被上传。忘记后云端备份无法恢复，请自己另存一份'),
                ),
                SwitchListTile(
                  value: _config.rememberPassphrase,
                  onChanged: (v) => _persist(rememberPassphrase: v),
                  secondary: const Icon(Icons.key_outlined, size: 20),
                  title: Text(context.tr(T('记住口令'))),
                  subtitle: Text(
                    T('以 0600 权限存在应用私有目录，用于每日自动备份。不勾选则每次都要手输'),
                    style: TextStyle(
                      fontSize: 12,
                      color: context.appColors.textTertiary,
                    ),
                  ),
                ),

                SectionHeader(context.tr(T('自动备份'))),
                SwitchListTile(
                  value: _config.autoDaily,
                  onChanged: (v) => _persist(autoDaily: v),
                  secondary: const Icon(Icons.schedule, size: 20),
                  title: Text(context.tr(T('每天自动备份'))),
                  subtitle: Text(
                    _config.rememberPassphrase
                        ? T('打开 App 时检查，距上次超过 23 小时就备份一次')
                        : T('需要先打开「记住口令」，否则自动备份时没有口令可用'),
                    style: TextStyle(
                      fontSize: 12,
                      color: context.appColors.textTertiary,
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.history, size: 20),
                  title: Text(context.tr(T('上次备份'))),
                  subtitle: Text(
                    _config.lastBackupAt == null
                        ? T('从未备份')
                        : TP('{} · {} 条想法', [
                            _formatTime(_config.lastBackupAt!),
                            _config.lastBackupNoteCount,
                          ]),
                  ),
                ),

                SectionHeader(context.tr(T('操作'))),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpace.md,
                    AppSpace.xs,
                    AppSpace.md,
                    0,
                  ),
                  child: Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _busy ? null : _backupNow,
                          icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                          label: Text(context.tr(T('立即备份'))),
                        ),
                      ),
                      const SizedBox(height: AppSpace.sm),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : _restore,
                          icon: const Icon(Icons.cloud_download_outlined,
                              size: 18),
                          label: Text(context.tr(T('从备份恢复'))),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _introCard() {
    final c = context.appColors;
    return Container(
      margin: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.md, AppSpace.md, 0),
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline, size: 18, color: c.accent),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text(
              T('备份内容是先在手机上 gzip 压缩、再用你的口令做 AES-256-GCM 加密的结果。'
                  'WebDAV 服务器和中间链路都只能看到密文，文件名固定、不暴露条数。'),
              style: TextStyle(
                fontSize: 13,
                height: 1.6,
                color: c.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    String? hint,
    String? helper,
    bool obscure = false,
    VoidCallback? onToggleObscure,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.md, 6, AppSpace.md, 6),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          helperText: helper,
          helperMaxLines: 3,
          suffixIcon: onToggleObscure == null
              ? null
              : IconButton(
                  icon: Icon(
                    obscure ? Icons.visibility_off : Icons.visibility,
                    size: 18,
                  ),
                  onPressed: onToggleObscure,
                ),
        ),
      ),
    );
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String _formatTime(DateTime time) {
    final local = time.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}
