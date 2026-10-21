import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as pkg;

import '../note/note.dart';
import '../note/note_controller.dart';
import '../settings/app_settings.dart';
import '../site/site_controller.dart';
import 'agent_runner.dart';
import 'ai_client.dart';
import 'ai_endpoint.dart';
import 'ai_message.dart';
import 'cancel_token.dart';
import 'context_compressor.dart';
import 'chat_store.dart';
import 'memory_store.dart';
import 'default_prompt.dart';
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
    this.settings,
  }) : _client = client ?? AiClient();

  final AiClient _client;
  final NoteController? noteController;
  final SiteController? siteController;

  /// 读取用户偏好（自定义 System Prompt、token 上限）。
  ///
  /// 用接口 [SettingsControllerLike] 而不是具体实现，
  /// 是为了让 core/ai 不必 import features 层的设置控制器。
  final SettingsControllerLike? settings;

  AiEndpointStore? _endpointStore;
  AiKeyStore? _keyStore;
  ChatStore? _chatStore;

  /// 记忆库（关于用户的长期事实）
  MemoryStore? memoryStore;
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

  /// 当前流式输出的思考过程（null = 无思考内容）
  String? _streamingReasoning;
  String? get streamingReasoning => _streamingReasoning;

  bool _busy = false;
  bool get busy => _busy;

  /// 正在执行的工具名（给 UI 显示「正在读取…」）
  String? _runningTool;
  String? get runningTool => _runningTool;

  String? _lastError;
  String? get lastError => _lastError;

  /// 当前请求的取消令牌（null = 没有进行中的请求）
  CancelToken? _activeCancel;

  /// 上下文压缩器。用设置里的阈值构造，见 [_compressorOf]。
  ContextCompressor _compressorOf() {
    final st = settings;
    return ContextCompressor(
      maxMessages: st?.aiCompressThreshold ?? 20,
      keepRecent: st?.aiKeepRecent ?? 8,
    );
  }

  /// 上次发送时是否做了压缩，以及折叠了多少条
  bool _lastCompressed = false;
  int _lastDroppedCount = 0;

  bool get lastCompressed => _lastCompressed;
  int get lastDroppedCount => _lastDroppedCount;

  /// 上一次请求实际发出的消息条数（压缩后）
  int _lastSentCount = 0;
  int get lastSentCount => _lastSentCount;

  /// 上一次请求实际发出的 token 估算（压缩后）
  int _lastSentTokens = 0;
  int get lastSentTokens => _lastSentTokens;

  /// 当前会话的上下文占用比例（0.0 ~ 1.0）。
  ///
  /// 分母用**压缩阈值**而不是模型真实上下文窗口：
  /// 我们不知道用户接的是 64K 还是 8K 的模型，但「离触发压缩还有多远」
  /// 是确定的，也是用户唯一能据此行动的数字。
  double get contextUsageRatio {
    final limit = settings?.aiCompressThreshold ?? 20;
    if (limit <= 0) return 0;
    return (_currentCount / limit).clamp(0.0, 1.0);
  }

  /// 当前会话的消息条数（未压缩时的原始条数）
  int get _currentCount => _session?.entries.length ?? 0;
  int get currentEntryCount => _currentCount;

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

    // 记忆库与对话存在同一层目录（ai/memories.json）
    final base = await getApplicationSupportDirectory();
    memoryStore = MemoryStore.at(Directory('${base.path}/ai'));
    await memoryStore!.load();
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
    ThinkingMode thinkingMode = ThinkingMode.none,
  }) async {
    final id = 'ep_${DateTime.now().microsecondsSinceEpoch}';
    final ep = AiEndpoint(
      id: id,
      name: name.trim().isEmpty ? baseUrl : name.trim(),
      baseUrl: baseUrl.trim(),
      model: model.trim(),
      keyHint: apiKey.isEmpty ? '' : AiKeyStore.mask(apiKey),
      thinkingMode: thinkingMode,
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
    if (_busy) return;
    if (_config.activeId == id) return;
    _config = _config.copyWith(activeId: id);
    await _endpointStore?.save(_config);
    await _syncSessionEndpoint();
    notifyListeners();
  }

  Future<void> setEndpointModel(String endpointId, String model) async {
    final list = _config.endpoints
        .map((e) => e.id == endpointId ? e.copyWith(model: model) : e)
        .toList();
    _config = _config.copyWith(endpoints: list);
    await _endpointStore?.save(_config);
    await _syncSessionEndpoint();
    notifyListeners();
  }

  /// 对话页的快速切换：一次调用同时可换端点、换模型。
  ///
  /// 为什么不复用 [setActiveEndpoint] + [setEndpointModel] 两次调用：
  /// 中间会各写一次磁盘、各 notify 一次，UI 会闪两下；
  /// 更重要的是「改端点」和「改模型」必须原子生效，
  /// 否则中途有一瞬间是「新端点 + 旧模型名」这种非法组合。
  ///
  /// [endpointId] 为空 / [model] 为空时表示不改该项。
  /// 发送中拒绝切换：正在跑的请求已经带着旧端点飞出，
  /// 中途换会让会话记录与实际请求对不上。
  Future<bool> switchModel({String? endpointId, String? model}) async {
    if (_busy) return false;

    final targetId = (endpointId ?? '').trim().isEmpty
        ? (_config.activeId.isEmpty
            ? (activeEndpoint?.id ?? '')
            : _config.activeId)
        : endpointId!.trim();
    if (targetId.isEmpty) return false;

    var cfg = _config;
    if (cfg.activeId != targetId) {
      cfg = cfg.copyWith(activeId: targetId);
    }

    final newModel = model?.trim() ?? '';
    if (newModel.isNotEmpty) {
      final list = cfg.endpoints
          .map((e) => e.id == targetId ? e.copyWith(model: newModel) : e)
          .toList();
      cfg = cfg.copyWith(endpoints: list);
    }

    _config = cfg;
    await _endpointStore?.save(_config);
    await _syncSessionEndpoint();
    notifyListeners();
    return true;
  }

  /// 切换后把「这次对话用的是哪个端点/模型」同步进会话，
  /// 历史记录里才能看出每条对话当时挂在什么模型上。
  Future<void> _syncSessionEndpoint() async {
    final s = _session;
    if (s == null) return;
    final ep = activeEndpoint;
    if (ep == null) return;
    if (s.endpointId == ep.id && s.model == ep.model) return;
    _session = s.copyWith(endpointId: ep.id, model: ep.model);
    await _chatStore?.save(_session!);
  }

  /// 某个端点的模型列表缓存（端点 id → 模型 id 列表）。
  ///
  /// 快速切换面板每次打开都去拉一次 `/models` 太慢（几百毫秒起步），
  /// 而模型清单基本不变。缓存后第二次打开是瞬时的，
  /// 用户想刷新时再显式点「刷新」。
  final Map<String, List<String>> _modelCache = {};

  List<String>? cachedModels(String endpointId) => _modelCache[endpointId];

  /// 拉取并缓存某端点的模型列表。失败时抛出 [AiException]。
  Future<List<String>> loadModels(String endpointId) async {
    AiEndpoint? ep;
    for (final e in _config.endpoints) {
      if (e.id == endpointId) ep = e;
    }
    if (ep == null) return const [];

    final key = await readKey(endpointId) ?? '';
    final models = await _client.listModels(endpoint: ep, apiKey: key);
    final ids = models
        .where((m) => m.looksChatCapable)
        .map((m) => m.id)
        .toList();
    _modelCache[endpointId] = ids;
    return ids;
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
  Future<bool> send(
    String userText, {
    required Future<ApprovalDecision?> Function(ApprovalRequest req)
        onApproval,
  }) async {
    if (_busy) return false;

    final text = userText.trim();
    if (text.isEmpty) return false;

    final ep = activeEndpoint;
    if (ep == null) {
      _lastError = '还没有配置 AI 端点';
      notifyListeners();
      return false;
    }
    if (ep.model.trim().isEmpty) {
      _lastError = '还没有为「${ep.name}」选择模型';
      notifyListeners();
      return false;
    }

    final key = await readKey(ep.id);
    if (key == null || key.isEmpty) {
      _lastError = '还没有填写「${ep.name}」的 API Key';
      notifyListeners();
      return false;
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

    final cancelToken = CancelToken();
    _activeCancel = cancelToken;

    _busy = true;
    _streamingText = '';
    _streamingReasoning = null;
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

    // 压缩历史，避免长对话把上下文窗口撑爆。
    //
    // 放在 toApiMessages 之后、发请求之前：
    // 早压缩没有意义（还不知道会不会超），晚压缩就来不及了。
    // 用 s0（不含本次输入）作为历史。
    //
    // withUser 里已经有这条 user 消息了，而 AgentRunner.run 会在末尾
    // 再补一条 —— 直接传 withUser 会让模型收到两遍同样的问题。
    final rawMessages = s0.toApiMessages();
    final compressed = _compressorOf().compress(rawMessages);
    _lastCompressed = compressed.compressed;
    _lastDroppedCount = compressed.droppedCount;
    _lastSentCount = compressed.messages.length;
    _lastSentTokens = estimateMessagesTokens(compressed.messages) +
        estimateTokens(_buildSystemPrompt());

    final systemPrompt = _buildSystemPrompt();
    final tools = _buildTools();
    final runner = AgentRunner(
      client: _client,
      tools: tools,
      readPost: _readPostContent,
      // 规格：单轮 token 上限「由配置决定」，不是写死的常量
      maxTokensPerRound: settings?.aiMaxTokensPerRound ?? 120000,
    );

    final streamed = StringBuffer();
    final toolRecords = <ToolCallRecord>[];

    try {
      final result = await runner.run(
        endpoint: ep,
        apiKey: key,
        baseMessages: compressed.messages,
        userText: text,
        systemPrompt: systemPrompt,
        cancelToken: cancelToken,
        callbacks: AgentCallbacks(
          onTextDelta: (d) {
            streamed.write(d);
            _streamingText = streamed.toString();
            notifyListeners();
          },
          // 思考过程。模型不返回就一次都不会触发，
          // 那时 _streamingReasoning 保持 null，UI 不显示思考区。
          onReasoningDelta: (d) {
            _streamingReasoning = (_streamingReasoning ?? '') + d;
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
        // 服务端给了 usage 才是真值，否则是估算。
        // 界面必须能区分，不能把估算当账单展示。
        usageIsExact: result.usageIsExact,
        reasoning: result.reasoning,
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
    } on CancelledException {
      // 用户主动取消：把已经收到的内容保留下来。
      //
      // 不写错误气泡 —— 取消是正常操作，不是失败。
      // 但也不能什么都不留：用户可能已经看到一半有用内容，
      // 刷新后消失会以为程序坏了。
      await _commitPartial(streamed.toString(), toolRecords);
      _lastError = null;
    } on AiException catch (e) {
      // 不设 _lastError：错误已经作为一条对话消息入流了，
      // 再在顶部弹一条错误条就是同一句话说两遍。
      await _appendError(e.toString());
    } catch (e) {
      await _appendError('$e');
    } finally {
      _busy = false;
      _streamingText = null;
      _streamingReasoning = null;
      _runningTool = null;
      _activeCancel = null;
      _sessions = await _chatStore?.listAll() ?? const [];
      notifyListeners();
    }
    return true;
  }

  // ── 撤回 / 重发 / 编辑 ──────────────────────────────

  /// 撤回。
  ///
  /// 两种粒度，语义必须分清：
  ///   - [fromIndex] 及之后全部删掉（默认，用于 user 消息）
  ///   - 只删这一条（[single] = true，用于 assistant 消息）
  ///
  /// 为什么 assistant 消息要支持「只删这条」：
  /// 用户可能只是觉得这次回答不好，想再问一次那个问题 ——
  /// 把提问也删掉就得重新打字。
  ///
  /// 返回撤销的文件数；`-1` 表示失败。
  Future<int> recallFromEntry(
    ChatEntry entry, {
    required bool rollbackFiles,
    bool single = false,
  }) async {
    if (_busy) return -1;
    final s = _session;
    if (s == null) return -1;

    final idx = s.entries.indexOf(entry);
    if (idx < 0) return -1;

    final removed = single ? [entry] : s.entries.sublist(idx);

    var rolledBack = 0;
    if (rollbackFiles) {
      // 从后往前撤，保证同一文件被写过多次时恢复到最早的版本。
      //
      // 举例：模型先写 A，后来又改 A。如果正序撤销，
      // 先恢复成「第一次写之前」的内容，再恢复成「第二次写之前」的内容，
      // 最终留下的是中间态 —— 顺序反了。
      for (final e in removed.reversed) {
        for (final b in e.backups.reversed) {
          if (await _restoreBackup(b)) rolledBack++;
        }
      }
      siteController?.refresh();
      siteController?.notifyListeners();
    }

    final kept = single
        ? ([...s.entries]..removeAt(idx))
        : s.entries.sublist(0, idx);

    _session = s.copyWith(
      entries: kept,
      updatedAt: DateTime.now(),
      // 撤回后如果一条不剩，标题回到「新对话」，
      // 否则列表里会留着一条空会话顶着旧标题
      title: kept.isEmpty ? '新对话' : s.title,
    );
    await _chatStore?.save(_session!);
    _sessions = await _chatStore?.listAll() ?? const [];
    notifyListeners();
    return rolledBack;
  }

  /// 把一条用户消息改成新内容后**重新发送**。
  ///
  /// 语义等同于「撤回这条及之后所有内容，再用新文本发一次」。
  /// 所以它必然同时回滚文件 —— 因为那些写入是基于旧提问产生的，
  /// 留着会和新的回答叠在一起。
  ///
  /// [onApproval] 同 [send]。
  Future<bool> editAndResend(
    ChatEntry entry,
    String newText, {
    required Future<ApprovalDecision?> Function(ApprovalRequest req) onApproval,
  }) async {
    if (_busy) return false;
    if (!entry.isUser) return false;
    final text = newText.trim();
    if (text.isEmpty) return false;

    await recallFromEntry(entry, rollbackFiles: true);
    return send(text, onApproval: onApproval);
  }

  /// 对同一条提问再生成一次回答，保留之前的回答。
  ///
  /// ## 与 resend 的区别（关键，两者语义不同）
  ///
  /// - resend：删除旧回答，并回滚文件。适合「答得不好，要替换」。
  /// - regenerate：保留旧回答，不回滚文件。适合「想比较几种写法」。
  ///
  /// 为什么不回滚文件：旧回答写的文章还在，用户可能想留着对比。
  /// 若新回答写同一路径会覆盖旧的 —— 那是用户自己选的路径冲突，
  /// 交给审批弹窗处理。
  ///
  /// ## 实现要点
  ///
  /// 不走「先删再加」，而是：
  /// 1. 取最后一条 user 消息之前的历史作为 base
  /// 2. 再调一次 runner
  /// 3. 新回答追加在末尾（旧的仍在上面）
  ///
  /// 不能把旧回答也当历史喂进去 —— 模型会以为那是别人的答复，
  /// 然后倾向于「延续」而不是重新回答，输出会和旧的几乎一样。
  Future<bool> regenerate({
    required Future<ApprovalDecision?> Function(ApprovalRequest req) onApproval,
  }) async {
    if (_busy) return false;
    final s = _session;
    if (s == null || s.entries.isEmpty) return false;

    var lastUserIdx = -1;
    for (var i = s.entries.length - 1; i >= 0; i--) {
      if (s.entries[i].isUser) {
        lastUserIdx = i;
        break;
      }
    }
    if (lastUserIdx < 0) return false;

    final question = s.entries[lastUserIdx].text;
    final base = s.copyWith(entries: s.entries.sublist(0, lastUserIdx));
    _session = base;
    notifyListeners();

    return send(question, onApproval: onApproval);
  }
  /// 重发：撤回这条用户消息，原样再发一遍。
  Future<bool> resend(
    ChatEntry entry, {
    required Future<ApprovalDecision?> Function(ApprovalRequest req) onApproval,
  }) async {
    if (!entry.isUser) return false;
    return editAndResend(entry, entry.text, onApproval: onApproval);
  }

  /// 删除单条消息（不动文件）。
  ///
  /// 用于「这条助手回复没用/这条提问打错了」这种清理场景。
  /// 不提供批量 —— 批量的语义已经被 [recallFromEntry] 覆盖。
  Future<bool> deleteEntry(ChatEntry entry) async {
    if (_busy) return false;
    final s = _session;
    if (s == null) return false;

    final idx = s.entries.indexOf(entry);
    if (idx < 0) return false;

    final list = [...s.entries]..removeAt(idx);
    _session = s.copyWith(entries: list, updatedAt: DateTime.now());
    await _chatStore?.save(_session!);
    _sessions = await _chatStore?.listAll() ?? const [];
    notifyListeners();
    return true;
  }

  /// 恢复一个备份。返回是否真的动了文件。
  Future<bool> _restoreBackup(WriteBackup b) async {
    final root = siteController?.repoPath;
    if (root == null) return false;
    try {
      final abs = pkg.join(root, 'content', b.relPath);
      final f = File(abs);
      if (b.previous == null) {
        // 原本不存在 → 删掉
        if (await f.exists()) await f.delete();
        return true;
      }
      await f.parent.create(recursive: true);
      await f.writeAsString(b.previous!);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 清掉界面上的错误条。
  void clearError() {
    if (_lastError == null) return;
    _lastError = null;
    notifyListeners();
  }

  /// 中止当前请求。
  ///
  /// 通过 [CancelToken] 让流式循环在当前分片后退出，
  /// 真正停止接收后续 token —— 不是只让 UI 不再等。
  ///
  /// 已收到的内容**保留**：用户点停止通常是因为
  /// 「要的部分已经出来了」，把它丢掉才是意外行为。
  /// 收尾由 [send] 的 finally 负责（那里会落盘）。
  void cancel() {
    final token = _activeCancel;
    if (token == null || token.isCancelled) return;
    token.cancel();
    // 同样不设 _lastError：取消是用户主动操作，不是错误。
    // 已经收到的内容会由 _commitPartial 带着「(已取消)」留痕。
    notifyListeners();
  }

  /// 发送前的同步检查。
  ///
  /// 返回 null = 可以发；否则是给用户看的原因。
  /// UI 必须在**清空输入框之前**调用，否则用户的关键输入会被吞掉。
  String? validateSend() {
    final ep = activeEndpoint;
    if (ep == null) return '还没有配置 AI 端点';
    if (ep.model.trim().isEmpty) return '还没有为「${ep.name}」选择模型';
    return null;
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

  /// 把取消前收到的部分内容存进历史。
  ///
  /// 空内容（还没吐出任何 token）时什么都不写 ——
  /// 造一条空白消息只会让人困惑。
  Future<void> _commitPartial(
    String text,
    List<ToolCallRecord> toolCalls,
  ) async {
    if (text.trim().isEmpty && toolCalls.isEmpty) return;
    final s = _session;
    if (s == null) return;

    final entry = ChatEntry(
      role: 'assistant',
      text: text.trim().isEmpty ? '（已取消）' : '$text\n\n_(已取消)_',
      at: DateTime.now(),
      toolCalls: toolCalls,
      // 取消时也保留已经产生的思考内容：
      // 用户点停止往往是因为「想看的已经看到了」，
      // 而思考过程恰恰是判断模型思路的关键。
      reasoning: _streamingReasoning ?? '',
    );
    final updated = s.copyWith(
      entries: [...s.entries, entry],
      updatedAt: DateTime.now(),
    );
    _session = updated;
    await _chatStore?.save(updated);
  }

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
    // 决议 5：用户覆盖优先，没有覆盖才用内置默认。
    // 空串表示「未覆盖」而不是「用空 Prompt」—— 后者会让模型完全
    // 失去角色约束，但那几乎不可能是用户想要的。
    final custom = settings?.aiSystemPrompt.trim() ?? '';
    buf.writeln(custom.isEmpty ? kDefaultSystemPrompt.trim() : custom);
    buf.writeln();

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

    // 注入记忆库。
    //
    // 放在想法上下文之后：想法是「素材」，记忆是「你是谁」，
    // 后者更底层，靠后一点模型更容易把它当背景而不是当前任务。
    final mem = memoryStore?.toPromptBlock() ?? '';
    if (mem.trim().isNotEmpty) {
      buf.writeln();
      buf.write(mem);
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
          // 必须给**相对 content 目录**的路径。
          //
          // PostDocument.relativePath 是相对仓库根的
          // （content/posts/a.md），而 write_post 的 path_guard
          // 基准是 content 目录。两边不一致的后果是：
          // 模型照抄它看到的路径去写，_writePostContent 再拼一次
          // content/，最终落到 content/content/posts/a.md ——
          // 文件确实写成功了（审批里也显示成功），
          // 但 _refreshPosts 扫的是 content/posts，永远看不到它。
          //
          // 表现就是「AI 说写好了，文章列表里没有」。
          .map((p) => (
                path: pkg.posix.relative(
                  p.relativePath.replaceAll('\\', '/'),
                  from: 'content',
                ),
                title: p.title,
              ))
          .toList(),
      readPost: _readPostContent,
      writePost: _writePostContent,
      contentDirAbs: contentAbs,
      fetcher: _fetcher,
      memoryStore: memoryStore,
    ).build();
  }

  /// 读文章内容（审批 Diff + 回滚备份都走这里）。
  ///
  /// 路径基准与 [write_post] 的 path_guard 一致：**相对 content 目录**。
  /// 同时兼容 `content/posts/a.md` 这种带 content 前缀的历史写法 ——
  /// 早期 listPosts 给的就是这种，旧会话里还留着。
  Future<String?> _readPostContent(String relPath) async {
    final root = siteController?.repoPath;
    if (root == null) return null;
    final cleaned = relPath.replaceAll('\\', '/');

    // content 基准优先；带前缀的写法其次
    final candidates = <String>[
      pkg.join(root, 'content', cleaned),
      pkg.join(root, cleaned),
    ];

    for (final candidate in candidates) {
      final f = File(candidate);
      if (await f.exists()) return f.readAsString();
    }
    return null;
  }

  Future<void> _writePostContent(String relPath, String content) async {
    final root = siteController?.repoPath;
    if (root == null) throw StateError('站点未就绪');

    // 与 path_guard 保持同一基准：相对 content。
    // 若模型仍传了 `content/xxx`（旧会话残留的写法），剥掉前缀，
    // 否则会写出 content/content/xxx。
    var cleaned = relPath.replaceAll('\\', '/');
    if (cleaned.startsWith('content/')) {
      cleaned = cleaned.substring('content/'.length);
    }

    final abs = pkg.join(root, 'content', cleaned);
    final f = File(abs);
    await f.parent.create(recursive: true);
    await f.writeAsString(content, flush: true);
    siteController?.refresh();
  }

  @visibleForTesting
  void debugSetSession(ChatSession? s) {
    _session = s;
    notifyListeners();
  }

  @visibleForTesting
  void debugSetConfig(AiConfig cfg) {
    _config = cfg;
    notifyListeners();
  }

  @visibleForTesting
  void debugSetBusy(bool v) {
    _busy = v;
    notifyListeners();
  }

  @visibleForTesting
  void debugSetError(String? msg) {
    _lastError = msg;
    notifyListeners();
  }

  @override
  void dispose() {
    _client.dispose();
    _fetcher?.dispose();
    super.dispose();
  }
}