import 'dart:async';
import 'package:hugosugar/app/i18n/l10n_scope.dart';

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/reading_prefs.dart';
import '../../core/edit/undo_history.dart';
import '../../core/post/front_matter.dart';
import '../../core/site/site_controller.dart';
import '../../core/ai/ai_controller.dart';
import '../../core/ai/ai_client.dart';
import '../ai/chat_markdown.dart';
import 'markdown_highlighter.dart';
import '../../shared/chip_editor.dart';
import 'markdown_toolbar.dart';

/// 保存状态
enum _SaveState { idle, dirty, saving, saved, failed }

/// 编辑器：全屏、无 Tab、顶栏自动淡出。
///
/// 设计要点（见设计规范 §3.2）：
/// - 输入 2 秒后顶栏淡到 0.15，点任意处恢复
/// - 底部只显示字数与保存状态
/// - 正文行高 1.75，左右边距 20
///
/// 保存策略：**停笔 2 秒自动保存**。这与顶栏淡出用的是同一个计时器，
/// 但职责分开 —— 淡出是视觉，保存是数据，各自有各自的开关。
class EditorPage extends StatefulWidget {
  const EditorPage({
    super.key,
    required this.title,
    this.relativePath,
    this.controller,
    this.aiController,
  });

  final String title;

  /// 相对站点根的文件路径，如 content/posts/hello.md
  final String? relativePath;

  /// 用来读写文件；为空时编辑器不落盘
  final SiteController? controller;

  /// 写作 AI。为空时「AI」按钮提示未接入（理论上主流程都会传入）。
  final AiController? aiController;

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  late final TextEditingController _titleCtrl;
  late final MarkdownEditingController _bodyCtrl = MarkdownEditingController();
  final _bodyFocus = FocusNode();
  final _scrollCtrl = ScrollController();

  Timer? _chromeTimer;
  Timer? _saveTimer;
  bool _chromeVisible = true;

  /// 撤销 / 重做
  final _history = EditHistory();

  /// 正在执行撤销 / 重做，此时文本变更是「程序化」的，不记历史
  bool _applyingHistory = false;

  bool _loading = false;
  String? _loadError;

  /// 原文档，用于保留未知 Front Matter 键
  PostDocument? _original;

  _SaveState _saveState = _SaveState.idle;
  String? _saveError;

  /// 是否已加载完成（避免加载过程中触发自动保存）
  bool _ready = false;

  // 查找替换
  bool _findOpen = false;
  final _findCtrl = TextEditingController();
  final _replaceCtrl = TextEditingController();
  List<int> _matches = const [];
  int _matchIndex = 0;

  /// 预览模式：正文区从「可编辑源码」切换成「富文本渲染」，留在编辑器内，
  /// 不弹面板、不遮正文。再点一次切回编辑。
  bool _previewMode = false;

