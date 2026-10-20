import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/ai/agent_runner.dart';

/// 写入审批面板：展示 Diff，让用户决定是否落盘。
///
/// 这是 AI 唯一的写权限入口。设计上刻意做成「必须看到差别才能同意」：
/// - 新增文件：显示将创建的完整内容
/// - 覆盖文件：逐行 Diff，改动的行高亮
class WriteApprovalSheet extends StatefulWidget {
  const WriteApprovalSheet({super.key, required this.request});

  final ApprovalRequest request;

  @override
  State<WriteApprovalSheet> createState() => _WriteApprovalSheetState();
}

class _WriteApprovalSheetState extends State<WriteApprovalSheet> {
  bool _showFullNew = false;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final req = widget.request;
    final diff = computeDiff(req.oldContent ?? '', req.newContent);

    return SafeArea(
      child: Padding(
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
                Icon(Icons.edit_note, size: 18, color: c.accent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    req.isNew ? '新建文章' : '修改文章',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: c.textPrimary,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _showFullNew = !_showFullNew),
                  child: Text(
                    _showFullNew ? '看差异' : '看全文',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              req.path,
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: c.textSecondary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              _showFullNew
                  ? '将写入 ${req.newContent.length} 字符'
                  : '${diff.added} 行新增 · ${diff.removed} 行删除',
              style: TextStyle(fontSize: 11, color: c.textTertiary),
            ),
            const SizedBox(height: AppSpace.sm),

            Container(
              constraints: const BoxConstraints(maxHeight: 340),
              width: double.infinity,
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(10),
                child: _showFullNew
                    ? SelectableText(
                        req.newContent,
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          fontFamily: 'monospace',
                        ),
                      )
                    : _DiffView(lines: diff.lines),
              ),
            ),

            const SizedBox(height: AppSpace.md),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () =>
                        Navigator.of(context).pop(ApprovalDecision.abort),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: c.textSecondary,
                    ),
                    child: const Text('中止'),
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () =>
                        Navigator.of(context).pop(ApprovalDecision.reject),
                    child: const Text('不要'),
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: () =>
                        Navigator.of(context).pop(ApprovalDecision.approve),
                    child: const Text('写入'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DiffView extends StatelessWidget {
  const _DiffView({required this.lines});

  final List<DiffLine> lines;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines.map((l) {
        final isAdd = l.kind == DiffKind.added;
        final isRemove = l.kind == DiffKind.removed;
        final bg = isAdd
            ? c.accent.withValues(alpha: 0.12)
            : isRemove
                ? c.danger.withValues(alpha: 0.12)
                : Colors.transparent;
        final prefix = isAdd ? '+' : (isRemove ? '-' : ' ');

        return Container(
          width: double.infinity,
          color: bg,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          child: Text(
            '$prefix ${l.text}',
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              fontFamily: 'monospace',
              color: isRemove ? c.danger : c.textPrimary,
            ),
          ),
        );
      }).toList(),
    );
  }
}

enum DiffKind { same, added, removed }

class DiffLine {
  const DiffLine(this.kind, this.text);
  final DiffKind kind;
  final String text;
}

class DiffResult {
  const DiffResult({required this.lines, required this.added, required this.removed});
  final List<DiffLine> lines;
  final int added;
  final int removed;
}

/// 行级 Diff（LCS）。
///
/// 为什么不用现成的 diff 包：
/// 这几个包要么带原生代码，要么体积远大于这份 40 行实现；
/// 而我只需要「给用户看改了哪几行」，不需要字符级精细 Diff。
///
/// 大文件保护：超过 3000 行时放弃逐行比对，直接标「全文替换」——
/// LCS 是 O(n·m)，3000×3000 会让手机卡住几秒。
DiffResult computeDiff(String oldText, String newText) {
  final a = oldText.isEmpty ? <String>[] : oldText.split('\n');
  final b = newText.isEmpty ? <String>[] : newText.split('\n');

  if (a.length > 3000 || b.length > 3000) {
    final lines = <DiffLine>[
      const DiffLine(DiffKind.removed, '（文件过大，不逐行比对）'),
      ...b.map((t) => DiffLine(DiffKind.added, t)),
    ];
    return DiffResult(lines: lines, added: b.length, removed: a.length);
  }

  // LCS 表
  final m = a.length;
  final n = b.length;
  final lcs = List.generate(m + 1, (_) => List<int>.filled(n + 1, 0));

  for (var i = m - 1; i >= 0; i--) {
    for (var j = n - 1; j >= 0; j--) {
      lcs[i][j] = a[i] == b[j]
          ? lcs[i + 1][j + 1] + 1
          : (lcs[i + 1][j] >= lcs[i][j + 1] ? lcs[i + 1][j] : lcs[i][j + 1]);
    }
  }

  final lines = <DiffLine>[];
  var added = 0;
  var removed = 0;
  var i = 0;
  var j = 0;

  while (i < m && j < n) {
    if (a[i] == b[j]) {
      lines.add(DiffLine(DiffKind.same, a[i]));
      i++;
      j++;
    } else if (lcs[i + 1][j] >= lcs[i][j + 1]) {
      lines.add(DiffLine(DiffKind.removed, a[i]));
      removed++;
      i++;
    } else {
      lines.add(DiffLine(DiffKind.added, b[j]));
      added++;
      j++;
    }
  }
  while (i < m) {
    lines.add(DiffLine(DiffKind.removed, a[i]));
    removed++;
    i++;
  }
  while (j < n) {
    lines.add(DiffLine(DiffKind.added, b[j]));
    added++;
    j++;
  }

  return DiffResult(lines: lines, added: added, removed: removed);
}