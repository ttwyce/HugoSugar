import 'package:flutter/material.dart';

import 'theme/app_colors.dart';
import '../core/note/note_controller.dart';
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
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final SiteController siteController;
  final NoteController noteController;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;

    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          PostsPage(siteController: widget.siteController),
          NotesPage(controller: widget.noteController),
          const ChatPage(),
          SitePage(controller: widget.siteController),
          SettingsPage(
            themeMode: widget.themeMode,
            onThemeModeChanged: widget.onThemeModeChanged,
            siteController: widget.siteController,
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
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.article_outlined),
              selectedIcon: Icon(Icons.article),
              label: '文章',
            ),
            NavigationDestination(
              icon: Icon(Icons.lightbulb_outline),
              selectedIcon: Icon(Icons.lightbulb),
              label: '笔记',
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