  /// 写作 AI 面板是否内联展开（贴在底部工具栏上方，不用模态遮罩）。
  bool _aiOpen = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.title);
    _bodyCtrl.addListener(_onBodyChanged);
    _titleCtrl.addListener(_onTitleChanged);
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 主题色只在拿到 context 后才知道。这里只更新控制器内部颜色，
    // 不换实例 —— 换实例会丢焦点、选区，还可能触发一次重建。
    final c = context.appColors;
    _bodyCtrl.applyTheme(
      accent: c.accent,
      dim: c.textTertiary,
      codeBg: c.surface,
    );
  }

  Future<void> _load() async {
    final path = widget.relativePath;
    final ctrl = widget.controller;
    if (path == null || ctrl == null) {
      // 新建空稿，直接可编辑
      _ready = true;
      _history.seed(_titleCtrl.text, _bodyCtrl.text);
      return;
    }

    setState(() => _loading = true);
    final doc = await ctrl.readPost(path);
    if (!mounted) return;

    if (doc == null) {
      setState(() {
        _loading = false;
        _loadError = TP('无法读取文件：{}', [path]);
        _ready = true;
      });
      return;
    }

    _titleCtrl.text = doc.title;
    _bodyCtrl.text = doc.body;
    setState(() {
      _loading = false;
      _original = doc;
      _ready = true;
      // 刚读入的内容不算改动
      _saveState = _SaveState.idle;
    });
    // 载入后的状态是撤销栈的起点
    _history.seed(doc.title, doc.body);
  }

  /// 是否已删除本文。删除后要阻止 dispose 里的兜底保存，
  /// 否则「删了又被写回来」—— 因为 _flushOnExit 会把内存内容重新落盘。
  bool _deleted = false;

  @override
  void dispose() {
    _chromeTimer?.cancel();
    _saveTimer?.cancel();
    // 离开时若还有未保存内容，尽力保存一次（不阻塞 UI）
    if (!_deleted) _flushOnExit();
    _bodyCtrl.removeListener(_onBodyChanged);
    _titleCtrl.removeListener(_onTitleChanged);
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    _bodyFocus.dispose();
    _findCtrl.dispose();
    _replaceCtrl.dispose();
    _scrollCtrl.dispose();
    _history.dispose();
    super.dispose();
  }

  void _flushOnExit() {
    if (_saveState == _SaveState.dirty) {
      // fire-and-forget：dispose 里不能 await
      _save(quiet: true);
    }
  }

  // ── 变更追踪 ─────────────────────────────────────

  void _onBodyChanged() {
    if (!_ready) return;
    _markDirty();
    _onTyping();
    _recordHistory();
    if (_findOpen) _recomputeMatches();
  }

  void _onTitleChanged() {
    if (!_ready) return;
    _markDirty();
    // 改标题也算「正在写」，应该和改正文一样重置淡出计时器。
    // 之前漏了这一行，导致在标题里打字时顶栏可能就在你眼前暗下去。
    _onTyping();
    _recordHistory();
  }

  // ── 撤销 / 重做 ──────────────────────────────────

  void _recordHistory() {
    // 撤销本身触发的文本变更不能再入栈，否则会产生「撤销的历史」
    if (_applyingHistory) return;
    _history.record(_titleCtrl.text, _bodyCtrl.text);
    // canUndo 变化要反映到工具栏按钮上
    setState(() {});
  }

  void _undo() {
    final snap = _history.undo();
    if (snap == null) return;
    _applySnapshot(snap);
  }

  void _redo() {
    final snap = _history.redo();
    if (snap == null) return;
    _applySnapshot(snap);
  }

  /// 把快照写回两个输入框。
  ///
  /// 必须 mute 掉 record，用 _applyingHistory 挡着；同时把光标放在末尾，
  /// 因为原文长度变了，旧的光标位置可能越界。
  void _applySnapshot(EditSnapshot snap) {
    _applyingHistory = true;
    _history.mute(true);
    if (_titleCtrl.text != snap.title) {
      _titleCtrl.value = TextEditingValue(
        text: snap.title,
        selection: TextSelection.collapsed(offset: snap.title.length),
      );
    }
    if (_bodyCtrl.text != snap.body) {
      _bodyCtrl.value = TextEditingValue(
        text: snap.body,
        selection: TextSelection.collapsed(offset: snap.body.length),
      );
    }
    _history.mute(false);
    _applyingHistory = false;

    _markDirty();
    _onTyping();
    setState(() {});
  }

  void _markDirty() {
    if (_saveState == _SaveState.dirty) return;
    setState(() => _saveState = _SaveState.dirty);
    _scheduleSave();
  }

  /// 停笔 2 秒后保存
  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      _save();
    });
  }

  Future<void> _save({bool quiet = false}) async {
    final ctrl = widget.controller;
    final path = widget.relativePath;

    // 没有落盘目标（新建但未创建的稿件）就不保存
    if (ctrl == null || path == null) {
      if (!quiet) {
        setState(() {
          _saveState = _SaveState.idle;
          _saveError = T('这篇稿件还没有文件路径，无法保存');
        });
      }
      return;
    }

    if (_saveState == _SaveState.saving) return;

    setState(() {
      _saveState = _SaveState.saving;
      _saveError = null;
    });

    final result = await ctrl.savePost(
      relativePath: path,
      title: _titleCtrl.text,
      body: _bodyCtrl.text,
      original: _original,
    );

    if (!mounted) return;
    setState(() {
      if (result.ok) {
        _saveState = _SaveState.saved;
        // 保存后刷新 original 的 Front Matter，供下次保存合并
      } else {
        _saveState = _SaveState.failed;
        _saveError = result.message;
      }
    });

    if (result.ok) {
      // 重新读一次，让 _original 反映刚写入的内容（含自动更新的日期等）
      final fresh = await ctrl.readPost(path);
      if (fresh != null && mounted) {
        setState(() => _original = fresh);
      }
    }
  }

  // ── 顶栏淡出 ─────────────────────────────────────

  void _onTyping() {
    if (!_chromeVisible) setState(() => _chromeVisible = true);
    _chromeTimer?.cancel();
    _chromeTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() => _chromeVisible = false);
    });
  }

  void _reveal() {
    // 关键：先停掉淡出计时器。
    // 之前这里只把 opacity 改回 1，但那个 2 秒计时器还在跑，
    // 于是「点一下亮了 → 2 秒后又暗」——用户感受就是点了没用。
    // 停掉之后，顶栏保持可见，直到下一次真正开始打字才重新计时。
    _chromeTimer?.cancel();
    _chromeTimer = null;
    if (_chromeVisible) return;
    setState(() => _chromeVisible = true);
  }

  int get _charCount => _bodyCtrl.text.replaceAll(RegExp(r'\s'), '').length;

  // ── 查找替换 ─────────────────────────────────────

  void _toggleFind() {
    setState(() {
      _findOpen = !_findOpen;
      if (!_findOpen) {
        _matches = const [];
        _matchIndex = 0;
      }
    });
    if (_findOpen && _bodyCtrl.selection.isValid) {
      // 如果编辑器里已选中文本，直接拿来做查找词
      final sel = _bodyCtrl.selection;
      if (sel.start != sel.end) {
        _findCtrl.text = _bodyCtrl.text.substring(sel.start, sel.end);
      }
      _recomputeMatches();
    }
  }

  void _recomputeMatches() {
    final q = _findCtrl.text;
    if (q.isEmpty) {
      setState(() {
        _matches = const [];
        _matchIndex = 0;
      });
      return;
    }
    final text = _bodyCtrl.text;
    final found = <int>[];
    var from = 0;
    while (true) {
      final i = text.indexOf(q, from);
      if (i < 0) break;
      found.add(i);
      from = i + q.length;
      // 防御空匹配死循环
      if (q.isEmpty) break;
    }
    setState(() {
      _matches = found;
      if (found.isEmpty) {
        _matchIndex = 0;
      } else if (_matchIndex >= found.length) {
        _matchIndex = 0;
      }
    });
  }

  void _findNext({bool backwards = false}) {
    if (_matches.isEmpty) return;
    setState(() {
      if (backwards) {
        _matchIndex = (_matchIndex - 1 + _matches.length) % _matches.length;
      } else {
        _matchIndex = (_matchIndex + 1) % _matches.length;
      }
    });
    _selectCurrentMatch();
  }

  void _selectCurrentMatch() {
    if (_matches.isEmpty) return;
    final start = _matches[_matchIndex];
    final end = start + _findCtrl.text.length;
    _bodyCtrl.selection = TextSelection(baseOffset: start, extentOffset: end);
    _bodyFocus.requestFocus();
    // 粗略滚动定位：按字符比例估算，足够用
    if (_scrollCtrl.hasClients) {
      final total = _bodyCtrl.text.length;
      if (total > 0) {
        final ratio = start / total;
        final max = _scrollCtrl.position.maxScrollExtent;
        _scrollCtrl.animateTo(
          (max * ratio).clamp(0.0, max),
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    }
  }

  /// 替换当前匹配
  void _replaceCurrent() {
    if (_matches.isEmpty) return;
    final start = _matches[_matchIndex];
    final end = start + _findCtrl.text.length;
    final text = _bodyCtrl.text;
    final replaced =
        '${text.substring(0, start)}${_replaceCtrl.text}'
        '${text.substring(end)}';
    _bodyCtrl.value = TextEditingValue(
      text: replaced,
      selection: TextSelection.collapsed(
        offset: start + _replaceCtrl.text.length,
      ),
    );
    _recomputeMatches();
    if (_matches.isNotEmpty) _selectCurrentMatch();
  }

  /// 全部替换
  void _replaceAll() {
    final q = _findCtrl.text;
    if (q.isEmpty) return;
    final count = _matches.length;
    if (count == 0) return;

    final text = _bodyCtrl.text;
    _bodyCtrl.text = text.replaceAll(q, _replaceCtrl.text);
    _recomputeMatches();

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(TP('已替换 {} 处', [count]))));
  }

  // ── 界面 ─────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final topInset = MediaQuery.of(context).padding.top;

    return Scaffold(
      // 用 Listener 而不是 GestureDetector：
      // GestureDetector 的 onTap 会被下面的 TextField 竞争掉（TextField 自己要处理
      // 点击定位光标），外层根本收不到。Listener 走的是指针事件，命中链上每一层
      // 都会收到，所以在正文里点一下一定能唤回顶栏。
      body: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _reveal(),
        child: Stack(
          children: [
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 52),
                    // 标题
                    TextField(
                      controller: _titleCtrl,
                      style: AppTypography.editorTitle.copyWith(
                        color: c.textPrimary,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        filled: false,
                        contentPadding: EdgeInsets.zero,
                        hintText: context.tr(T('标题')),
                        hintStyle: AppTypography.editorTitle.copyWith(
                          color: c.textTertiary,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
                      maxLines: null,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: AppSpace.xs),
                    // 元信息
                    Row(
                      children: [
                        Text(
                          _original?.statusLabel ?? T('草稿'),
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            color: c.textTertiary,
                          ),
                        ),
                        const SizedBox(width: AppSpace.xs),
                        Text('·', style: TextStyle(color: c.textTertiary)),
                        const SizedBox(width: AppSpace.xs),
                        Text(
                          _loading ? T('读取中…') : TP('{} 字', [_charCount]),
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            color: c.textTertiary,
                          ),
                        ),
                      ],
                    ),
                    if (_loadError != null) ...[
                      const SizedBox(height: AppSpace.xxs),
                      Text(
                        _loadError!,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          color: c.danger,
                        ),
                      ),
                    ],
                    if (_findOpen)
                      _FindBar(
                        findCtrl: _findCtrl,
                        replaceCtrl: _replaceCtrl,
                        matchCount: _matches.length,
                        current: _matches.isEmpty ? 0 : _matchIndex + 1,
                        onChanged: _recomputeMatches,
                        onPrev: () => _findNext(backwards: true),
                        onNext: _findNext,
                        onReplace: _replaceCurrent,
                        onReplaceAll: _replaceAll,
                        onClose: _toggleFind,
                      ),
                    const SizedBox(height: AppSpace.md),
                    // 正文：预览模式渲染富文本，编辑模式是可编辑源码。
                    Expanded(
                      child: _previewMode
                          ? _buildPreviewBody(c)
                          : TextField(
                              controller: _bodyCtrl,
                              focusNode: _bodyFocus,
                              scrollController: _scrollCtrl,
                              maxLines: null,
                              expands: true,
                              textAlignVertical: TextAlignVertical.top,
                              keyboardType: TextInputType.multiline,
                              style: context.reading.apply(
                                AppTypography.editorBody.copyWith(
                                  color: c.textPrimary,
                                ),
                              ),
                              decoration: InputDecoration(
                                filled: false,
                                contentPadding: EdgeInsets.zero,
                                hintText: context.tr(T('正文…')),
                                hintStyle: context.reading.apply(
                                  AppTypography.editorBody.copyWith(
                                    color: c.textTertiary,
                                  ),
                                ),
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                              ),
                            ),
                    ),
                    // 内联写作 AI 面板（非模态，不遮正文）
                    if (_aiOpen)
                      _WriteAiPanelInline(
                        ai: widget.aiController,
                        currentBody: _bodyCtrl.text,
                        onInsert: (text) {
                          _applyAiResult(text, replaceAll: false);
                          setState(() => _aiOpen = false);
                        },
                        onReplaceAll: (text) {
                          _applyAiResult(text, replaceAll: true);
                          setState(() => _aiOpen = false);
                        },
                        onClose: () => setState(() => _aiOpen = false),
                      ),
                    // 给固定显示的底部区域留高度：工具栏 46 + 状态行 44 + 底部安全区
                    SizedBox(
                      height: 46 + 44 + MediaQuery.of(context).padding.bottom,
                    ),
                  ],
                ),
              ),
            ),

            // 悬浮顶栏
            AnimatedOpacity(
              opacity: _chromeVisible ? 1 : 0.15,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              child: Container(
                padding: EdgeInsets.only(top: topInset, left: 6, right: 6),
                height: topInset + 48,
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () async {
                        // 返回前确保保存
                        if (_saveState == _SaveState.dirty) {
                          await _save(quiet: true);
                        }
                        if (context.mounted) {
                          Navigator.of(context).maybePop();
                        }
                      },
                      icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                      tooltip: context.tr(T('返回')),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: _showMetaSheet,
                      icon: const Icon(Icons.tune, size: 20),
                      tooltip: context.tr(T('文章信息（分类/标签/日期）')),
                    ),
                    // 更多操作：删除等低频但危险的操作收进来，避免误触
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_horiz, size: 20),
                      tooltip: context.tr(T('更多')),
                      onSelected: (v) {
                        if (v == 'delete') _deleteCurrentPost();
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'delete',
                          child: Text(context.tr(T('删除文章'))),
                        ),
                      ],
                    ),
                    IconButton(
                      onPressed: _toggleFind,
                      icon: Icon(
                        _findOpen ? Icons.search_off : Icons.search,
                        size: 20,
                      ),
                      tooltip: context.tr(T('查找替换')),
                    ),
                    IconButton(
                      onPressed: () => _save(),
                      icon: const Icon(Icons.save_outlined, size: 20),
                      tooltip: context.tr(T('保存')),
                    ),
                  ],
                ),
              ),
            ),

            // 底部：Markdown 工具栏 + 状态行
            // **整体不参与淡出** —— 设计文档只要求顶栏淡出，
            // 这里是操作入口，淡到 15% 等于让人找不到。
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  MarkdownToolbar(
                    controller: _bodyCtrl,
                    onChanged: () {
                      // 工具栏插入属于用户操作，要记历史、重置淡出、标记脏
                      _onBodyChanged();
                      _bodyFocus.requestFocus();
                    },
                    onUndo: _undo,
                    onRedo: _redo,
                    canUndo: _history.canUndo,
                    canRedo: _history.canRedo,
                    onDismissKeyboard: () => _bodyFocus.unfocus(),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 8, 16, 8),
                    color: c.background,
                    child: SafeArea(
                      top: false,
                      child: Row(
                        children: [
                          Text(
                            TP('{} 字', [_charCount]),
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.4,
                              color: c.textTertiary,
                            ),
                          ),
                          const SizedBox(width: AppSpace.xs),
                          _SaveIndicator(state: _saveState, error: _saveError),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: _togglePreview,
                            icon: Icon(
                              _previewMode
                                  ? Icons.edit_outlined
                                  : Icons.visibility_outlined,
                              size: 16,
                            ),
                            label: Text(
                              context.tr(
                                T(_previewMode ? '编辑' : '预览'),
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpace.xxs),
                          TextButton.icon(
                            onPressed: _toggleAi,
                            icon: Icon(
                              Icons.auto_awesome,
                              size: 16,
                              color: _aiOpen ? c.accent : null,
                            ),
                            label: const Text('AI'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 切换预览：正文区在「可编辑源码」与「富文本渲染」之间切换，
/// 就地替换，不弹面板、不遮挡。再点一次切回编辑。
  void _togglePreview() {
    setState(() {
      _previewMode = !_previewMode;
      // 进预览时收起键盘，避免输入法盖住渲染内容
      if (_previewMode) _bodyFocus.unfocus();
    });
  }

  /// 预览正文：用 [ChatMarkdown] 就地渲染当前 Markdown。
  ///
  /// 与编辑器正文用同一套 [ReadingPrefs]（字号/字体），所以在预览里看到的
  /// 字号就是读者看到的字号 —— 这就是「富文本式」预览的意义。
  Widget _buildPreviewBody(AppColors c) {
    final body = _bodyCtrl.text;
    if (body.trim().isEmpty) {
      return Center(
        child: Text(
          context.tr(T('正文还是空的')),
          style: TextStyle(color: c.textTertiary),
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      // 用读者字号渲染，预览所见即读者所见
      child: ChatMarkdown(body, baseFontSize: context.reading.fontSize),
    );
  }

  /// 切换内联写作 AI 面板：展开/收起，不用模态遮罩。
  void _toggleAi() {
    final ai = widget.aiController;
    if (ai == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr(T('写作 AI 未接入（缺少 AI 控制器）')))),
      );
      return;
    }
    setState(() {
      _aiOpen = !_aiOpen;
      if (_aiOpen) {
        // AI 面板要在编辑模式下用，先退出预览
        _previewMode = false;
        _bodyFocus.unfocus();
      }
    });
  }

  /// 把 AI 生成结果写回正文。
  ///
  /// [replaceAll] 为 true 时整篇替换；否则插入到当前光标处。
  /// 只是改文本，会自动触发自动保存 —— 不需要额外手动保存。
  void _applyAiResult(String text, {required bool replaceAll}) {
    if (replaceAll) {
      _bodyCtrl.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
      return;
    }
    final sel = _bodyCtrl.selection;
    final src = _bodyCtrl.text;
    final at = sel.isValid ? sel.start : src.length;
    final end = sel.isValid ? sel.end : src.length;
    final newText = src.replaceRange(at, end, text);
    _bodyCtrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: at + text.length),
    );
    _bodyFocus.requestFocus();
  }

  /// 文章信息面板
  ///
  /// 可改：草稿状态、日期、分类、标签、简介。
  /// 这些全部是 Front Matter 字段，改完立即写回文件。
  void _showMetaSheet() {
    final doc = _original;

    if (doc == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr(T('这篇文章还没有加载完成，稍后再试')))),
      );
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return _MetaSheet(
          doc: doc,
          allCategories: widget.controller?.allCategories ?? const [],
          allTags: widget.controller?.allTags ?? const [],
          onSave: (draft, date, categories, tags, description) async {
            final path = widget.relativePath;
            final ctrl = widget.controller;
            if (path == null || ctrl == null) return false;

            final result = await ctrl.savePost(
              relativePath: path,
              title: _titleCtrl.text,
              body: _bodyCtrl.text,
              original: _original,
              draft: draft,
              date: date,
              categories: categories,
              tags: tags,
              description: description,
            );
            if (!result.ok) {
              if (mounted) {
                setState(() {
                  _saveState = _SaveState.failed;
                  _saveError = result.message;
                });
              }
              return false;
            }
            final fresh = await ctrl.readPost(path);
            if (fresh != null && mounted) {
              setState(() {
                _original = fresh;
                _saveState = _SaveState.saved;
              });
            }
            return true;
          },
        );
      },
    );
  }

  /// 补录到列表页：删除当前文章
  Future<void> _deleteCurrentPost() async {
    final path = widget.relativePath;
    final ctrl = widget.controller;
    if (path == null || ctrl == null) return;
    final c = context.appColors;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr(T('删除这篇文章？'))),
        content: Text(
          TP('文件将被永久删除：\n{}\n\n这是本地文件删除，Git 仓库里的历史记录不受影响。', [path]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr(T('取消'))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: c.danger),
            child: Text(context.tr(T('删除'))),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    // 删除前把待保存的改动取消掉，否则 dispose 时会把文件又写回来
    _saveTimer?.cancel();
    _saveState = _SaveState.idle;

    final deleted = await ctrl.deletePost(path);
    if (!mounted) return;

    if (deleted) {
      _deleted = true;
      Navigator.of(context).maybePop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.tr(T('文章已删除')))));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(TP('删除失败：{}', [ctrl.error ?? "未知错误"]))),
      );
    }
  }
}
// ── 写作 AI 内联面板 ────────────────────────────────

