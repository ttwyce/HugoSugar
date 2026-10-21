import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'ai_message.dart';

/// 一次工具调用的记录，供 UI 折叠展示与回滚
class ToolCallRecord {
  const ToolCallRecord({
    required this.id,
    required this.name,
    required this.arguments,
    required this.ok,
    required this.summary,
    this.detail = '',
    this.approved,
  });

  final String id;
  final String name;

  /// 原始参数 JSON
  final String arguments;
  final bool ok;

  /// 一行摘要（折叠时显示）
  final String summary;

  /// 展开后的详情
  final String detail;

  /// 仅 write_post 有：用户是否批准
  final bool? approved;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'arguments': arguments,
        'ok': ok,
        'summary': summary,
        'detail': detail,
        if (approved != null) 'approved': approved,
      };

  static ToolCallRecord fromJson(Map<String, dynamic> j) => ToolCallRecord(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        arguments: j['arguments'] as String? ?? '',
        ok: j['ok'] as bool? ?? false,
        summary: j['summary'] as String? ?? '',
        detail: j['detail'] as String? ?? '',
        approved: j['approved'] as bool?,
      );
}

/// 一次写入操作的备份，支持回滚
class WriteBackup {
  const WriteBackup({
    required this.relPath,
    required this.previous,
    required this.at,
  });

  final String relPath;

  /// 写入前的原内容；null 表示这个文件之前不存在
  final String? previous;

  final DateTime at;

  Map<String, dynamic> toJson() => {
        'relPath': relPath,
        'previous': previous,
        'at': at.toIso8601String(),
      };

  static WriteBackup fromJson(Map<String, dynamic> j) => WriteBackup(
        relPath: j['relPath'] as String? ?? '',
        previous: j['previous'] as String?,
        at: DateTime.tryParse(j['at'] as String? ?? '') ?? DateTime.now(),
      );
}

/// 对话中的一条展示消息。
///
/// 与 [AiMessage] 的区别：[AiMessage] 是发给 API 的形状，
/// 这里是给用户看的形状（包含工具调用记录、错误、时间）。
class ChatEntry {
  const ChatEntry({
    required this.role,
    required this.text,
    required this.at,
    this.toolCalls = const [],
    this.isError = false,
    this.backups = const [],
    this.promptTokens,
    this.completionTokens,
    this.usageIsExact = false,
    this.reasoning = '',
    this.toolTokensEstimated = 0,
  });

  final String role;
  final String text;
  final DateTime at;
  final List<ToolCallRecord> toolCalls;
  final bool isError;

  /// 本条触发的所有写盘备份。
  ///
  /// 用 List 而不是单个：模型在一次回答里完全可能连续写多篇文章
  /// （「帮我写三篇」），只记最后一个会让前几次写入无法回滚。
  final List<WriteBackup> backups;

  final int? promptTokens;
  final int? completionTokens;

  /// token 数是否来自服务端 usage。
  ///
  /// false 表示是按「字数 / 4」估出来的 —— 界面上必须标注，
  /// 否则用户会把它当账单数字。
  final bool usageIsExact;

  /// 模型的思考过程（DeepSeek-R1 等推理模型才有）。
  ///
  /// 存下来的理由：思考过程往往解释了模型为什么那样写文章
  /// （比如「先看看已有文章的格式」），事后回看很有价值。
  /// 空串表示该模型不返回思考内容 —— 界面据此决定是否显示折叠区。
  final String reasoning;

  /// 工具结果注入后额外增加的 token（估算）
  final int toolTokensEstimated;

  bool get isUser => role == 'user';
  bool get canRollback => backups.isNotEmpty;

