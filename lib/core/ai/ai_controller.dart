import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as pkg;

import '../note/note.dart';
import '../note/note_controller.dart';
import '../site/site_controller.dart';
import 'agent_runner.dart';
import 'ai_client.dart';
import 'ai_endpoint.dart';
import 'chat_store.dart';
import 'note_context.dart';
import 'tools/ai_tool.dart';
import 'tools/builtin_tools.dart';

/// AI 功能的对外门面。
///
/// 负责把「设置 → 端点 / key」「想法 / 文章 → 工具」「对话 → 存储」
/// 这几块拼起来，UI 只跟它打交道。
class AiController extends ChangeNotifier {
  AiController({
    AiClient? client,
    this.noteController,
    this.siteController,
  }) : _client = client ?? AiClient();

  final AiClient _client;
  final NoteController? noteController;
  final SiteController? siteController;

  AiEndpointStore? _endpointStore;
  AiKeyStore? _keyStore;
  ChatStore? _chatStore;
  UrlFetcher? _fetcher;

  // ── 状态 ────────────────────────────────────────────

  AiConfig _config = const AiConfig();
  AiConfig get config => _config;

  AiEndpoint? get activeEndpoint => _config.active;

  ChatSession? _session;
  ChatSession? get session => _session;

  List<ChatSession> _sessions = const [];
  List<ChatSession> get sessions => _sessions;

  /// 当前流式输出的累积文本（null = 空闲）
  String? _streamingText;
  String? get streamingText => _streamingText;

  bool _busy = false;
  bool get busy => _busy;

  /// 正在执行的工具名（给 UI 显示「正在读取…」）
  String? _runningTool;
  String? get runningTool => _runningTool;

  String? _lastError;
  String? get lastError => _lastError;

  /// 本次对话的 AI 读取范围（想法页设置过就沿用）
  bool _readNotes = false;
  bool get readNotes => _readNotes;

  List<String> _categoryIds = const [];
  List<String> get categoryIds => _categoryIds;

  /// 上次调用注入的说明，用于输入框上方的提示
  NoteContextSelection? _lastContext;
  NoteContextSelection? get lastContext => _lastContext;

  // ── 初始化 ──────────────────────────────────────────

  Future<void> init() async {
    _endpointStore = await AiEndpointStore.open();
    _keyStore = await AiKeyStore.open();
    _chatStore = await ChatStore.open();
    _fetcher = UrlFetcher();
    _config = await _endpointStore!.load();
    _sessions = await _chatStore!.listAll();
    notifyListeners();
  }

  // ── 端点管理 ────────────────────────────────────────

  Future<void> addEndpoint({
    required String name,
    required String baseUrl,
    String model = '',
    String apiKey = '',
  }) async {
    final id = 'ep_${DateTime.now().microsecondsSinceEpoch}';
    final ep = AiEndpoint(
      id: id,
      name: name.trim().isEmpty ? baseUrl : name.trim(),
      baseUrl: baseUrl.trim(),
      model: model.trim(),
      keyHint: apiKey.isEmpty ? '' : AiKeyStore.mask(apiKey),
    );

    _config = _config.copyWith(
      endpoints: [..._config.endpoints, ep],
      activeId: _config.activeId.isEmpty ? id : _config.activeId,
    );
    await _endpointStore?.save(_config);
    if (apiKey.trim().isNotEmpty) {
      await _keyStore?.write(id, apiKey);
    }
    notifyListeners();
  }

  Future<void> updateEndpoint(AiEndpoint ep, {String? apiKey}) async {
    final list = _config.endpoints
        .map((e) => e.id == ep.id ? ep : e)
        .toList(growable: false);

    var updated = ep;
    if (apiKey != null && apiKey.trim().isNotEmpty) {
      await _keyStore?.write(ep.id, apiKey);
      updated = ep.copyWith(keyHint: AiKeyStore.mask(apiKey));
    }

    _config = _config.copyWith(
      endpoints: list.map((e) => e.id == ep.id ? updated : e).toList(),
    );
    await _endpointStore?.save(_config);
    notifyListeners();
  }

  Future<void> removeEndpoint(String id) async {
    final list = _config.endpoints.where((e) => e.id != id).toList();
    // 删的是当前选中的，就切到剩下的第一个
    var activeId = _config.activeId;
    if (activeId == id) {
      activeId = list.isEmpty ? '' : list.first.id;
    }
    _config = AiConfig(endpoints: list, activeId: activeId);
    await _endpointStore?.save(_config);
    await _keyStore?.delete(id);
    notifyListeners();
  }