/// 写作 AI 内联面板（嵌在编辑器正文下方，非模态、不遮正文）。
///
/// 交互：输入指令（如「帮我写一段开头」「把这段改得更简洁」）→ 点「生成」→
/// 流式显示结果 → 满意后点「插入到光标处」或「替换整篇」。
///
/// 为什么内联而不是弹层：用户要一边看正文一边和 AI 对话，
/// 模态遮罩会把正文整个盖住，等于蒙着眼睛改稿。
class _WriteAiPanelInline extends StatefulWidget {
  const _WriteAiPanelInline({
    required this.ai,
    required this.currentBody,
    required this.onInsert,
    required this.onReplaceAll,
    required this.onClose,
  });

  final AiController? ai;
  final String currentBody;
  final void Function(String) onInsert;
  final void Function(String) onReplaceAll;
  final VoidCallback onClose;

  @override
  State<_WriteAiPanelInline> createState() => _WriteAiPanelInlineState();
}

class _WriteAiPanelInlineState extends State<_WriteAiPanelInline> {
  final _inputCtrl = TextEditingController();
  final _result = StringBuffer();
  bool _running = false;
  String? _error;
  String _live = '';


  @override
  void dispose() {
    _inputCtrl.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final instruction = _inputCtrl.text.trim();
    if (instruction.isEmpty) return;
    final ai = widget.ai;
    if (ai == null) return;
    setState(() {
      _running = true;
      _error = null;
      _result.clear();
      _live = '';
    });
    try {
      final full = await ai.composeWriting(
        instruction: instruction,
        currentBody: widget.currentBody,
        onDelta: (text) {
          if (!mounted) return;
          setState(() => _live = text);
        },
      );
      if (!mounted) return;
      setState(() {
        _result.write(full);
        _running = false;
      });
    } on AiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _running = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _running = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final output = _result.isNotEmpty ? _result.toString() : _live;
    return Container(
      margin: const EdgeInsets.only(top: AppSpace.xs),
      padding: const EdgeInsets.fromLTRB(
        AppSpace.sm,
        AppSpace.xxs,
        AppSpace.xs,
        0,
      ),
      decoration: BoxDecoration(
        color: c.surfaceHigh,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: c.divider),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 16, color: c.accent),
              const SizedBox(width: AppSpace.xs),
              Text(
                context.tr(T('写作 AI')),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: c.textPrimary,
                ),
              ),
              const Spacer(),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.close, size: 18, color: c.textSecondary),
                onPressed: _running ? null : widget.onClose,
              ),
            ],
          ),
          // 输出区（流式）
            if (_running || output.isNotEmpty)
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                width: double.infinity,
                margin: const EdgeInsets.symmetric(vertical: AppSpace.xs),
                padding: const EdgeInsets.all(AppSpace.sm),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: SingleChildScrollView(
                  child: _running && output.isEmpty
                      ? Row(
                          children: [
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: c.accent,
                              ),
                            ),
                            const SizedBox(width: AppSpace.xs),
                            Text(
                              context.tr(T('生成中…')),
                              style: TextStyle(color: c.textTertiary),
                            ),
                          ],
                        )
                      : ChatMarkdown(output),
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.xs),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _error!,
                    style: TextStyle(fontSize: 12, color: c.danger),
                  ),
                ),
              ),
            // 输入框
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.xs, right: AppSpace.xxs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputCtrl,
                      enabled: !_running,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.newline,
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: context.tr(
                          T('告诉 AI 你想怎么写，如「帮我写一段开头」'),
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpace.sm,
                          vertical: AppSpace.sm,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpace.xs),
                  FilledButton(
                    onPressed: _running ? null : _generate,
                    child: _running
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(context.tr(T('生成'))),
                  ),
                ],
              ),
            ),
            // 结果操作
            if (output.isNotEmpty && !_running)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.xs, right: AppSpace.xxs),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => widget.onInsert(output),
                        child: Text(context.tr(T('插入到光标处'))),
                      ),
                    ),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => widget.onReplaceAll(output),
                        child: Text(context.tr(T('替换整篇'))),
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

