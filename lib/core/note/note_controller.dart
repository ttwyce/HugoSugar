import 'package:flutter/foundation.dart';

import '../site/site_controller.dart';
import 'note.dart';
import 'note_store.dart';

/// 笔记页的视图状态（置顶区 / 全部 / 搜索 / 分类 / 回收站）
enum NoteView { active, pinned, trashed }

/// 笔记控制器。
///
/// 职责分离：
/// - [NoteStore] 只管读写磁盘
/// - 本类管视图筛选、选中态、以及「转文章」这种跨模块动作
///
/// 「转文章」放在这里而不是笔记页，是因为它要同时动笔记库和站点文件，
/// 属于业务编排，不该写进 Widget。
class NoteController extends ChangeNotifier {
  NoteController({required NoteStore store, SiteController? site})
      : _store = store,
        _site = site;

  final NoteStore _store;
  final SiteController? _site;

  /// 站点可能在启动后才就绪，所以要能换
  SiteController? _siteLive;
  SiteController? get site => _siteLive ?? _site;

  NoteView _view = NoteView.active;
  String _query = '';
  String? _categoryId;

  NoteStore get store => _store;
  NoteView get view => _view;
  String get query => _query;
  String? get categoryId => _categoryId;

  bool get isSearching => _query.trim().isNotEmpty;

  /// 附件站点控制器（站点晚于笔记就绪时用）
  void attachSite(SiteController? site) {
    if (identical(_siteLive, site)) return;
    _siteLive = site;
    notifyListeners();
  }

  /// 外部直接改动了 [NoteStore] 后通知界面刷新。
  ///
  /// 目前只有「从 WebDAV 备份恢复」会走这里：恢复是批量合并，
  /// 走 [_store.mergeBackup] 比逐条调 [saveNote] 快得多，
  /// 但那样就绕过了本类的每个写方法，需要显式补一次通知。
  void notifyExternalChange() => notifyListeners();

  // ── 视图状态 ───────────────────────────────────────

  void setView(NoteView v) {
    if (_view == v) return;
    _view = v;
    // 切到回收站时清掉分类过滤，否则会是空列表且用户不知为何
    if (v == NoteView.trashed) _categoryId = null;
    notifyListeners();
  }

  void setQuery(String q) {
    if (_query == q) return;
    _query = q;
    notifyListeners();
  }

  void setCategory(String? id) {
    if (_categoryId == id) return;
    _categoryId = id;
    notifyListeners();
  }

  void clearFilters() {
    _view = NoteView.active;
    _query = '';
    _categoryId = null;
    notifyListeners();
  }

  // ── 列表装配 ───────────────────────────────────────

  /// 当前应显示的笔记列表。
  ///
  /// 顺序规则（重要）：
  /// 1. 回收站视图只显示已删除的，按删除时间倒序
  /// 2. 其它视图：置顶在前，然后按更新时间倒序
  /// 这样「置顶 = 重要」的语义在列表上就是可见的。
  List<Note> get visibleNotes {
    if (_view == NoteView.trashed) {
      final list = List<Note>.of(_store.trashed)
        ..sort((a, b) =>
            (b.deletedAt ?? b.updatedAt).compareTo(a.deletedAt ?? a.updatedAt));
      if (!isSearching) return list;
      final q = _query.trim().toLowerCase();
      return list
          .where((n) =>
              n.title.toLowerCase().contains(q) ||
              n.content.toLowerCase().contains(q))
          .toList();
    }

    var list = _store.active;

    if (_categoryId != null) {
      list = list.where((n) => n.categoryId == _categoryId).toList();
    }

    if (isSearching) {
      final q = _query.trim().toLowerCase();
      list = list
          .where((n) =>
              n.title.toLowerCase().contains(q) ||
              n.content.toLowerCase().contains(q))
          .toList();
    }

    if (_view == NoteView.pinned) {
      list = list.where((n) => n.pinned).toList();
    }

    // 置顶优先，再按更新时间
    return list
      ..sort((a, b) {
        if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
        return b.updatedAt.compareTo(a.updatedAt);
      });
  }

