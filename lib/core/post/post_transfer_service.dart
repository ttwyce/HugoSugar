import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../fs/site_storage.dart';
import 'post_transfer.dart';
import '../site/site_controller.dart';

/// 导入时同名文件怎么处理。
enum ImportConflict {
  /// 跳过，保留仓库里原有的
  skip,

  /// 覆盖仓库里原有的
  overwrite,

  /// 存成 `name-2.md`
  rename,
}

/// 把「选文件 / 选保存位置 / 写进仓库」这些平台相关动作收在一处。
///
/// 为什么单独一层：PostTransfer 是纯逻辑能单测，
/// 而这里全是平台插件调用，测试环境跑不了。分开后，
/// 逻辑改动有测试兜底，插件调用只在真机上验证。
class PostTransferService {
  PostTransferService(this._site);

  final SiteController _site;

  /// 导出全部文章为 zip 并调起系统分享面板。
  ///
  /// 返回 null 表示用户取消或没有文章。
  Future<TransferReport> exportAll() async {
    final storage = _site.storage;
    final posts = _site.posts;
    if (storage == null) {
      return const TransferReport(ok: false, message: '站点尚未就绪');
    }
    if (posts.isEmpty) {
      return const TransferReport(ok: false, message: '没有可导出的文章');
    }

    // 用原始文件内容而不是重新序列化：
    // 重新序列化会丢掉用户手写的 Front Matter 顺序、注释和空行，
    // 导出应当是「原样备份」，不是「按我们的格式重写一遍」。
    final items = <String, String>{};
    final failed = <String, String>{};
    for (final post in posts) {
      try {
        final content = await storage.readString(post.relativePath);
        items[post.fileName] = content;
      } catch (e) {
        failed[post.fileName] = '$e';
      }
    }
    if (items.isEmpty) {
      return TransferReport(
        ok: false,
        message: '所有文章都读取失败',
        failed: failed,
      );
    }

    final bytes = PostTransfer.buildZip(items);
    final name = PostTransfer.exportFileName(DateTime.now());
    final tmp = await getTemporaryDirectory();
    final file = await PostTransfer.writeTempZip(tmp, bytes, name);

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/zip')],
      subject: 'HugoSugar 文章导出',
    );

    return TransferReport(
      ok: true,
      message: '已导出 ${items.length} 篇',
      succeeded: items.keys.toList(),
      failed: failed,
    );
  }

  /// 导出单篇为 .md 并分享。
  Future<TransferReport> exportOne(String relativePath, String fileName) async {
    final storage = _site.storage;
    if (storage == null) {
      return const TransferReport(ok: false, message: '站点尚未就绪');
    }
    try {
      final content = await storage.readString(relativePath);
      final tmp = await getTemporaryDirectory();
      await tmp.create(recursive: true);
      final file = File(p.join(tmp.path, fileName));
      await file.writeAsString(content, flush: true);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/markdown')],
        subject: fileName,
      );
      return TransferReport(
        ok: true,
        message: '已导出 $fileName',
        succeeded: [fileName],
      );
    } catch (e) {
      return TransferReport(
        ok: false,
        message: '导出失败：$e',
        failed: {fileName: '$e'},
      );
    }
  }

  /// 让用户挑一个 zip 或 md，然后导入。
  ///
  /// [conflict] 决定同名怎么办。默认跳过：
  /// 导入的常见场景是「从旧手机/旧备份恢复几篇」，
  /// 此时仓库里已有的版本通常更新，覆盖是更危险的选择。
  Future<TransferReport?> pickAndImport({
    ImportConflict conflict = ImportConflict.skip,
  }) async {
    final storage = _site.storage;
    if (storage == null) {
      return const TransferReport(ok: false, message: '站点尚未就绪');
    }

    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip', 'md', 'markdown', 'txt'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return null;

    final f = picked.files.first;
    final bytes = f.bytes ?? await _readPath(f.path);
    if (bytes == null) {
      return const TransferReport(ok: false, message: '读取文件失败');
    }

    final lower = (f.name).toLowerCase();
    final Map<String, String> incoming;
    if (lower.endsWith('.zip')) {
      try {
        incoming = PostTransfer.readZip(bytes);
      } catch (e) {
        return TransferReport(ok: false, message: '压缩包损坏或格式不支持：$e');
      }
    } else {
      final text = PostTransfer.decodeSingle(bytes);
      if (text == null) {
        return const TransferReport(ok: false, message: '文件不是 UTF-8 文本');
      }
      incoming = {f.name: text};
    }

    if (incoming.isEmpty) {
      return const TransferReport(ok: false, message: '文件里没有找到 .md 文章');
    }

    return _writeIntoRepo(storage, PostTransfer.dedupe(incoming), conflict);
  }

  Future<Uint8List?> _readPath(String? path) async {
    if (path == null) return null;
    try {
      return await File(path).readAsBytes();
    } catch (_) {
      return null;
    }
  }

  /// 真正落盘。逐篇写，单篇失败不影响其余。
  Future<TransferReport> _writeIntoRepo(
    SiteStorage storage,
    Map<String, String> items,
    ImportConflict conflict,
  ) async {
    final dir = _site.postsDir;
    final succeeded = <String>[];
    final failed = <String, String>{};
    final skipped = <String, String>{};

    for (final e in items.entries) {
      var name = e.key;
      try {
        var target = '$dir/$name';

        if (await storage.existsPath(target)) {
          switch (conflict) {
            case ImportConflict.skip:
              skipped[name] = '已存在，已跳过';
              continue;
            case ImportConflict.overwrite:
              break;
            case ImportConflict.rename:
              target = await _uniquePath(storage, dir, name);
          }
        }

        await storage.writeString(target, e.value);
        succeeded.add(p.posix.basename(target));
      } catch (err) {
        failed[name] = '$err';
      }
    }

    // 导完必须刷新，否则列表还是旧的
    await _site.refresh();

    final ok = failed.isEmpty;
    final parts = <String>[];
    if (succeeded.isNotEmpty) parts.add('导入 ${succeeded.length} 篇');
    if (skipped.isNotEmpty) parts.add('跳过 ${skipped.length} 篇');
    if (failed.isNotEmpty) parts.add('失败 ${failed.length} 篇');

    return TransferReport(
      ok: ok,
      message: parts.isEmpty ? '没有变化' : parts.join('，'),
      succeeded: succeeded,
      failed: failed,
      skipped: skipped,
    );
  }

  /// 找一个没被占用的文件名：`a.md` -> `a-2.md` -> `a-3.md`
  Future<String> _uniquePath(SiteStorage storage, String dir, String name) async {
    final base = p.posix.basenameWithoutExtension(name);
    final ext = p.posix.extension(name);
    var i = 2;
    while (true) {
      final candidate = '$dir/$base-$i$ext';
      if (!await storage.existsPath(candidate)) return candidate;
      i++;
    }
  }
}

/// 供 UI 层判断能否导出（纯展示用，不碰插件）。
@immutable
class TransferAvailability {
  const TransferAvailability({required this.canTransfer, required this.reason});
  final bool canTransfer;
  final String reason;
}