  Future<void> setActiveEndpoint(String id) async {
    if (_config.activeId == id) return;
    _config = _config.copyWith(activeId: id);
    await _endpointStore?.save(_config);
    notifyListeners();
  }

  Future<void> setEndpointModel(String endpointId, String model) async {
    final list = _config.endpoints
        .map((e) => e.id == endpointId ? e.copyWith(model: model) : e)
        .toList();
    _config = _config.copyWith(endpoints: list);
    await _endpointStore?.save(_config);
    notifyListeners();
  }

  Future<String?> readKey(String endpointId) async =>
      _keyStore?.read(endpointId);

  /// 拉取模型列表
  Future<List<AiModel>> fetchModels({
    required AiEndpoint endpoint,
    String? apiKey,
  }) async {
    final key = apiKey ?? await readKey(endpoint.id) ?? '';
    return _client.listModels(endpoint: endpoint, apiKey: key);
  }

  // ── 想法读取范围 ────────────────────────────────────

  void setReadScope({required bool enabled, List<String>? categoryIds}) {
    _readNotes = enabled;
    if (categoryIds != null) _categoryIds = categoryIds;
    notifyListeners();
  }

  // ── 对话 ────────────────────────────────────────────

  Future<void> newSession() async {
    final s = ChatSession(
      id: 'chat_${DateTime.now().microsecondsSinceEpoch}',
      title: '新对话',
      updatedAt: DateTime.now(),
      endpointId: activeEndpoint?.id ?? '',
      model: activeEndpoint?.model ?? '',
      categoryIds: _categoryIds,
      readNotes: _readNotes,
    );
    _session = s;
    await _chatStore?.save(s);
    notifyListeners();
  }

  Future<void> openSession(String id) async {
    final s = await _chatStore?.load(id);
    if (s == null) return;
    _session = s;
    _categoryIds = s.categoryIds;
    _readNotes = s.readNotes;
    notifyListeners();
  }

  Future<void> deleteSession(String id) async {
    await _chatStore?.delete(id);
    if (_session?.id == id) _session = null;
    _sessions = await _chatStore?.listAll() ?? const [];
    notifyListeners();
  }

  /// 发送一条消息并跑完整 Agent 循环。
  ///
  /// [onApproval] 由 UI 提供：弹出 Diff 让用户决定。返回 null 表示
  /// 用户直接关掉了面板，按「拒绝」处理。
  Future<void> send(
    String userText, {
    required Future<ApprovalDecision?> Function(ApprovalRequest req)
        onApproval,
  }) async {
    if (_busy) return;

    final text = userText.trim();
    if (text.isEmpty) return;

    final ep = activeEndpoint;
    if (ep == null) {
      _lastError = '还没有配置 AI 端点';
      notifyListeners();
      return;
    }
    if (ep.model.trim().isEmpty) {
      _lastError = '还没有为「${ep.name}」选择模型';
      notifyListeners();
      return;
    }

    final key = await readKey(ep.id);
    if (key == null || key.isEmpty) {
      _lastError = '还没有填写「${ep.name}」的 API Key';
      notifyListeners();
      return;
    }

    _session ??= ChatSession(
      id: 'chat_${DateTime.now().microsecondsSinceEpoch}',
      title: '新对话',
      updatedAt: DateTime.now(),
      endpointId: ep.id,
      model: ep.model,
      categoryIds: _categoryIds,
      readNotes: _readNotes,
    );

    _busy = true;
    _streamingText = '';
    _lastError = null;
    _runningTool = null;
    notifyListeners();

    // 记下用户消息（先落盘，避免中途崩溃丢失输入）
    final s0 = _session!;
    final withUser = s0.copyWith(
      entries: [
        ...s0.entries,
        ChatEntry(role: 'user', text: text, at: DateTime.now()),
      ],
      updatedAt: DateTime.now(),
      // 首条消息当作标题
      title: s0.entries.isEmpty
          ? (text.length > 24 ? '${text.substring(0, 24)}…' : text)
          : s0.title,
    );
    _session = withUser;
    await _chatStore?.save(withUser);
    notifyListeners();

    final systemPrompt = _buildSystemPrompt();
    final tools = _buildTools();
    final runner = AgentRunner(
      client: _client,
      tools: tools,
      readPost: _readPostContent,
    );

    final streamed = StringBuffer();
    final toolRecords = <ToolCallRecord>[];

    try {
      final result = await runner.run(
        endpoint: ep,
        apiKey: key,
        baseMessages: withUser.toApiMessages(),
        userText: text,
        systemPrompt: systemPrompt,
        callbacks: AgentCallbacks(
          onTextDelta: (d) {
            streamed.write(d);
            _streamingText = streamed.toString();
            notifyListeners();
          },
          onToolStart: (name, args) {
            _runningTool = name;
            notifyListeners();
          },
          onToolDone: (rec) {
            toolRecords.add(rec);
            _runningTool = null;
            notifyListeners();
          },
          requestApproval: (req) async {
            final d = await onApproval(req);
            // 关掉面板 = 不写。默认成「拒绝」而不是「批准」，
            // 是因为误写的代价远大于不写。
            return d ?? ApprovalDecision.reject;
          },
        ),
      );

      final entry = ChatEntry(
        role: 'assistant',
        text: result.text.isEmpty && toolRecords.isEmpty
            ? '（模型没有返回内容）'
            : result.text,
        at: DateTime.now(),
        toolCalls: toolRecords,
        promptTokens: result.promptTokens,
        completionTokens: result.completionTokens,
      );

      final s = _session!;
      var updated = s.copyWith(
        entries: [...s.entries, entry],
        updatedAt: DateTime.now(),
      );
      // 把备份挂到最后一条真正写盘的记录上，供 UI 显示「撤销」
      final backups = result.backups;
      if (backups.isNotEmpty) {
        updated = _attachBackups(updated, backups);
      }
      _session = updated;
      await _chatStore?.save(updated);

      if (result.aborted) {
        _lastError = '已中止';
      }
    } on AiException catch (e) {
      _lastError = e.toString();
      await _appendError(e.toString());
    } catch (e) {
      _lastError = '$e';
      await _appendError('$e');
    } finally {
      _busy = false;
      _streamingText = null;
      _runningTool = null;
      _sessions = await _chatStore?.listAll() ?? const [];
      notifyListeners();
    }
  }