  ChatEntry copyWith({
    String? text,
    List<ToolCallRecord>? toolCalls,
    bool? isError,
    int? promptTokens,
    int? completionTokens,
    bool? usageIsExact,
    String? reasoning,
    int? toolTokensEstimated,
  }) {
    return ChatEntry(
      role: role,
      text: text ?? this.text,
      at: at,
      toolCalls: toolCalls ?? this.toolCalls,
      isError: isError ?? this.isError,
      backups: backups,
      promptTokens: promptTokens ?? this.promptTokens,
      completionTokens: completionTokens ?? this.completionTokens,
      usageIsExact: usageIsExact ?? this.usageIsExact,
      reasoning: reasoning ?? this.reasoning,
      toolTokensEstimated: toolTokensEstimated ?? this.toolTokensEstimated,
    );
  }

  Map<String, dynamic> toJson() => {
        'role': role,
        'text': text,
        'at': at.toIso8601String(),
        if (toolCalls.isNotEmpty)
          'toolCalls': toolCalls.map((c) => c.toJson()).toList(),
        if (isError) 'isError': true,
        if (backups.isNotEmpty)
          'backups': backups.map((b) => b.toJson()).toList(),
        if (promptTokens != null) 'promptTokens': promptTokens,
        if (completionTokens != null) 'completionTokens': completionTokens,
        if (usageIsExact) 'usageIsExact': true,
        if (reasoning.isNotEmpty) 'reasoning': reasoning,
        if (toolTokensEstimated > 0)
          'toolTokensEstimated': toolTokensEstimated,
      };

