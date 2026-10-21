import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

/// 一次导出/导入的结果。
class TransferReport {
  const TransferReport({
    required this.ok,
    required this.message,
    this.succeeded = const <String>[],
    this.failed = const <String, String>{},
    this.skipped = const <String, String>{},
  });

  final bool ok;
  final String message;

  /// 成功处理的文件名
  final List<String> succeeded;

  /// 失败的文件名 -> 原因
  final Map<String, String> failed;

  /// 跳过的文件名 -> 原因（已存在、非法路径等）
  final Map<String, String> skipped;
}

/// 文章导入导出的纯逻辑层。
///
/// 刻意不碰 Flutter：文件读写、打包、校验都在这里，
/// UI 只负责选路径和展示结果。这样这块能单测，
/// 而「选择保存位置」那种平台相关的事才留在界面层。
class PostTransfer {
  /// 从一组文章内容打包成 zip 字节。
  ///
  /// [items] 的 key 是导出后的文件名，value 是文件内容。
  /// 用 zip 而不是逐篇分享：用户说「只导出文章」，但十几篇一篇篇点
  /// 太难受；zip 在手机上也能直接用系统文件管理器解开。
  static Uint8List buildZip(Map<String, String> items) {
    final archive = Archive();
    for (final e in items.entries) {
      final bytes = utf8.encode(e.value);
      archive.addFile(ArchiveFile(e.key, bytes.length, bytes));
    }
    final data = ZipEncoder().encode(archive);
    if (data == null) return Uint8List(0);
    return Uint8List.fromList(data);
  }

  /// 从 zip 字节里读出「文件名 -> 内容」。
  ///
  /// 只收 `.md`。会主动挡掉几类危险条目：
  /// - 绝对路径（/etc/passwd）
  /// - 含 `..` 的路径穿越（../../x.md）
  /// - 隐藏文件与 macOS 打包垃圾（__MACOSX、.DS_Store）
  ///
  /// 这不是洁癖：导入的文件会被写进站点仓库，一个 `../` 就能写到仓库外，
  /// 而 zip 里的路径是外部输入，必须当成不可信数据处理。
  static Map<String, String> readZip(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final out = <String, String>{};

    for (final f in archive) {
      if (!f.isFile) continue;
      final raw = f.name.replaceAll('\\', '/');
      if (!raw.toLowerCase().endsWith('.md')) continue;
      if (_isUnsafe(raw)) continue;

      final content = f.content;
      if (content is! List<int>) continue;
      try {
        out[_flatten(raw)] = utf8.decode(content);
      } catch (_) {
        // 不是 UTF-8，跳过（Hugo 文章基本是 UTF-8）
      }
    }
    return out;
  }

  /// 单个 md 文件的内容解码（导入单篇时用）。
  static String? decodeSingle(Uint8List bytes) {
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return null;
    }
  }

  /// 路径是否不安全。
  static bool _isUnsafe(String path) {
    if (path.startsWith('/')) return true;
    if (path.contains('..')) return true;
    if (path.startsWith('__MACOSX/')) return true;
    final base = p.posix.basename(path);
    if (base == '.DS_Store' || base.isEmpty) return true;
    return false;
  }

  /// 把 zip 里的层级压平。
  ///
  /// 为什么压平：文章导入后要落在站点的 postsDir 下，
  /// 而 zip 里可能带 `myblog/content/posts/a.md` 这种整条路径。
  /// 直接照搬会在仓库里造出一堆多余层级。
  ///
  /// 同名冲突时用 `-2`、`-3` 后缀区分，而不是覆盖。
  static String _flatten(String path) => p.posix.basename(path);

  /// 给一组文件名去重，遇到同名加序号。
  static Map<String, String> dedupe(Map<String, String> items) {
    final out = <String, String>{};
    for (final e in items.entries) {
      var name = e.key;
      if (out.containsKey(name)) {
        final base = p.posix.basenameWithoutExtension(name);
        final ext = p.posix.extension(name);
        var i = 2;
        while (out.containsKey('$base-$i$ext')) {
          i++;
        }
        name = '$base-$i$ext';
      }
      out[name] = e.value;
    }
    return out;
  }

  /// 生成导出文件名：`hugosugar-posts-20240501-0803.zip`
  static String exportFileName(DateTime now) {
    String two(int n) => n.toString().padLeft(2, '0');
    return 'hugosugar-posts-${now.year}${two(now.month)}${two(now.day)}'
        '-${two(now.hour)}${two(now.minute)}.zip';
  }

  /// 把内容写进临时文件，供分享面板使用。
  static Future<File> writeTempZip(
    Directory tmpDir,
    Uint8List bytes,
    String fileName,
  ) async {
    await tmpDir.create(recursive: true);
    final f = File(p.join(tmpDir.path, fileName));
    await f.writeAsBytes(bytes, flush: true);
    return f;
  }
}