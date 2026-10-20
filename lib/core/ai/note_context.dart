import '../note/note.dart';

/// AI 读取想法的范围。
///
/// ## 为什么需要这一层
///
/// 早先的规则是「只有置顶的想法才进 AI 上下文」，问题在于：
/// - 用户记想法时根本不会想到「要置顶才能给 AI 看」
/// - 结果是 AI 实际只能看到少数被手动精选的条目，
///   而绝大部分真实素材它一无所知
///
/// 现在的默认行为改成 **[Scope.all]：不指定就读全部想法**。
/// 置顶（[Scope.pinned]）降级为一种可选的收窄方式，
/// 而不是「能不能被读到」的开关。
///
/// ## 为什么要有上限
///
/// 全部想法可能是几百条，直接拼进 prompt 会：
/// 1. 撑爆上下文窗口
/// 2. 让每条的有效信息密度变得极低，回答质量反而下降
///
/// 所以按「最近更新优先」截断，并给出可读的统计信息，
/// 让用户知道 AI 到底看到了多少、被截掉了多少。
enum NoteScopeMode {
  /// 全部想法（默认）
  all,

  /// 只在指定分类里
  categories,

  /// 只在精选（置顶）里
  pinned,

  /// 不注入任何想法
  none,
}

/// 选择结果：最终要注入的列表 + 供用户确认的说明
class NoteContextSelection {
  const NoteContextSelection({
    required this.notes,
    required this.totalMatched,
    required this.truncated,
    required this.mode,
  });

  /// 实际注入的想法（已按上限截断）
  final List<Note> notes;

  /// 符合范围条件的总数（截断前）
  final int totalMatched;

  /// 因超上限被丢弃的条数
  final int truncated;

  final NoteScopeMode mode;

  bool get isEmpty => notes.isEmpty;

  /// 给 UI 显示的一句话，例如：
  /// `读取全部想法 12 条` / `读取 3 个分组 45 条（已截断 25 条）`
  String describe({String Function(String id)? categoryName}) {
    if (mode == NoteScopeMode.none) return '不读取想法';
    if (notes.isEmpty) {
      return switch (mode) {
        NoteScopeMode.all => '没有可读取的想法',
        NoteScopeMode.categories => '选中的分组里没有说话',
        NoteScopeMode.pinned => '没有精选的想法',
        NoteScopeMode.none => '不读取想法',
      };
    }

    final base = switch (mode) {
      NoteScopeMode.all => '读取全部想法 ${notes.length} 条',
      NoteScopeMode.categories =>
        '读取选中分组 ${notes.length} 条',
      NoteScopeMode.pinned => '读取精选想法 ${notes.length} 条',
      NoteScopeMode.none => '不读取想法',
    };

    if (truncated <= 0) return base;
    return '$base（另有 $truncated 条超出上限未读取）';
  }

  /// 拼成注入 LLM 的文本块。
  ///
  /// 格式刻意保持朴素：标题 + 正文。不加时间戳和分类标签，
  /// 那些是给人看的元信息，对模型理解内容没有帮助，
  /// 反而会占用 token。
  String toPromptBlock() {
    if (notes.isEmpty) return '';
    final buf = StringBuffer();
    buf.writeln('## 用户的想法');
    buf.writeln();
    for (final n in notes) {
      final title = n.title.trim();
      buf.writeln(title.isEmpty ? '（无标题）' : '### $title');
      buf.writeln(n.content.trim());
      buf.writeln();
    }
    return buf.toString();
  }
}

/// 想法上下文的装配器。
///
/// 纯函数式，不碰 IO —— 输入是已经加载好的想法列表，
/// 输出是选择结果。这样能单测，也方便将来换成
/// 「从磁盘增量读取」的实现而不改调用方。
class NoteContextBuilder {
  const NoteContextBuilder({this.maxNotes = 80});

  /// 最多注入多少条，防止撑爆上下文
  final int maxNotes;

  NoteContextSelection build({
    required List<Note> allNotes,
    NoteScopeMode mode = NoteScopeMode.all,
    Set<String> categoryIds = const {},
  }) {
    // 回收站里的一律不注入 —— 用户已经表达过「不要了」
    final alive = allNotes.where((n) => !n.isDeleted).toList();

    final matched = switch (mode) {
      NoteScopeMode.none => <Note>[],
      NoteScopeMode.all => alive,
      NoteScopeMode.pinned => alive.where((n) => n.pinned).toList(),
      NoteScopeMode.categories => alive
          .where((n) => n.categoryId != null &&
              categoryIds.contains(n.categoryId))
          .toList(),
    };

    // 最近更新的优先，这样超上限时保留的是活跃内容
    matched.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    final truncated =
        matched.length > maxNotes ? matched.length - maxNotes : 0;
    final picked =
        matched.length > maxNotes ? matched.sublist(0, maxNotes) : matched;

    return NoteContextSelection(
      notes: pickIfEmpty(mode, categoryIds, picked),
      totalMatched: matched.length,
      truncated: truncated,
      mode: mode,
    );
  }

  /// 分组模式下如果用户还没选分组，退化成「不读取」而不是
  /// 意外变成「读全部」—— 悄悄扩大范围比读不到更让人意外。
  List<Note> pickIfEmpty(
    NoteScopeMode mode,
    Set<String> categoryIds,
    List<Note> picked,
  ) {
    if (mode == NoteScopeMode.categories && categoryIds.isEmpty) {
      return const [];
    }
    return picked;
  }
}