  /// 中止当前请求。
  ///
  /// 目前只做「标记」，正在进行的 HTTP 请求会自然跑完 ——
  /// 真正的取消需要给 http 客户端加 CancelToken，属于后续优化。
  /// 至少用户不会看到卡住的界面。
  void cancel() {
    if (!_busy) return;
    _busy = false;
    _streamingText = null;
    _runningTool = null;
    _lastError = '已取消';
    notifyListeners();
  }

  // ── 回滚 ────────────────────────────────────────────

  /// 撤销某条 assistant 消息产生的所有写入。
  Future<bool> rollback(ChatEntry entry) async {
    final backups = entry.backups;
    if (backups.isEmpty) return false;

    final root = siteController?.repoPath;
    if (root == null) return false;

    var ok = true;
    for (final b in backups) {
      try {
        final abs = pkg.join(root, 'content', b.relPath);
        final f = File(abs);
        if (b.previous == null) {
          // 原本不存在 → 删掉
          if (await f.exists()) await f.delete();
        } else {
          await f.parent.create(recursive: true);
          await f.writeAsString(b.previous!);
        }
      } catch (_) {
        ok = false;
      }
    }

    // 撤销后刷新站点与文章列表
    siteController?.refresh();
    siteController?.notifyListeners();

    if (ok) {
      // 标记已撤销，避免重复点
      final s = _session;
      if (s != null) {
        final list = s.entries
            .map((e) => identical(e, entry) ? _stripBackup(e) : e)
            .toList();
        _session = s.copyWith(entries: list);
        await _chatStore?.save(_session!);
      }
      notifyListeners();
    }
    return ok;
  }

  /// 复制一条 entry 并清空 backups（用它表示「已撤销」）
  ChatEntry _stripBackup(ChatEntry e) => ChatEntry(
        role: e.role,
        text: e.text,
        at: e.at,
        toolCalls: e.toolCalls,
        isError: e.isError,
        promptTokens: e.promptTokens,
        completionTokens: e.completionTokens,
      );

  /// 把本轮产生的备份挂到最后一条 entry 上，供 UI 显示「撤销」。
  ///
  /// 会**追加**而不是覆盖：一次回答里模型可能写好几次文件，
  /// 覆盖会让之前那几次写入变得无法回滚。
  ChatSession _attachBackups(ChatSession s, List<WriteBackup> backups) {
    if (s.entries.isEmpty) return s;
    final last = s.entries.last;
    final merged = ChatEntry(
      role: last.role,
      text: last.text,
      at: last.at,
      toolCalls: last.toolCalls,
      isError: last.isError,
      backups: [...last.backups, ...backups],
      promptTokens: last.promptTokens,
      completionTokens: last.completionTokens,
    );
    final list = [...s.entries]..[s.entries.length - 1] = merged;
    return s.copyWith(entries: list);
  }

