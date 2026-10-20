import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../core/note/note.dart';
import '../../core/note/note_controller.dart';
import '../editor/markdown_highlighter.dart';
import '../editor/editor_page.dart';

/// 笔记编辑器。
///
/// 与文章编辑器的区别（这是刻意的，不是没做完）：
/// - 笔记**没有** Front Matter，就是一整块 Markdown 文本
/// - 停笔 1.5 秒自动保存（比文章更频繁，因为笔记是随手记）
/// - 顶部有一个「转为文章」入口，这是笔记存在的意义
class NoteEditorPage extends StatefulWidget {
  const NoteEditorPage({
    super.key,
    required this.controller,
    required this.noteId,
    this.isNew = false,
  });

  final NoteController controller;
  final String noteId;
  final bool isNew;

  @override
  State<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends State<NoteEditorPage> {
  final _titleCtrl = TextEditingController();
  late final MarkdownEditingController _bodyCtrl =
      MarkdownEditingController();
  final _bodyFocus = FocusNode();

  Timer? _saveTimer;
  Note? _note;
  bool _dirty = false;
  bool _saving = false;
  String? _savedAtLabel;

  NoteController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    _note = c.store.byId(widget.noteId);
    if (_note != null) {
      _titleCtrl.text = _note!.title;
      _bodyCtrl.text = _note!.content;
    }
    _titleCtrl.addListener(_onChanged);
    _bodyCtrl.addListener(_onChanged);
    if (widget.isNew) {
      // 新建时直接聚焦正文，省一次点击
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _bodyFocus.requestFocus();
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final colours = context.appColors;
    _bodyCtrl.applyTheme(
      accent: colours.accent,
      dim: colours.textTertiary,
      codeBg: colours.surface,
    );
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _flush();
    _titleCtrl.removeListener(_onChanged);
    _bodyCtrl.removeListener(_onChanged);
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    _bodyFocus.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (_note == null) return;
    if (!_dirty) setState(() => _dirty = true);
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 1500), _flush);
  }

  /// 立即保存。不 await 也能调用（离开页面时用）。
  Future<void> _flush() async {
    final base = _note;
    if (base == null || !_dirty || _saving) return;

    setState(() => _saving = true);
    final updated = base.copyWith(
      title: _titleCtrl.text.trim(),
      content: _bodyCtrl.text,
    );
    final saved = await c.saveNote(updated);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _dirty = false;
      if (saved != null) {
        _note = saved;
        _savedAtLabel = '已保存';
      }
    });
  }

  int get _charCount => _bodyCtrl.text.replaceAll(RegExp(r'\s'), '').length;

  @override
  Widget build(BuildContext context) {
    final colours = context.appColors;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _flush();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 18),
            onPressed: () async {
              await _flush();
              // await 之后必须检查 context 本身是否还在树上，
              // 只检查 State.mounted 不覆盖 Navigator 所在的 context
              if (context.mounted) Navigator.of(context).pop(true);
            },
          ),
          title: const SizedBox.shrink(),
          actions: [
            IconButton(
              onPressed: _note == null ? null : () => c.togglePin(_note!.id).then(
                    (_) => setState(() {
                      _note = c.store.byId(widget.noteId);
                    }),
                  ),
              icon: Icon(
                (_note?.pinned ?? false)
                    ? Icons.push_pin
                    : Icons.push_pin_outlined,
                size: 20,
                color: (_note?.pinned ?? false) ? colours.accent : null,
              ),
              tooltip: (_note?.pinned ?? false) ? '取消置顶' : '置顶',
            ),
            IconButton(
              onPressed: _note == null ? null : _convert,
              icon: const Icon(Icons.article_outlined, size: 20),
              tooltip: '转为文章',
            ),
            const SizedBox(width: AppSpace.xs),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _titleCtrl,
                  style: AppTypography.editorTitle.copyWith(
                    color: colours.textPrimary,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: false,
                    contentPadding: EdgeInsets.zero,
                    hintText: '笔记标题',
                    hintStyle: AppTypography.editorTitle.copyWith(
                      color: colours.textTertiary,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                  maxLines: null,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: AppSpace.xxs),
                Row(
                  children: [
                    Text(
                      _saving
                          ? '保存中…'
                          : _dirty
                              ? '未保存'
                              : (_savedAtLabel ?? '已保存'),
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: colours.textTertiary,
                      ),
                    ),
                    const SizedBox(width: AppSpace.xs),
                    Text('·', style: TextStyle(color: colours.textTertiary)),
                    const SizedBox(width: AppSpace.xs),
                    Text(
                      '$_charCount 字',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: colours.textTertiary,
                      ),
                    ),
                    if (_note?.isConverted ?? false) ...[
                      const SizedBox(width: AppSpace.xs),
                      Icon(
                        Icons.article_outlined,
                        size: 12,
                        color: colours.accent,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '已转文章',
                        style: TextStyle(
                          fontSize: 12,
                          color: colours.accent,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: AppSpace.sm),
                Expanded(
                  child: TextField(
                    controller: _bodyCtrl,
                    focusNode: _bodyFocus,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    keyboardType: TextInputType.multiline,
                    style: AppTypography.editorBody.copyWith(
                      color: colours.textPrimary,
                    ),
                    decoration: InputDecoration(
                      filled: false,
                      contentPadding: EdgeInsets.zero,
                      hintText: '随手写点什么…',
                      hintStyle: AppTypography.editorBody.copyWith(
                        color: colours.textTertiary,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── 转文章 ─────────────────────────────────────────

  Future<void> _convert() async {
    final note = _note;
    if (note == null) return;

    await _flush();
    if (!mounted) return;

    final result = await showModalBottomSheet<_ConvertForm>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ConvertSheet(
        initialTitle: note.title.trim().isEmpty ? '无标题' : note.title.trim(),
        siteCategories: c.site?.allCategories ?? const [],
        siteTags: c.site?.allTags ?? const [],
      ),
    );
    if (result == null || !mounted) return;

    if (c.site == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先接入站点，再转换为文章')),
      );
      return;
    }

    final convert = await c.convertToPost(
      note,
      title: result.title,
      categories: result.categories,
      tags: result.tags,
      description: result.description,
      draft: result.draft,
    );

    if (!mounted) return;

    if (!convert.ok) {
      // 已转换过：提示并给出跳转入口
      if (convert.postPath != null && convert.message != null) {
        final choice = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('已经转换过'),
            content: Text('${convert.message}\n\n要打开那篇文章，还是再生成一篇？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'force'),
                child: const Text('再生成一篇'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'open'),
                child: const Text('打开'),
              ),
            ],
          ),
        );

        if (!mounted) return;

        if (choice == 'force') {
          final retry = await c.convertToPost(
            note,
            title: result.title,
            categories: result.categories,
            tags: result.tags,
            description: result.description,
            draft: result.draft,
            force: true,
          );
          if (!mounted) return;
          if (!retry.ok) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(retry.message ?? '转换失败')),
            );
            return;
          }
          setState(() => _note = c.store.byId(widget.noteId));
          if (!mounted) return;
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => EditorPage(
                title: result.title,
                relativePath: retry.postPath,
                controller: c.site,
              ),
            ),
          );
          if (mounted) setState(() => _note = c.store.byId(widget.noteId));
          return;
        }

        if (choice == 'open') {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => EditorPage(
                title: result.title,
                relativePath: convert.postPath,
                controller: c.site,
              ),
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(convert.message ?? '转换失败')),
        );
      }
      return;
    }

    setState(() => _note = c.store.byId(widget.noteId));

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EditorPage(
          title: result.title,
          relativePath: convert.postPath,
          controller: c.site,
        ),
      ),
    );
    if (mounted) setState(() => _note = c.store.byId(widget.noteId));
  }
}

