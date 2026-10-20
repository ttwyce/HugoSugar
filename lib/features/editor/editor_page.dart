import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../core/post/front_matter.dart';
import '../../core/site/site_controller.dart';
import 'markdown_highlighter.dart';

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
  });

  final String title;

  /// 相对站点根的文件路径，如 content/posts/hello.md
  final String? relativePath;

  /// 用来读写文件；为空时编辑器不落盘
  final SiteController? controller;

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
      return;
    }

    setState(() => _loading = true);
    final doc = await ctrl.readPost(path);
    if (!mounted) return;

    if (doc == null) {
      setState(() {
        _loading = false;
        _loadError = '无法读取文件：$path';
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
  }

  @override
  void dispose() {
    _chromeTimer?.cancel();
    _saveTimer?.cancel();
    // 离开时若还有未保存内容，尽力保存一次（不阻塞 UI）
    _flushOnExit();
    _bodyCtrl.removeListener(_onBodyChanged);
    _titleCtrl.removeListener(_onTitleChanged);
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    _bodyFocus.dispose();
    _findCtrl.dispose();
    _replaceCtrl.dispose();
    _scrollCtrl.dispose();
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
    if (_findOpen) _recomputeMatches();
  }

  void _onTitleChanged() {
    if (!_ready) return;
    _markDirty();
    // 改标题也算「正在写」，应该和改正文一样重置淡出计时器。
    // 之前漏了这一行，导致在标题里打字时顶栏可能就在你眼前暗下去。
    _onTyping();
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
          _saveError = '这篇稿件还没有文件路径，无法保存';
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
    final replaced = '${text.substring(0, start)}${_replaceCtrl.text}'
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

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已替换 $count 处')),
    );
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
                        hintText: '标题',
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
                          _original?.statusLabel ?? '草稿',
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
                          _loading ? '读取中…' : '$_charCount 字',
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
                    if (_findOpen) _FindBar(
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
                    // 正文
                    Expanded(
                      child: TextField(
                        controller: _bodyCtrl,
                        focusNode: _bodyFocus,
                        scrollController: _scrollCtrl,
                        maxLines: null,
                        expands: true,
                        textAlignVertical: TextAlignVertical.top,
                        keyboardType: TextInputType.multiline,
                        style: AppTypography.editorBody.copyWith(
                          color: c.textPrimary,
                        ),
                        decoration: InputDecoration(
                          filled: false,
                          contentPadding: EdgeInsets.zero,
                          hintText: '正文…',
                          hintStyle: AppTypography.editorBody.copyWith(
                            color: c.textTertiary,
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                        ),
                      ),
                    ),
                    // 给固定显示的底部状态栏留出高度，避免最后一行文字被盖住
                    SizedBox(height: 44 + MediaQuery.of(context).padding.bottom),
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
                      tooltip: '返回',
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => _showMetaSheet(),
                      icon: const Icon(Icons.tune, size: 20),
                      tooltip: '文章信息',
                    ),
                    IconButton(
                      onPressed: _toggleFind,
                      icon: Icon(
                        _findOpen ? Icons.search_off : Icons.search,
                        size: 20,
                      ),
                      tooltip: '查找替换',
                    ),
                    IconButton(
                      onPressed: () => _save(),
                      icon: const Icon(Icons.save_outlined, size: 20),
                      tooltip: '保存',
                    ),
                  ],
                ),
              ),
            ),

            // 底部状态：**不参与淡出**。
            // 设计文档只要求顶栏淡出，这里的字数 / 保存状态 / 预览 / AI 是操作入口，
            // 淡到 15% 等于让人找不到，所以固定常驻。
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 8, 16, 8),
                color: c.background,
                child: SafeArea(
                  top: false,
                    child: Row(
                      children: [
                        Text(
                          '$_charCount 字',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            color: c.textTertiary,
                          ),
                        ),
                        const SizedBox(width: AppSpace.xs),
                        _SaveIndicator(
                          state: _saveState,
                          error: _saveError,
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () {},
                          icon: const Icon(Icons.visibility_outlined, size: 16),
                          label: const Text('预览'),
                        ),
                        const SizedBox(width: AppSpace.xxs),
                        TextButton.icon(
                          onPressed: () {},
                          icon: const Icon(Icons.auto_awesome, size: 16),
                          label: const Text('AI'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 文章信息面板：草稿开关
  void _showMetaSheet() {
    final c = context.appColors;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        var draft = _original?.draft ?? true;
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.md,
                  AppSpace.xs,
                  AppSpace.md,
                  AppSpace.md,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '文章信息',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppSpace.md),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: draft,
                      title: const Text('草稿'),
                      subtitle: Text(
                        draft ? 'Hugo 构建时不会输出这篇' : '已发布，构建时会输出',
                        style: TextStyle(
                          fontSize: 12,
                          color: c.textTertiary,
                        ),
                      ),
                      onChanged: (v) {
                        setSheet(() => draft = v);
                        _applyDraft(v);
                      },
                    ),
                    const SizedBox(height: AppSpace.xs),
                    if (_original != null) ...[
                      Text(
                        '文件：${_original!.relativePath}',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.6,
                          color: c.textTertiary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '格式：${_original!.format.toUpperCase()}'
                        '${_original!.dateLabel.isEmpty ? "" : " · ${_original!.dateLabel}"}',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.6,
                          color: c.textTertiary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _applyDraft(bool draft) {
    final doc = _original;
    if (doc == null) return;
    setState(() {
      _original = PostDocument(
        relativePath: doc.relativePath,
        fileName: doc.fileName,
        title: doc.title,
        frontMatter: doc.frontMatter,
        body: doc.body,
        rawFrontMatter: doc.rawFrontMatter,
        format: doc.format,
        date: doc.date,
        draft: draft,
        categories: doc.categories,
        tags: doc.tags,
        description: doc.description,
        slug: doc.slug,
        weight: doc.weight,
      );
      _saveState = _SaveState.dirty;
    });
    _save();
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
      _SaveState.idle => (Icons.cloud_done_outlined, '已同步', c.textTertiary),
      _SaveState.dirty => (Icons.edit_outlined, '未保存', c.textTertiary),
      _SaveState.saving => (Icons.sync, '保存中…', c.textTertiary),
      _SaveState.saved => (Icons.check_circle_outline, '已保存', c.textTertiary),
      _SaveState.failed => (Icons.error_outline, '保存失败', c.danger),
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 3),
        Text(
          text,
          style: TextStyle(fontSize: 12, height: 1.4, color: color),
        ),
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
                  decoration: const InputDecoration(
                    hintText: '查找',
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                matchCount == 0 ? '无' : '$current/$matchCount',
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
                  decoration: const InputDecoration(
                    hintText: '替换为',
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
                child: const Text('替换', style: TextStyle(fontSize: 12)),
              ),
              TextButton(
                onPressed: matchCount == 0 ? null : onReplaceAll,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                ),
                child: const Text('全部', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}