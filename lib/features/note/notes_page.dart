import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../shared/widgets.dart';

/// 笔记页：碎片化灵感。卡片式布局，置顶区单独分组。
///
/// 置顶笔记会进 AI 的 System Prompt，所以行尾有一个小圆点提示。
class NotesPage extends StatelessWidget {
  const NotesPage({super.key});

  static const _pinned = [
    _NoteMock('写作偏好', '中文与英文之间加空格；少用破折号；段落短。'),
    _NoteMock('常用术语', 'drift = 数据库层；Widget = 界面单元。'),
  ];

  static const _others = [
    _NoteMock('Hugo 的 Front Matter', 'title / date / draft / tags / categories。'),
    _NoteMock('Vercel Deploy Hook 想法', 'push 完 POST 一下就能触发构建。'),
    _NoteMock('灵感：把写作工具做轻', '不要终端、不要构建，只留写和发。'),
    _NoteMock('SQLite 选型', 'drift 有类型安全，值得。'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('笔记'),
        actions: [
          IconButton(onPressed: () {}, icon: const Icon(Icons.search)),
          const SizedBox(width: AppSpace.xs),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        tooltip: '新建笔记',
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          const SectionHeader('置顶 · 2  ·  会注入 AI 上下文'),
          for (final n in _pinned) _NoteCard(note: n, pinned: true),
          const SectionHeader('全部 · 4'),
          for (final n in _others) _NoteCard(note: n, pinned: false),
        ],
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.note, required this.pinned});

  final _NoteMock note;
  final bool pinned;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.xs,
      ),
      child: InkWell(
        onTap: () {},
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          padding: const EdgeInsets.all(AppSpace.sm),
          decoration: BoxDecoration(
            color: pinned ? c.surfaceHigh : c.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      note.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                  if (pinned)
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: c.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpace.xxs),
              Text(
                note.preview,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.55,
                  color: c.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoteMock {
  const _NoteMock(this.title, this.preview);
  final String title;
  final String preview;
}