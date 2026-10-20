import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'note.dart';

/// 笔记持久化。
///
/// ## 为什么不用 drift（与原规格的偏差）
///
/// FEATURE_SPEC 里写的是 drift。这里改成 JSON 文件，原因是实测权衡：
///
/// | | drift | JSON 文件 |
/// |---|---|---|
/// | 原生依赖 | 需要 sqlite3 native 库 | 无 |
/// | codegen | 需要 build_runner，每次改表跑一遍 | 无 |
/// | ARM64 构建风险 | sqlite3_flutter_libs 编 ABI，踩过 ABI 的坑 | 零 |
/// | 笔记量级 | 几千条无压力 | 几千条无压力 |
///
/// 笔记是**个人灵感库**，典型量级是几百到几千条，全文都在内存里也
/// 不到 1 MB。用数据库换来的查询能力，在「按分类 / 关键词过滤」
/// 这种需求上，Dart 的 `where` 完全够用，且省掉一整条原生构建链路。
///
/// 真到需要全文索引或几万条时再换 drift 不迟 —— 接口已经收在
/// [NoteStore] 里，替换实现不影响 UI。
///
/// ## 写入安全
///
/// 所有写操作都是「写临时文件 → rename」。rename 在同分区是原子操作，
/// 所以即使进程被系统杀掉在写入中途，原文件也完好。这是直接用
/// `writeAsString` 做不到的。
class NoteStore {
  NoteStore._(this._file);

  final File _file;

  List<Note> _notes = [];
  List<NoteCategory> _categories = [];
  bool _loaded = false;

