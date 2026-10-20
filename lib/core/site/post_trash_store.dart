import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 一篇被移入回收站的文章。
///
/// [content] 保存的是**整个 md 文件的原文**（含 Front Matter），
/// 而不是解析后的字段。这样恢复时能原样写回，用户手写的
/// 未知 Front Matter 键（cover / series / aliases 等）不会丢失。
class TrashedPost {
  const TrashedPost({
    required this.relativePath,
    required this.title,
    required this.content,
    required this.deletedAt,
  });

  final String relativePath;
  final String title;
  final String content;
  final DateTime deletedAt;

  Map<String, Object?> toJson() => {
        'relativePath': relativePath,
        'title': title,
        'content': content,
        'deletedAt': deletedAt.toIso8601String(),
      };

  static TrashedPost fromJson(Map<String, Object?> json) => TrashedPost(
        relativePath: json['relativePath'] as String? ?? '',
        title: json['title'] as String? ?? '',
        content: json['content'] as String? ?? '',
        deletedAt:
            DateTime.tryParse(json['deletedAt'] as String? ?? '') ??
                DateTime.now(),
      );
}

/// 文章回收站的持久化。
///
/// ## 为什么不放在 Git 仓库里
///
/// 直觉做法是把文件 move 到仓库内的 `.trash/` 目录。但那会让
/// `git status` 里多出一堆 `D posts/x.md` + `?? .trash/x.md`，
/// 用户每次推送都被要求提交一堆「删除」，回收站反而污染了工作流。
///
/// 所以回收站存在**仓库之外**：`<appSupport>/trash-posts/<siteId>.json`。
/// 移入回收站 = 从仓库删除文件 + 把原文存到仓库外；
/// 恢复 = 把原文写回仓库原路径。
///
/// ## 代价
///
/// 用户若在别的机器上克隆仓库，看不到回收站内容 —— 这符合预期，
/// 回收站本来就是本地临时区，不是版本控制内容。
class PostTrashStore {
  PostTrashStore._(this._file);

  final File _file;

  /// 站点标识，用来隔离不同仓库的回收站
  final List<TrashedPost> _items = [];

  static Future<PostTrashStore> open(String siteId) async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'trash-posts'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    // siteId 里可能有路径分隔符，压平成合法文件名
    final safe = siteId.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final store = PostTrashStore._(File(p.join(dir.path, '$safe.json')));
    await store._load();
    return store;
  }

  /// 指定路径打开（测试用）
  static Future<PostTrashStore> openAt(String path) async {
    final store = PostTrashStore._(File(path));
    await store._load();
    return store;
  }

  Future<void> _load() async {
    _items.clear();
    try {
      if (!await _file.exists()) return;
      final raw = await _file.readAsString();
      if (raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) return;
      final list = decoded['items'];
      if (list is! List) return;
      for (final e in list) {
        if (e is Map<String, Object?>) _items.add(TrashedPost.fromJson(e));
      }
      _sort();
    } catch (_) {
      // 损坏就当作空回收站，不让一条坏记录卡死整个页面
      _items.clear();
    }
  }

  /// 原子写入：先写临时文件再 rename，避免写一半被系统杀掉。
  Future<void> _flush() async {
    _sort();
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(
      jsonEncode({'items': _items.map((e) => e.toJson()).toList()}),
      flush: true,
    );
    await tmp.rename(_file.path);
  }

  void _sort() {
    _items.sort((a, b) => b.deletedAt.compareTo(a.deletedAt));
  }

  List<TrashedPost> get items => List.unmodifiable(_items);
  int get count => _items.length;

  bool contains(String relativePath) =>
      _items.any((e) => e.relativePath == relativePath);

  Future<void> add(TrashedPost post) async {
    // 同一路径只保留最新一条，避免重复删除堆垃圾
    _items.removeWhere((e) => e.relativePath == post.relativePath);
    _items.add(post);
    await _flush();
  }

  Future<TrashedPost?> remove(String relativePath) async {
    final idx = _items.indexWhere((e) => e.relativePath == relativePath);
    if (idx < 0) return null;
    final removed = _items.removeAt(idx);
    await _flush();
    return removed;
  }

  Future<int> clear() async {
    final n = _items.length;
    _items.clear();
    await _flush();
    return n;
  }
}
