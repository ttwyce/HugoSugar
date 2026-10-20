import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// GitHub PAT 的本地存储。
///
/// **为什么不用 flutter_secure_storage**：
/// 它是原生插件（Android Keystore / iOS Keychain），引入后需要在
/// ARM64 proot 环境里重新跑一遍原生构建链；而本项目已经在这个环节
/// 踩过 NDK/clang 的坑（见 docs/ARM64_BUILD_TROUBLESHOOTING.md）。
/// 权衡下来，用「应用私有目录 + 0600 权限」足够：
/// - 路径在 `/data/data/<应用包名>/` 下，非 root 设备其他 App 读不到
/// - 文件权限 0600，同用户下其他进程也读不到
/// - 明文存储的风险面等于「设备被 root」这个前提
///
/// 如果以后要上 secure_storage，只需替换这个类的实现，
/// 调用方（SiteController / 页面）不用改。
class TokenStore {
  TokenStore(this._file);

  final File _file;

  static Future<TokenStore> open() async {
    final dir = await getApplicationSupportDirectory();
    return TokenStore(File('${dir.path}/token'));
  }

  Future<String?> read() async {
    try {
      if (!await _file.exists()) return null;
      final s = (await _file.readAsString()).trim();
      return s.isEmpty ? null : s;
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String token) async {
    final t = token.trim();
    if (t.isEmpty) return;
    try {
      await _file.parent.create(recursive: true);
      // 先建文件再收紧权限，最后才写内容 ——
      // 避免「写完内容后还有一段时间是默认权限」的窗口期
      if (!await _file.exists()) {
        await _file.create(recursive: false);
      }
      await _restrictPermissions();
      await _file.writeAsString(t, flush: true);
    } catch (_) {
      // 写失败不致命：用户下次需要重新输入 token
    }
  }

  Future<void> clear() async {
    try {
      if (await _file.exists()) await _file.delete();
    } catch (_) {
      // 忽略
    }
  }

  Future<void> _restrictPermissions() async {
    // Dart 没有 chmod API，只能走系统命令。
    // Android 上 chmod 由 toybox 提供，存在且可用。
    try {
      await Process.run('chmod', ['600', _file.path]);
    } catch (_) {
      // 失败就退回默认权限，不阻断主流程
    }
  }
}