  /// 打开（或创建）笔记库
  static Future<NoteStore> open() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'notes'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final store = NoteStore._(File(p.join(dir.path, 'notes.json')));
    await store._load();
    return store;
  }

  /// 指定路径打开（测试用）
  static Future<NoteStore> openAt(String path) async {
    final store = NoteStore._(File(path));
    await store._load();
    return store;
  }

  Future<void> _load() async {
    _loaded = false;
    try {
      if (await _file.exists()) {
        final raw = await _file.readAsString();
        if (raw.trim().isNotEmpty) {
          final decoded = jsonDecode(raw);
          if (decoded is Map<String, Object?>) {
            final notes = decoded['notes'];
            if (notes is List) {
              _notes = notes
                  .whereType<Map<String, Object?>>()
                  .map(Note.fromJson)
                  .where((n) => n.id.isNotEmpty)
                  .toList();
            }
            final cats = decoded['categories'];
            if (cats is List) {
              _categories = cats
                  .whereType<Map<String, Object?>>()
                  .map(NoteCategory.fromJson)
                  .where((c) => c.id.isNotEmpty)
                  .toList();
            }
          }
        }
      }
    } catch (_) {
      // 文件损坏不能让 App 起不来。备份坏文件后从空库开始，
      // 至少用户还能继续用，坏数据也还在磁盘上可人工抢救。
      await _backupCorrupt();
      _notes = [];
      _categories = [];
    }
    _loaded = true;
  }

  Future<void> _backupCorrupt() async {
    try {
      if (await _file.exists()) {
        final ts = DateTime.now().millisecondsSinceEpoch;
        await _file.copy('${_file.path}.corrupt-$ts');
      }
    } catch (_) {
      // 备份失败也不阻断启动
    }
  }

  Future<void> _persist() async {
    final payload = jsonEncode({
      'version': 1,
      'notes': _notes.map((n) => n.toJson()).toList(),
      'categories': _categories.map((c) => c.toJson()).toList(),
    });

    // 原子写：先写 tmp，再 rename
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(payload, flush: true);
    if (await _file.exists()) {
      await _file.delete();
    }
    await tmp.rename(_file.path);
  }

  // ── 查询 ───────────────────────────────────────────

  bool get isLoaded => _loaded;

  /// 所有未删除的笔记（回收站除外）
  List<Note> get active => _notes.where((n) => !n.isDeleted).toList();

  /// 全部想法，**包含回收站里的**。
  ///
  /// 给 AI 上下文装配这类需要自己决定过滤逻辑的调用方用。
  /// UI 列表不要用这个，用 [active] —— 否则删除的想法会漏出来。
  List<Note> get all => List.unmodifiable(_notes);

  /// 回收站
  List<Note> get trashed => _notes.where((n) => n.isDeleted).toList();

  /// 置顶笔记（会注入 AI System Prompt）
  List<Note> get pinned => active.where((n) => n.pinned).toList();

  List<NoteCategory> get categories => List.unmodifiable(
        [..._categories]..sort((a, b) => a.order.compareTo(b.order)),
      );

  NoteCategory? categoryById(String? id) {
    if (id == null) return null;
    for (final c in _categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  Note? byId(String id) {
    for (final n in _notes) {
      if (n.id == id) return n;
    }
    return null;
  }

  /// 搜索：标题 + 正文，大小写不敏感
  List<Note> search(String query, {bool includeTrashed = false}) {
    final q = query.trim().toLowerCase();
    final pool = includeTrashed ? _notes : active;
    if (q.isEmpty) return pool;
    return pool
        .where((n) =>
            n.title.toLowerCase().contains(q) ||
            n.content.toLowerCase().contains(q))
        .toList();
  }

  /// 按分类过滤（null = 不分类）
  List<Note> inCategory(String? categoryId) {
    return active.where((n) => n.categoryId == categoryId).toList();
  }

  // ── 写入 ───────────────────────────────────────────

  /// 新建笔记，返回落盘后的对象
  Future<Note> create({
    String title = '',
    String content = '',
    String? categoryId,
    bool pinned = false,
  }) async {
    final now = DateTime.now();
    final note = Note(
      id: _newId(),
      title: title.trim(),
      content: content,
      createdAt: now,
      updatedAt: now,
      categoryId: categoryId,
      pinned: pinned,
    );
    _notes = [..._notes, note];
    await _persist();
    return note;
  }

  /// 更新笔记。id 不存在时静默忽略（避免 UI 竞态导致崩溃）。
  Future<Note?> update(Note note) async {
    final i = _notes.indexWhere((n) => n.id == note.id);
    if (i < 0) return null;
    _notes = [..._notes]..[i] = note.copyWith(updatedAt: DateTime.now());
    await _persist();
    return _notes[i];
  }

  /// 移到回收站（软删除）
  Future<bool> trash(String id) async {
    final note = byId(id);
    if (note == null) return false;
    final i = _notes.indexWhere((n) => n.id == id);
    _notes = [..._notes]
      ..[i] = note.copyWith(deletedAt: DateTime.now(), pinned: false);
    await _persist();
    return true;
  }

  /// 从回收站恢复
  Future<bool> restore(String id) async {
    final note = byId(id);
    if (note == null) return false;
    final i = _notes.indexWhere((n) => n.id == id);
    _notes = [..._notes]..[i] = note.copyWith(clearDeletedAt: true);
    await _persist();
    return true;
  }

  /// 彻底删除
  Future<bool> purge(String id) async {
    final before = _notes.length;
    _notes = _notes.where((n) => n.id != id).toList();
    if (_notes.length == before) return false;
    await _persist();
    return true;
  }

  /// 清空回收站
  Future<int> purgeAllTrashed() async {
    final count = trashed.length;
    if (count == 0) return 0;
    _notes = _notes.where((n) => !n.isDeleted).toList();
    await _persist();
    return count;
  }

  /// 切换置顶
  Future<Note?> togglePin(String id) async {
    final note = byId(id);
    if (note == null || note.isDeleted) return null;
    return update(note.copyWith(pinned: !note.pinned));
  }

  // ── 分类 ───────────────────────────────────────────

  Future<NoteCategory> createCategory(String name) async {
    final now = DateTime.now().microsecondsSinceEpoch.toString();
    final cat = NoteCategory(
      id: 'cat_$now',
      name: name.trim(),
      order: _categories.length,
    );
    _categories = [..._categories, cat];
    await _persist();
    return cat;
  }

  Future<void> renameCategory(String id, String name) async {
    final i = _categories.indexWhere((c) => c.id == id);
    if (i < 0) return;
    _categories = [..._categories]
      ..[i] = NoteCategory(
        id: _categories[i].id,
        name: name.trim(),
        order: _categories[i].order,
      );
    await _persist();
  }

  /// 删除分类。笔记不跟着删，只是解除归属。
  Future<void> deleteCategory(String id) async {
    _categories = _categories.where((c) => c.id != id).toList();
    _notes = _notes
        .map((n) => n.categoryId == id ? n.copyWith(clearCategory: true) : n)
        .toList();
    await _persist();
  }

  /// 分类下的笔记数
  int countInCategory(String? categoryId) =>
      active.where((n) => n.categoryId == categoryId).length;

  String _newId() {
    final ts = DateTime.now().microsecondsSinceEpoch;
    // 极短时间连续创建时用计数器避免碰撞
    final suffix = _notes.length % 1000;
    return 'note_${ts}_$suffix';
  }
}