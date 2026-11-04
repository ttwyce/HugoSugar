import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// WebDAV 备份配置。
///
/// ## 口令为什么允许记住
///
/// 备份口令是唯一能解开云端文件的东西。如果每次备份都要手输 20 位，
/// 「每日自动备份」就没法成立 —— 后台没人替你输。
/// 所以提供 [rememberPassphrase]：默认关闭，用户主动勾选后
/// 以 0600 权限存在应用私有目录。
///
/// 风险边界：拿到「已解锁设备 + root 权限」的人能读到口令。
/// 这与 TokenStore 存 GitHub PAT 的风险面完全一致，不再额外放大。
class BackupConfig {
  const BackupConfig({
    this.serverUrl = '',
    this.username = '',
    this.password = '',
    this.remoteDir = 'HugoSugar',
    this.autoDaily = true,
    this.rememberPassphrase = false,
    this.passphrase = '',
    this.allowBadCertificate = false,
    this.allowInsecureHttp = false,
    this.lastBackupAt,
    this.lastBackupNoteCount = 0,
  });

  /// WebDAV 根地址，例如 `https://dav.jianguoyun.com/dav`。
  final String serverUrl;
  final String username;
  final String password;

  /// 远端目录（相对根地址）。默认 `HugoSugar`。
  final String remoteDir;

  /// 是否每天自动备份一次（App 前台启动时检查）。
  final bool autoDaily;

  /// 是否记住备份口令。
  final bool rememberPassphrase;

  /// 记住的备份口令。未勾选 [rememberPassphrase] 时应始终为空。
  final String passphrase;

  /// 是否接受自签证书。
  final bool allowBadCertificate;

  /// 是否允许明文 HTTP。
  ///
  /// 与 [allowBadCertificate] 分开：自签证书仍然是加密传输，
  /// 而明文 HTTP 会把 WebDAV 密码和备份密文都暴露在链路上。
  /// 两个风险等级不同，不能共用一个开关。
  final bool allowInsecureHttp;

  /// 上次成功备份的时间。
  final DateTime? lastBackupAt;

  /// 上次成功备份包含的想法条数，用于在设置页展示。
  final int lastBackupNoteCount;

  /// 配置是否完整到足以发起备份。
  bool get isConfigured =>
      serverUrl.trim().isNotEmpty && username.trim().isNotEmpty;

  /// 能否在无人值守时自动备份（需要已记住口令）。
  bool get canAutoBackup =>
      isConfigured && autoDaily && rememberPassphrase && passphrase.isNotEmpty;

  BackupConfig copyWith({
    String? serverUrl,
    String? username,
    String? password,
    String? remoteDir,
    bool? autoDaily,
    bool? rememberPassphrase,
    String? passphrase,
    bool? allowBadCertificate,
    bool? allowInsecureHttp,
    DateTime? lastBackupAt,
    int? lastBackupNoteCount,
  }) {
    return BackupConfig(
      serverUrl: serverUrl ?? this.serverUrl,
      username: username ?? this.username,
      password: password ?? this.password,
      remoteDir: remoteDir ?? this.remoteDir,
      autoDaily: autoDaily ?? this.autoDaily,
      rememberPassphrase: rememberPassphrase ?? this.rememberPassphrase,
      passphrase: passphrase ?? this.passphrase,
      allowBadCertificate: allowBadCertificate ?? this.allowBadCertificate,
      allowInsecureHttp: allowInsecureHttp ?? this.allowInsecureHttp,
      lastBackupAt: lastBackupAt ?? this.lastBackupAt,
      lastBackupNoteCount: lastBackupNoteCount ?? this.lastBackupNoteCount,
    );
  }

  Map<String, Object?> toJson() => {
        'serverUrl': serverUrl,
        'username': username,
        'password': password,
        'remoteDir': remoteDir,
        'autoDaily': autoDaily,
        'rememberPassphrase': rememberPassphrase,
        'passphrase': rememberPassphrase ? passphrase : '',
        'allowBadCertificate': allowBadCertificate,
        'allowInsecureHttp': allowInsecureHttp,
        'lastBackupAt': lastBackupAt?.toIso8601String(),
        'lastBackupNoteCount': lastBackupNoteCount,
      };

  static BackupConfig fromJson(Map<String, Object?> j) {
    final remember = j['rememberPassphrase'] as bool? ?? false;
    final remoteDir = (j['remoteDir'] as String?)?.trim() ?? '';
    return BackupConfig(
      serverUrl: j['serverUrl'] as String? ?? '',
      username: j['username'] as String? ?? '',
      password: j['password'] as String? ?? '',
      remoteDir: remoteDir.isEmpty ? 'HugoSugar' : remoteDir,
      autoDaily: j['autoDaily'] as bool? ?? true,
      rememberPassphrase: remember,
      // 不记住时即使文件里残留了旧口令也丢掉，避免「关掉开关仍然落盘」
      passphrase: remember ? (j['passphrase'] as String? ?? '') : '',
      allowBadCertificate: j['allowBadCertificate'] as bool? ?? false,
      allowInsecureHttp: j['allowInsecureHttp'] as bool? ?? false,
      lastBackupAt: DateTime.tryParse(j['lastBackupAt'] as String? ?? ''),
      lastBackupNoteCount: (j['lastBackupNoteCount'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 读写 `backup/config.json`，权限 0600。
///
/// 与 [TokenStore] 同一套权限模型：先建文件 → 收紧权限 → 再写内容，
/// 避免「写完内容后有一小段时间是默认权限」的窗口。
class BackupConfigStore {
  BackupConfigStore(this._file);

  final File _file;

  static Future<BackupConfigStore> open() async {
    final dir = await getApplicationSupportDirectory();
    return BackupConfigStore(File('${dir.path}/backup/config.json'));
  }

  Future<BackupConfig> load() async {
    try {
      if (!await _file.exists()) return const BackupConfig();
      final raw = await _file.readAsString();
      if (raw.trim().isEmpty) return const BackupConfig();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const BackupConfig();
      return BackupConfig.fromJson(Map<String, Object?>.from(decoded));
    } catch (_) {
      // 配置损坏不影响 App 启动，当作未配置
      return const BackupConfig();
    }
  }

  Future<void> save(BackupConfig config) async {
    try {
      await _file.parent.create(recursive: true);
      if (!await _file.exists()) {
        await _file.create(recursive: false);
      }
      await _restrictPermissions();
      await _file.writeAsString(jsonEncode(config.toJson()), flush: true);
      // 写完后可能因编辑器/重命名语义丢失权限，再收紧一次
      await _restrictPermissions();
    } catch (_) {
      // 写失败不致命，下次再写
    }
  }

  Future<void> _restrictPermissions() async {
    try {
      // Dart 没有 chmod API；Android 上由 toybox 提供
      await Process.run('chmod', ['600', _file.path]);
    } catch (_) {
      // 失败就退回平台默认权限，不阻断主流程
    }
  }
}
