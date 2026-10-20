import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 站点文件读写的抽象。
///
/// 现在只有 App 私有目录一种实现；以后想接 SAF（Android）或
/// 外部目录，只要再加一个实现类，上层不用改。
abstract class SiteStorage {
  /// 站点根目录（git 工作区）
  Directory get root;

  /// 站点是否已存在（已经 clone 过）
  Future<bool> get exists;

  /// 相对路径是否存在
  Future<bool> existsPath(String relativePath);

  /// 读文本
  Future<String> readString(String relativePath);

  /// 写文本（自动建父目录）
  Future<void> writeString(String relativePath, String content);

  /// 删除
  Future<void> delete(String relativePath, {bool recursive = false});

  /// 递归列出目录下所有文件，返回**相对站点的路径**。
  ///
  /// Hugo 的 content 经常有子目录（content/posts/tech/a.md），
  /// 不递归会漏掉一大半文章。只保留递归版本，避免误用非递归接口。
  Future<List<String>> listFilesRecursive(
    String relativeDir, {
    String extension = '',
  });
}

/// App 私有目录实现。
///
/// 实际位置：`<应用私有目录>/sites/<siteId>/`
///
/// 选私有目录的原因：不需要任何存储权限，卸载即清理，git 操作不会
/// 被 scoped storage 干扰。
class AppPrivateStorage implements SiteStorage {
  AppPrivateStorage._(this.root);

  @override
  final Directory root;

  /// 打开（或创建）某个站点的存储
  static Future<AppPrivateStorage> open(String siteId) async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'sites', siteId));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return AppPrivateStorage._(dir);
  }

  @override
  Future<bool> get exists async => await root.exists();

  @override
  Future<bool> existsPath(String relativePath) async {
    final f = File(_abs(relativePath));
    final d = Directory(_abs(relativePath));
    return await f.exists() || await d.exists();
  }

  @override
  Future<String> readString(String relativePath) =>
      File(_abs(relativePath)).readAsString();

  @override
  Future<void> writeString(String relativePath, String content) async {
    final file = File(_abs(relativePath));
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
  }

  @override
  Future<void> delete(String relativePath, {bool recursive = false}) async {
    final f = File(_abs(relativePath));
    if (await f.exists()) {
      await f.delete();
      return;
    }
    final d = Directory(_abs(relativePath));
    if (await d.exists()) {
      await d.delete(recursive: recursive);
    }
  }

  @override
  Future<List<String>> listFilesRecursive(
    String relativeDir, {
    String extension = '',
  }) async {
    final dir = Directory(_abs(relativeDir));
    if (!await dir.exists()) return const [];

    final paths = <String>[];
    await for (final e in dir.list(followLinks: false, recursive: true)) {
      if (e is! File) continue;
      final name = p.basename(e.path);
      if (name.startsWith('.')) continue;
      if (extension.isNotEmpty && !name.endsWith(extension)) continue;
      // 转成相对站点根的路径，供 UI 与 Git 层共用
      paths.add(p.relative(e.path, from: root.path));
    }
    paths.sort();
    return paths;
  }

  String _abs(String relativePath) => p.join(root.path, relativePath);
}