  // ── 内部 ────────────────────────────────────────────

  Future<void> _appendError(String msg) async {
    final s = _session;
    if (s == null) return;
    final updated = s.copyWith(
      entries: [
        ...s.entries,
        ChatEntry(
          role: 'assistant',
          text: msg,
          at: DateTime.now(),
          isError: true,
        ),
      ],
      updatedAt: DateTime.now(),
    );
    _session = updated;
    await _chatStore?.save(updated);
  }

  String _buildSystemPrompt() {
    final buf = StringBuffer();
    buf.writeln('你是 HugoSugar 的写作助手，帮用户把零散想法整理成能发布的 Hugo 文章。');
    buf.writeln();
    buf.writeln('规则：');
    buf.writeln('- 写文章前先调用 list_notes / search_notes 了解用户想法，'
        '用 read_post 学习已有文章的格式和文风。');
    buf.writeln('- 写入用 write_post，内容必须含完整 Front Matter'
        '（至少 title、date）。用户会审阅 Diff，可能拒绝。');
    buf.writeln('- fetch_url 仅在用户明确给出网址、或需要查证具体文档时使用。'
        '不要主动联网搜索，不要连续抓取同一网站的多个页面。');
    buf.writeln('- 不要重复写入同一个文件；用户拒绝后不要换个路径重试。');
    buf.writeln('- 回答用中文，简洁直接。');

    // 注入想法上下文
    final nc = noteController;
    if (nc != null) {
      final builder = NoteContextBuilder();
      final selection = builder.buildFromSettings(
        allNotes: nc.store.all,
        enabled: _readNotes,
        categoryIds: _categoryIds.toSet(),
      );
      _lastContext = selection;
      final block = selection.toPromptBlock();
      if (block.trim().isNotEmpty) {
        buf.writeln();
        buf.write(block);
      }
    }

    return buf.toString();
  }

  List<AiTool> _buildTools() {
    final nc = noteController;
    final posts = siteController?.posts ?? const [];
    final root = siteController?.repoPath ?? '';
    final contentAbs = pkg.join(root, 'content');

    return ToolRegistry(
      listNotes: () {
        final all = nc?.store.all ?? const <Note>[];
        // 与 system prompt 的注入范围保持一致：
        // 总开关关着且没指定分组时，工具也读不到。
        if (!_readNotes && _categoryIds.isEmpty) return const <Note>[];
        final alive = all.where((n) => !n.isDeleted).toList();
        if (_categoryIds.isEmpty) return alive;
        return alive
            .where((n) => n.categoryId != null &&
                _categoryIds.contains(n.categoryId))
            .toList();
      },
      readNote: (id) {
        final all = nc?.store.all ?? const <Note>[];
        if (!_readNotes && _categoryIds.isEmpty) return null;
        for (final n in all) {
          if (n.id == id && !n.isDeleted) return n;
        }
        return null;
      },
      searchNotes: (kw) {
        final all = nc?.store.all ?? const <Note>[];
        if (!_readNotes && _categoryIds.isEmpty) return const <Note>[];
        final k = kw.toLowerCase();
        return all
            .where((n) =>
                !n.isDeleted &&
                (n.title.toLowerCase().contains(k) ||
                    n.content.toLowerCase().contains(k)))
            .toList();
      },
      listPosts: () => posts
          .map((p) => (path: p.relativePath, title: p.title))
          .toList(),
      readPost: _readPostContent,
      writePost: _writePostContent,
      contentDirAbs: contentAbs,
      fetcher: _fetcher,
    ).build();
  }

  Future<String?> _readPostContent(String relPath) async {
    final root = siteController?.repoPath;
    if (root == null) return null;
    final cleaned = relPath.replaceAll('\\', '/');
    for (final candidate in [
      pkg.join(root, cleaned),
      pkg.join(root, 'content', cleaned),
    ]) {
      final f = File(candidate);
      if (await f.exists()) return f.readAsString();
    }
    return null;
  }

  Future<void> _writePostContent(String relPath, String content) async {
    final root = siteController?.repoPath;
    if (root == null) throw StateError('站点未就绪');
    final abs = pkg.join(root, 'content', relPath.replaceAll('\\', '/'));
    final f = File(abs);
    await f.parent.create(recursive: true);
    await f.writeAsString(content, flush: true);
    siteController?.refresh();
  }

  @override
  void dispose() {
    _client.dispose();
    _fetcher?.dispose();
    super.dispose();
  }
}