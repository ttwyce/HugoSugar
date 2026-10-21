import 'package:flutter/material.dart';
import 'package:hugosugar/app/i18n/l10n_scope.dart';

import '../../app/theme/app_colors.dart';

import 'markdown_insert.dart';

/// 编辑器底部 Markdown 工具栏。
///
/// 设计约束：
/// - 横向可滚，不占多行高度（手机上竖着排会吃掉半屏正文）
/// - 按钮只做「插入 / 包裹」，不显示当前是否生效 —— 光标状态变化太频繁，
///   高亮会闪，不如统一中性色
/// - 字体图标用等宽字形代替，避免引入额外 icon 字体依赖
class MarkdownToolbar extends StatelessWidget {
  const MarkdownToolbar({
    super.key,
    required this.controller,
    required this.onChanged,
    this.onUndo,
    this.onRedo,
    this.canUndo = false,
    this.canRedo = false,
    this.onDismissKeyboard,
  });

  final TextEditingController controller;

  /// 插入后通知外层（重置淡出计时器、标记脏、记撤销）
  final VoidCallback onChanged;

  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final bool canUndo;
  final bool canRedo;
  final VoidCallback? onDismissKeyboard;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;

    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.divider, width: 0.5)),
      ),
      child: Row(
        children: [
          // 撤销 / 重做固定在左侧，不参与横向滚动 —— 这两个用得最频繁
          _ActionBtn(
            label: '↶',
            tooltip: context.tr(T('撤销')),
            enabled: canUndo,
            onTap: onUndo,
          ),
          _ActionBtn(
            label: '↷',
            tooltip: context.tr(T('重做')),
            enabled: canRedo,
            onTap: onRedo,
          ),
          Container(width: 0.5, height: 22, color: c.divider),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  _MarkBtn('H1', () => _prefix('# ')),
                  _MarkBtn('H2', () => _prefix('## ')),
                  _MarkBtn('H3', () => _prefix('### ')),
                  _sep(c),
                  _MarkBtn(
                    'B',
                    () => _wrap('**', placeholder: T('粗体')),
                    bold: true,
                    tooltip: context.tr(T('粗体')),
                  ),
                  _MarkBtn(
                    'I',
                    () => _wrap('_', placeholder: T('斜体')),
                    italic: true,
                    tooltip: context.tr(T('斜体')),
                  ),
                  _MarkBtn(
                    'S',
                    () => _wrap('~~', placeholder: T('删除线')),
                    strike: true,
                    tooltip: context.tr(T('删除线')),
                  ),
                  _MarkBtn(
                    '</>',
                    () => _wrap('`', placeholder: 'code'),
                    mono: true,
                    tooltip: context.tr(T('行内代码')),
                  ),
                  _sep(c),
                  _MarkBtn(
                    '“”',
                    () => _prefix('> '),
                    tooltip: context.tr(T('引用')),
                  ),
                  _MarkBtn(
                    '•',
                    () => _prefix('- '),
                    tooltip: context.tr(T('无序列表')),
                  ),
                  _MarkBtn(
                    '1.',
                    () => _prefix('1. '),
                    tooltip: context.tr(T('有序列表')),
                  ),
                  _sep(c),
                  _MarkBtn(
                    '🔗',
                    () => _apply(MarkdownInsert.link),
                    tooltip: context.tr(T('链接')),
                  ),
                  _MarkBtn(
                    '▦',
                    () => _apply(MarkdownInsert.table),
                    tooltip: context.tr(T('表格')),
                  ),
                  _MarkBtn(
                    '—',
                    () => _insertAtCursor('\n---\n'),
                    tooltip: context.tr(T('分隔线')),
                  ),
                  _MarkBtn(
                    '💡',
                    () => _prefix('> [!note] '),
                    tooltip: context.tr(T('提示块')),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ),
          if (onDismissKeyboard != null)
            _ActionBtn(
              label: '⌄',
              tooltip: context.tr(T('收起键盘')),
              enabled: true,
              onTap: onDismissKeyboard,
            ),
        ],
      ),
    );
  }

  Widget _sep(AppColors c) => Container(
    width: 0.5,
    height: 18,
    margin: const EdgeInsets.symmetric(horizontal: 6),
    color: c.divider,
  );

  void _apply(TextEditingValue Function(TextEditingValue) fn) {
    final v = fn(controller.value);
    controller.value = v;
    onChanged();
  }

  void _wrap(String marker, {String? placeholder}) {
    _apply(
      (v) => MarkdownInsert.wrap(v, marker: marker, placeholder: placeholder),
    );
  }

  void _prefix(String prefix) {
    _apply((v) => MarkdownInsert.prefixLine(v, prefix: prefix));
  }

  void _insertAtCursor(String s) {
    _apply((v) => MarkdownInsert.insert(v, s));
  }
}

class _MarkBtn extends StatelessWidget {
  const _MarkBtn(
    this.label,
    this.onTap, {
    this.bold = false,
    this.italic = false,
    this.strike = false,
    this.mono = false,
    this.tooltip,
  });

  final String label;
  final VoidCallback onTap;
  final bool bold;
  final bool italic;
  final bool strike;
  final bool mono;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    Widget child = Text(
      label,
      style: TextStyle(
        fontSize: mono ? 11 : 14,
        height: 1.2,
        color: c.textPrimary,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
        fontStyle: italic ? FontStyle.italic : FontStyle.normal,
        decoration: strike ? TextDecoration.lineThrough : null,
        fontFamily: mono ? 'monospace' : null,
      ),
    );

    final btn = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        constraints: const BoxConstraints(minWidth: 36),
        height: 44,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: child,
      ),
    );

    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({
    required this.label,
    required this.tooltip,
    required this.enabled,
    this.onTap,
  });

  final String label;
  final String tooltip;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Container(
          width: 40,
          height: 44,
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 17,
              height: 1.2,
              color: enabled
                  ? c.textPrimary
                  : c.textTertiary.withValues(alpha: 0.4),
            ),
          ),
        ),
      ),
    );
  }
}