// ── 转换表单 ─────────────────────────────────────────

class _ConvertForm {
  const _ConvertForm({
    required this.title,
    required this.categories,
    required this.tags,
    required this.description,
    required this.draft,
  });

  final String title;
  final List<String> categories;
  final List<String> tags;
  final String description;
  final bool draft;
}

class _ConvertSheet extends StatefulWidget {
  const _ConvertSheet({
    required this.initialTitle,
    required this.siteCategories,
    required this.siteTags,
  });

  final String initialTitle;
  final List<String> siteCategories;
  final List<String> siteTags;

  @override
  State<_ConvertSheet> createState() => _ConvertSheetState();
}

class _ConvertSheetState extends State<_ConvertSheet> {
  late final TextEditingController _titleCtrl =
      TextEditingController(text: widget.initialTitle);
  final _descCtrl = TextEditingController();
  final _catCtrl = TextEditingController();
  final _tagCtrl = TextEditingController();

  final _categories = <String>[];
  final _tags = <String>[];
  bool _draft = true;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _catCtrl.dispose();
    _tagCtrl.dispose();
    super.dispose();
  }

  void _add(bool isCat) {
    final ctrl = isCat ? _catCtrl : _tagCtrl;
    final raw = ctrl.text.trim();
    if (raw.isEmpty) return;
    final parts = raw
        .split(RegExp(r'[,，\s]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty);
    setState(() {
      for (final v in parts) {
        final list = isCat ? _categories : _tags;
        if (!list.contains(v)) list.add(v);
      }
    });
    ctrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final colours = context.appColors;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        child: SingleChildScrollView(
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
                '转为文章',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: colours.textPrimary,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '笔记正文会成为文章正文。分类和标签与笔记分类无关。',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: colours.textTertiary,
                  ),
                ),
              ),
              const SizedBox(height: AppSpace.md),
              TextField(
                controller: _titleCtrl,
                style: const TextStyle(fontSize: 15),
                decoration: const InputDecoration(
                  hintText: '文章标题',
                  isDense: true,
                ),
              ),
              const SizedBox(height: AppSpace.sm),
              TextField(
                controller: _descCtrl,
                style: const TextStyle(fontSize: 14),
                maxLines: 2,
                decoration: const InputDecoration(
                  hintText: '简介（可选）',
                  isDense: true,
                ),
              ),
              const SizedBox(height: AppSpace.sm),
              _ChipField(
                label: '分类',
                selected: _categories,
                controller: _catCtrl,
                suggestions: widget.siteCategories,
                onAdd: () => _add(true),
                onRemove: (v) => setState(() => _categories.remove(v)),
                onPick: (v) => setState(() {
                  if (!_categories.contains(v)) _categories.add(v);
                }),
              ),
              const SizedBox(height: AppSpace.sm),
              _ChipField(
                label: '标签',
                selected: _tags,
                controller: _tagCtrl,
                suggestions: widget.siteTags,
                onAdd: () => _add(false),
                onRemove: (v) => setState(() => _tags.remove(v)),
                onPick: (v) => setState(() {
                  if (!_tags.contains(v)) _tags.add(v);
                }),
              ),
              const SizedBox(height: AppSpace.sm),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '保存为草稿',
                      style: TextStyle(fontSize: 14, color: colours.textPrimary),
                    ),
                  ),
                  Switch(
                    value: _draft,
                    onChanged: (v) => setState(() => _draft = v),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.sm),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    final title = _titleCtrl.text.trim();
                    if (title.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('请填写标题')),
                      );
                      return;
                    }
                    Navigator.of(context).pop(
                      _ConvertForm(
                        title: title,
                        categories: List.of(_categories),
                        tags: List.of(_tags),
                        description: _descCtrl.text.trim(),
                        draft: _draft,
                      ),
                    );
                  },
                  child: const Text('生成文章'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 简单的 chip 输入（笔记页与转文章表单共用风格）
class _ChipField extends StatelessWidget {
  const _ChipField({
    required this.label,
    required this.selected,
    required this.controller,
    required this.suggestions,
    required this.onAdd,
    required this.onRemove,
    required this.onPick,
  });

  final String label;
  final List<String> selected;
  final TextEditingController controller;
  final List<String> suggestions;
  final VoidCallback onAdd;
  final void Function(String) onRemove;
  final void Function(String) onPick;

  @override
  Widget build(BuildContext context) {
    final colours = context.appColors;
    final available =
        suggestions.where((s) => !selected.contains(s)).take(8).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            height: 1.4,
            color: colours.textTertiary,
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          style: const TextStyle(fontSize: 14),
          onSubmitted: (_) => onAdd(),
          decoration: InputDecoration(
            hintText: '回车添加，可用逗号分隔',
            isDense: true,
            suffixIcon: IconButton(
              icon: const Icon(Icons.add, size: 18),
              onPressed: onAdd,
            ),
          ),
        ),
        if (selected.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final v in selected)
                InputChip(
                  label: Text(v, style: const TextStyle(fontSize: 12)),
                  onDeleted: () => onRemove(v),
                  deleteIcon: const Icon(Icons.close, size: 14),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
        if (available.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final v in available)
                ActionChip(
                  label: Text(v, style: const TextStyle(fontSize: 12)),
                  onPressed: () => onPick(v),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
      ],
    );
  }
}