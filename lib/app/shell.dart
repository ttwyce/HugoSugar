import 'package:flutter/material.dart';

import 'theme/app_colors.dart';
import '../core/note/note_controller.dart';
import '../core/settings/settings_controller.dart';
import '../core/site/site_controller.dart';
import '../features/post/posts_page.dart';
import '../features/note/notes_page.dart';
import '../features/ai/chat_page.dart';
import '../features/site/site_page.dart';
import '../features/settings/settings_page.dart';

/// 应用外壳：5 个 Tab + 底部导航。
///
/// 用 IndexedStack 保活，切 Tab 不重建、滚动位置不丢。
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.siteController,
    required this.noteController,
    required this.settingsController,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final SiteController siteController;
  final NoteController noteController;
  final SettingsController settingsController;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  /// 当前选中的 Tab 序号。
  ///
  /// 用 IndexedStack 保活意味着页面只会 initState 一次，
  /// 需要「切回来时刷新」的页面得能感知自己被切到了，
  /// 所以把索引做成 ValueNotifier 传下去。
  final _tabIndex = ValueNotifier<int>(0);

  @override
  void dispose() {
    _tabIndex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;

    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          // Tab 顺序：想法 → 文章 → AI → 站点 → 设置
          // 想法排第一，因为它是最高频的入口：随手记一句比写整篇多得多。
          NotesPage(
            controller: widget.noteController,
            settingsController: widget.settingsController,
          ),
          PostsPage(siteController: widget.siteController),
          const ChatPage(),
          SitePage(
            controller: widget.siteController,
            settingsController: widget.settingsController,
            visibleWhen: _tabIndex,
          ),
          SettingsPage(
            themeMode: widget.themeMode,
            onThemeModeChanged: widget.onThemeModeChanged,
            siteController: widget.siteController,
            settingsController: widget.settingsController,
          ),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: c.background,
          border: Border(top: BorderSide(color: c.divider, width: 1)),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) {
            setState(() => _index = i);
            _tabIndex.value = i;
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.lightbulb_outline),
              selectedIcon: Icon(Icons.lightbulb),
              label: '想法',
            ),
            NavigationDestination(
              icon: Icon(Icons.article_outlined),
              selectedIcon: Icon(Icons.article),
              label: '文章',
            ),
            NavigationDestination(
              icon: Icon(Icons.auto_awesome_outlined),
              selectedIcon: Icon(Icons.auto_awesome),
              label: 'AI',
            ),
            NavigationDestination(
              icon: Icon(Icons.folder_outlined),
              selectedIcon: Icon(Icons.folder),
              label: '站点',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: '设置',
            ),
          ],
        ),
      ),
    );
  }
}