  static ChatEntry fromJson(Map<String, dynamic> j) {
    final raw = j['toolCalls'];
    final calls = <ToolCallRecord>[];
    if (raw is List) {
      for (final c in raw) {
        if (c is Map) {
          calls.add(ToolCallRecord.fromJson(Map<String, dynamic>.from(c)));
        }
      }
    }
    final rawBackups = j['backups'];
    final backups = <WriteBackup>[];
    if (rawBackups is List) {
      for (final b in rawBackups) {
        if (b is Map) {
          backups.add(WriteBackup.fromJson(Map<String, dynamic>.from(b)));
        }
      }
    }
    // 兼容早期单条格式（beta 中写过的数据）
    final legacy = j['backup'];
    if (backups.isEmpty && legacy is Map) {
      backups.add(WriteBackup.fromJson(Map<String, dynamic>.from(legacy)));
    }
    return ChatEntry(
      role: j['role'] as String? ?? 'assistant',
      text: j['text'] as String? ?? '',
      at: DateTime.tryParse(j['at'] as String? ?? '') ?? DateTime.now(),
      toolCalls: calls,
      isError: j['isError'] as bool? ?? false,
      backups: backups,
      promptTokens: (j['promptTokens'] as num?)?.toInt(),
      completionTokens: (j['completionTokens'] as num?)?.toInt(),
      usageIsExact: j['usageIsExact'] as bool? ?? false,
      reasoning: j['reasoning'] as String? ?? '',
      toolTokensEstimated: (j['toolTokensEstimated'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 一次完整对话
class ChatSession {
  const ChatSession({
    required this.id,
    required this.title,
    required this.updatedAt,
    this.entries = const [],
    this.endpointId = '',
    this.model = '',
    this.categoryIds = const [],
    this.readNotes = false,
  });

  final String id;
  final String title;
  final DateTime updatedAt;
  final List<ChatEntry> entries;

  /// 记录用哪个端点/模型产生的，方便回溯
  final String endpointId;
  final String model;

  /// 本次对话的 AI 读取范围设置（分组 + 开关），持久化后下次沿用
  final List<String> categoryIds;
  final bool readNotes;

  /// 累计 token（服务端给了用真值，否则是估算）
  int get totalPromptTokens =>
      entries.fold(0, (a, e) => a + (e.promptTokens ?? 0));

  int get totalCompletionTokens =>
      entries.fold(0, (a, e) => a + (e.completionTokens ?? 0));

  /// 是否至少有一条用了精确值
  bool get hasExactUsage =>
      entries.any((e) => e.promptTokens != null || e.completionTokens != null);

  ChatSession copyWith({
    String? title,
    DateTime? updatedAt,
    List<ChatEntry>? entries,
    String? endpointId,
    String? model,
    List<String>? categoryIds,
    bool? readNotes,
  }) {
    return ChatSession(
      id: id,
      title: title ?? this.title,
      updatedAt: updatedAt ?? this.updatedAt,
      entries: entries ?? this.entries,
      endpointId: endpointId ?? this.endpointId,
      model: model ?? this.model,
      categoryIds: categoryIds ?? this.categoryIds,
      readNotes: readNotes ?? this.readNotes,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'updatedAt': updatedAt.toIso8601String(),
        'entries': entries.map((e) => e.toJson()).toList(),
        'endpointId': endpointId,
        'model': model,
        'categoryIds': categoryIds,
        'readNotes': readNotes,
      };

  static ChatSession fromJson(Map<String, dynamic> j) {
    final raw = j['entries'];
    final list = <ChatEntry>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) list.add(ChatEntry.fromJson(Map<String, dynamic>.from(e)));
      }
    }
    final cats = j['categoryIds'];
    return ChatSession(
      id: j['id'] as String? ?? '',
      title: j['title'] as String? ?? '',
      updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? '') ??
          DateTime.now(),
      entries: list,
      endpointId: j['endpointId'] as String? ?? '',
      model: j['model'] as String? ?? '',
      categoryIds: cats is List ? cats.whereType<String>().toList() : const [],
      readNotes: j['readNotes'] as bool? ?? false,
    );
  }

  /// 消息转成 API 形状。
  ///
  /// 只取 user / assistant 的文本 —— 工具调用记录**不**重新发回去，
  /// 因为回放历史工具调用会让模型以为那些操作刚刚发生，
  /// 容易导致「重复写同一个文件」。需要上下文时让它重新调工具。
  List<AiMessage> toApiMessages({int maxEntries = 24}) {
    final out = <AiMessage>[];
    final usable = entries.where((e) => !e.isError).toList();
    final slice = usable.length > maxEntries
        ? usable.sublist(usable.length - maxEntries)
        : usable;
    for (final e in slice) {
      if (e.text.trim().isEmpty) continue;
      out.add(AiMessage(role: e.isUser ? 'user' : 'assistant', content: e.text));
    }
    return out;
  }
}

/// 对话的本地存储。
///
/// 每个会话一个文件，列表通过扫目录得到 ——
/// 会话可能很多，全塞一个 JSON 里每次保存都要重写全部。
class ChatStore {
  ChatStore(this._dir);

  final Directory _dir;

  static Future<ChatStore> open() async {
    final base = await getApplicationSupportDirectory();
    return ChatStore(Directory('${base.path}/ai/chats'));
  }

  File _fileFor(String id) => File('${_dir.path}/$id.json');

  Future<List<ChatSession>> listAll() async {
    try {
      if (!await _dir.exists()) return const [];
      final files = await _dir.list().where((f) => f.path.endsWith('.json')).toList();
      final sessions = <ChatSession>[];
      for (final f in files) {
        try {
          final j = jsonDecode(await File(f.path).readAsString());
          if (j is Map) {
            sessions.add(ChatSession.fromJson(Map<String, dynamic>.from(j)));
          }
        } catch (_) {
          // 单个会话文件坏了，不影响其他会话
        }
      }
      sessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return sessions;
    } catch (_) {
      return const [];
    }
  }

  Future<ChatSession?> load(String id) async {
    try {
      final f = _fileFor(id);
      if (!await f.exists()) return null;
      final j = jsonDecode(await f.readAsString());
      if (j is! Map) return null;
      return ChatSession.fromJson(Map<String, dynamic>.from(j));
    } catch (_) {
      return null;
    }
  }

  Future<void> save(ChatSession s) async {
    await _dir.create(recursive: true);
    await _fileFor(s.id).writeAsString(jsonEncode(s.toJson()), flush: true);
  }

  Future<void> delete(String id) async {
    try {
      final f = _fileFor(id);
      if (await f.exists()) await f.delete();
    } catch (_) {
      // 忽略
    }
  }
}