// ── 保存状态指示 ────────────────────────────────────

class _SaveIndicator extends StatelessWidget {
  const _SaveIndicator({required this.state, this.error});

  final _SaveState state;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;

    final (icon, text, color) = switch (state) {
      _SaveState.idle => (Icons.cloud_done_outlined, T('已同步'), c.textTertiary),
      _SaveState.dirty => (Icons.edit_outlined, T('未保存'), c.textTertiary),
      _SaveState.saving => (Icons.sync, T('保存中…'), c.textTertiary),
      _SaveState.saved => (
        Icons.check_circle_outline,
        T('已保存'),
        c.textTertiary,
      ),
      _SaveState.failed => (Icons.error_outline, T('保存失败'), c.danger),
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 3),
        Text(text, style: TextStyle(fontSize: 12, height: 1.4, color: color)),
        if (error != null) ...[
          const SizedBox(width: AppSpace.xxs),
          Tooltip(
            message: error!,
            child: Icon(Icons.info_outline, size: 13, color: c.danger),
          ),
        ],
      ],
    );
  }
}

// ── 查找替换条 ──────────────────────────────────────

class _FindBar extends StatelessWidget {
  const _FindBar({
    required this.findCtrl,
    required this.replaceCtrl,
    required this.matchCount,
    required this.current,
    required this.onChanged,
    required this.onPrev,
    required this.onNext,
    required this.onReplace,
    required this.onReplaceAll,
    required this.onClose,
  });