  List<Note> get pinnedNotes => visibleNotes.where((n) => n.pinned).toList();
  List<Note> get unpinnedNotes => visibleNotes.where((n) => !n.pinned).toList();

  int get activeCount => _store.active.length;
  int get trashCount => _store.trashed.length;
  int get pinnedCount => _store.pinned.length;

  // ── CRUD ───────────────────────────────────────────

  Future<Note> createNote({
    String title = '',
    String content = '',
    String? categoryId,
    bool pinned = false,
  }) async {
    final note = await _store.create(
      title: title,
      content: content,
      categoryId: categoryId ?? _categoryId,
      pinned: pinned,
    );
    notifyListeners();
    return note;
  }

  Future<Note?> saveNote(Note note) async {
    final saved = await _store.update(note);
    notifyListeners();
    return saved;
  }

  Future<void> trashNote(String id) async {
    await _store.trash(id);
    notifyListeners();
  }

  Future<void> restoreNote(String id) async {
    await _store.restore(id);
    notifyListeners();
  }

  Future<void> purgeNote(String id) async {
    await _store.purge(id);
    notifyListeners();
  }

  Future<int> purgeAll() async {
    final n = await _store.purgeAllTrashed();
    notifyListeners();
    return n;
  }

  Future<void> togglePin(String id) async {
    await _store.togglePin(id);
    notifyListeners();
  }

  Future<void> createCategory(String name) async {
    await _store.createCategory(name);
    notifyListeners();
  }

  Future<void> renameCategory(String id, String name) async {
    await _store.renameCategory(id, name);
    notifyListeners();
  }

  Future<void> deleteCategory(String id) async {
    await _store.deleteCategory(id);
    if (_categoryId == id) _categoryId = null;
    notifyListeners();
  }

  // ── 转文章（核心动作）────────────────────────────────

  /// 把笔记转成一篇文章并写入站点。
  ///
  /// 返回新文章的相对路径，失败返回 null。
  ///
  /// 三个必须处理的细节：
  /// 1. 笔记已转过 → 不重复创建，除非 [force]
  /// 2. 站点未接入 → 明确报错，不能静默失败
  /// 3. 转换成功后回写 convertedPostId，避免用户连点两次生成两篇
  Future<NoteConvertResult> convertToPost(
    Note note, {
    required String title,
    List<String> categories = const [],
    List<String> tags = const [],
    String description = '',
    bool draft = true,
    bool force = false,
  }) async {
    final site = this.site;
    if (site == null || site.stage != SiteStage.ready) {
      return const NoteConvertResult(false, null, '站点未接入，无法生成文章');
    }

    if (note.isConverted && !force) {
      final existing = note.convertedPostId!;
      // 检查文件是否还在：用户可能已经手动删了文章
      final doc = await site.readPost(existing);
      if (doc != null) {
        return NoteConvertResult(
          false,
          existing,
          '这条笔记已经转换成「${doc.title}」',
        );
      }
      // 文件不在了，允许重新生成
    }

    final path = await site.createPost(
      title: title,
      categories: categories,
      tags: tags,
      description: description,
      draft: draft,
    );
    if (path == null) {
      return NoteConvertResult(false, null, site.error ?? '创建文章失败');
    }

    // 把笔记正文写进新文章（createPost 只建了空正文）
    final saveResult = await site.savePost(
      relativePath: path,
      title: title,
      body: note.content,
      original: await site.readPost(path),
    );

    if (!saveResult.ok) {
      return NoteConvertResult(false, path, saveResult.message ?? '写入正文失败');
    }

    // 回写转换记录
    final updated = note.copyWith(convertedPostId: path);
    await _store.update(updated);
    notifyListeners();

    return NoteConvertResult(true, path, null);
  }
}

/// 转文章的结果
class NoteConvertResult {
  const NoteConvertResult(this.ok, this.postPath, this.message);

  final bool ok;
  final String? postPath;
  final String? message;
}