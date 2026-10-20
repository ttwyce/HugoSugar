/// 一条笔记（灵感）。
///
/// 设计要点（见 FEATURE_SPEC 决议 2）：
/// - 笔记是 **AI 的一等数据源**，不只是 App 里一个页面。
///   [pinned] 为 true 时会自动注入 AI 的 System Prompt。
/// - [deletedAt] 非空表示在回收站，所有正常查询都要过滤掉。
/// - [convertedPostId] 记录「已转成哪篇文章」，防止重复转换。
class Note {
  const Note({
    required this.id,
    required this.title,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    this.categoryId,
    this.pinned = false,
    this.deletedAt,
    this.convertedPostId,
  });

  final String id;
  final String title;

  /// Markdown 正文
  final String content;

  final String? categoryId;

  /// 置顶 = 自动进 System Prompt
  final bool pinned;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// 非空 = 在回收站
  final DateTime? deletedAt;

  /// 转成文章后的相对路径，防止重复转换
  final String? convertedPostId;

  bool get isDeleted => deletedAt != null;
  bool get isConverted => convertedPostId != null && convertedPostId!.isNotEmpty;

  /// 列表预览：去掉 Markdown 标记的前若干字符
  String get preview {
    var s = content
        .replaceAll(RegExp(r'```[\s\S]*?```'), ' ')
        .replaceAll(RegExp(r'`([^`]*)`'), r'$1')
        .replaceAll(RegExp(r'^\s{0,3}#{1,6}\s*', multiLine: true), '')
        .replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), ' ')
        .replaceAllMapped(
          RegExp(r'\[([^\]]*)\]\([^)]*\)'),
          (m) => m.group(1) ?? '',
        )
        .replaceAll(RegExp(r'^\s*[-*+]\s+', multiLine: true), '')
        .replaceAll(RegExp(r'^\s*>\s?', multiLine: true), '')
        .replaceAll(RegExp(r'[*_~]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (s.length <= 90) return s;
    return '${s.substring(0, 90)}…';
  }

  /// 字数（不计空白）
  int get charCount => content.replaceAll(RegExp(r'\s'), '').length;

  /// 更新时间的人话表示
  String get updatedLabel {
    final now = DateTime.now();
    final diff = now.difference(updatedAt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    if (diff.inDays < 7) return '${diff.inDays} 天前';
    final m = updatedAt.month.toString().padLeft(2, '0');
    final d = updatedAt.day.toString().padLeft(2, '0');
    return '${updatedAt.year}-$m-$d';
  }

  Note copyWith({
    String? title,
    String? content,
    String? categoryId,
    bool? pinned,
    DateTime? updatedAt,
    DateTime? deletedAt,
    String? convertedPostId,
    bool clearDeletedAt = false,
    bool clearCategory = false,
  }) {
    return Note(
      id: id,
      title: title ?? this.title,
      content: content ?? this.content,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
      pinned: pinned ?? this.pinned,
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
      convertedPostId: convertedPostId ?? this.convertedPostId,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'content': content,
        'categoryId': categoryId,
        'pinned': pinned,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'deletedAt': deletedAt?.toIso8601String(),
        'convertedPostId': convertedPostId,
      };

  static Note fromJson(Map<String, Object?> json) {
    final now = DateTime.now().toIso8601String();
    return Note(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      content: json['content'] as String? ?? '',
      categoryId: json['categoryId'] as String?,
      pinned: json['pinned'] as bool? ?? false,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? now) ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? now) ?? DateTime.now(),
      deletedAt: json['deletedAt'] == null
          ? null
          : DateTime.tryParse(json['deletedAt'] as String),
      convertedPostId: json['convertedPostId'] as String?,
    );
  }
}

/// 笔记分类。
///
/// 用独立实体而不是字符串字段，是为了支持「重命名分类不影响笔记」
/// 以及将来 AI 的 `list_notes` 按分类过滤。
class NoteCategory {
  const NoteCategory({
    required this.id,
    required this.name,
    this.order = 0,
  });

  final String id;
  final String name;
  final int order;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'order': order,
      };

  static NoteCategory fromJson(Map<String, Object?> json) => NoteCategory(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        order: (json['order'] as num?)?.toInt() ?? 0,
      );
}