  final TextEditingController findCtrl;
  final TextEditingController replaceCtrl;
  final int matchCount;
  final int current;
  final VoidCallback onChanged;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onReplace;
  final VoidCallback onReplaceAll;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;

    return Container(
      margin: const EdgeInsets.only(top: AppSpace.xs),
      padding: const EdgeInsets.all(AppSpace.xs),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: findCtrl,
                  onChanged: (_) => onChanged(),
                  autofocus: true,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: context.tr(T('查找')),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                matchCount == 0 ? T('无') : '$current/$matchCount',
                style: TextStyle(fontSize: 11, color: c.textTertiary),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: matchCount == 0 ? null : onPrev,
                icon: const Icon(Icons.keyboard_arrow_up, size: 18),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: matchCount == 0 ? null : onNext,
                icon: const Icon(Icons.keyboard_arrow_down, size: 18),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: onClose,
                icon: const Icon(Icons.close, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: replaceCtrl,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: context.tr(T('替换为')),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              TextButton(
                onPressed: matchCount == 0 ? null : onReplace,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                ),
                child: Text(
                  context.tr(T('替换')),
                  style: TextStyle(fontSize: 12),
                ),
              ),
              TextButton(
                onPressed: matchCount == 0 ? null : onReplaceAll,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                ),
                child: Text(
                  context.tr(T('全部')),
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── 文章信息编辑面板 ──────────────────────────────────

/// 编辑 Front Matter 里的元信息。
///
/// 为什么做成一整张表单而不是「点一项改一项」：
/// 元信息通常是一起调的（改日期顺便改草稿状态），分开点会关掉又打开好几次。
class _MetaSheet extends StatefulWidget {
  const _MetaSheet({
    required this.doc,
    required this.allCategories,
    required this.allTags,
    required this.onSave,
  });

  final PostDocument doc;
  final List<String> allCategories;
  final List<String> allTags;

  /// 返回 true 表示写入成功
  final Future<bool> Function(
    bool draft,
    DateTime? date,
    List<String> categories,
    List<String> tags,
    String description,
  )
  onSave;

  @override
  State<_MetaSheet> createState() => _MetaSheetState();
}

class _MetaSheetState extends State<_MetaSheet> {
  late bool _draft = widget.doc.draft;
  late DateTime? _date = widget.doc.date;
  late List<String> _categories = [...widget.doc.categories];
  late List<String> _tags = [...widget.doc.tags];
  late final TextEditingController _descCtrl = TextEditingController(
    text: widget.doc.description,
  );

  final _catCtrl = TextEditingController();
  final _tagCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _descCtrl.dispose();
    _catCtrl.dispose();
    _tagCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.md,
            AppSpace.sm,
            AppSpace.md,
            AppSpace.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    context.tr(T('文章信息')),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: c.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _saving ? null : _submit,
                    child: Text(_saving ? T('保存中…') : T('保存')),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.xs),

              // 草稿
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _draft,
                title: Text(context.tr(T('草稿'))),
                subtitle: Text(
                  _draft ? T('Hugo 构建时不会输出这篇') : T('已发布，构建时会输出'),
                  style: TextStyle(fontSize: 12, color: c.textTertiary),
                ),
                onChanged: (v) => setState(() => _draft = v),
              ),

              const SizedBox(height: AppSpace.xs),
              _label(T('发布日期'), c),
              const SizedBox(height: 4),
              InkWell(
                onTap: _pickDate,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.event_outlined,
                        size: 16,
                        color: c.textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _date == null ? T('未设置（保存时自动填今天）') : _fmt(_date!),
                        style: TextStyle(
                          fontSize: 13,
                          color: _date == null ? c.textTertiary : c.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      if (_date != null)
                        GestureDetector(
                          onTap: () => setState(() => _date = null),
                          child: Icon(
                            Icons.close,
                            size: 16,
                            color: c.textTertiary,
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: AppSpace.md),
              _label(T('分类'), c),
              const SizedBox(height: 6),
              ChipEditor(
                values: _categories,
                allValues: widget.allCategories,
                hint: T('添加分类，回车确认'),
                controller: _catCtrl,
                onChanged: (v) => setState(() => _categories = v),
              ),

              const SizedBox(height: AppSpace.md),
              _label(T('标签'), c),
              const SizedBox(height: 6),
              ChipEditor(
                values: _tags,
                allValues: widget.allTags,
                hint: T('添加标签，回车确认'),
                controller: _tagCtrl,
                onChanged: (v) => setState(() => _tags = v),
              ),

              const SizedBox(height: AppSpace.md),
              _label(T('简介（description）'), c),
              const SizedBox(height: 6),
              TextField(
                controller: _descCtrl,
                maxLines: 3,
                minLines: 2,
                style: const TextStyle(fontSize: 13, height: 1.5),
                decoration: InputDecoration(
                  hintText: context.tr(T('留空则用正文开头做摘要')),
                  hintStyle: TextStyle(fontSize: 13, color: c.textTertiary),
                  filled: true,
                  fillColor: c.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),

              const SizedBox(height: AppSpace.md),
              Text(
                TP('文件：{}', [widget.doc.relativePath]),
                style: TextStyle(
                  fontSize: 11,
                  height: 1.6,
                  color: c.textTertiary,
                ),
              ),
              Text(
                TP('格式：{}', [widget.doc.format.toUpperCase()]),
                style: TextStyle(
                  fontSize: 11,
                  height: 1.6,
                  color: c.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String s, AppColors c) => Text(
    s,
    style: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: c.textSecondary,
    ),
  );

  String _fmt(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} '
        '${two(d.hour)}:${two(d.minute)}';
  }

  Future<void> _pickDate() async {
    final base = _date ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: T('选择发布日期'),
    );
    if (picked == null || !mounted) return;

    // 日期选择器不回时间，这里补问一次？不 —— 保留原时分，
    // 新日期则用当前时分，避免每次改日期都变成 00:00。
    final now = DateTime.now();
    setState(() {
      _date = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _date?.hour ?? now.hour,
        _date?.minute ?? now.minute,
      );
    });
  }

  Future<void> _submit() async {
    // 把输入框里还没回车的分类标签也带上，否则用户敲完直接点保存会丢
    _commitPending(_catCtrl, _categories, (v) => _categories = v);
    _commitPending(_tagCtrl, _tags, (v) => _tags = v);

    setState(() => _saving = true);
    final ok = await widget.onSave(
      _draft,
      _date,
      _categories,
      _tags,
      _descCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _saving = false);

    if (ok) {
      Navigator.of(context).maybePop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.tr(T('文章信息已保存')))));
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.tr(T('保存失败，请查看底部状态')))));
    }
  }

  void _commitPending(
    TextEditingController ctrl,
    List<String> target,
    void Function(List<String>) assign,
  ) {
    final v = ctrl.text.trim();
    if (v.isEmpty) return;
    if (!target.contains(v)) assign([...target, v]);
    ctrl.clear();
  }
}
