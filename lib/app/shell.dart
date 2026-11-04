import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'i18n/l10n_scope.dart';
import 'theme/app_colors.dart';
import '../core/ai/ai_controller.dart';
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
    required this.aiController,
    this.onAccentChanged,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final SiteController siteController;
  final NoteController noteController;
  final SettingsController settingsController;
  final AiController aiController;
  final VoidCallback? onAccentChanged;

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

  /// 连续两次返回的允许间隔。
  ///
  /// 用 2 秒而不是更长：这是「防误触」而不是「确认操作」，
  /// 窗口太长会让真正想退出的人多按几次。
  static const _exitWindow = Duration(seconds: 2);

  /// 是否正处在「再按一次就退出」的等待窗口里。
  bool _awaitingExit = false;
  Timer? _exitTimer;

  /// 拦截系统返回键。
  ///
  /// 分两级，避免一次误触就把 App 关掉：
  /// 1. 不在首个 Tab → 先回「想法」，不影响任何已输入内容
  /// 2. 已在首个 Tab → 提示「再按一次返回退出」，2 秒内再按才真退出
  ///
  /// 只在根路由生效。编辑器、备份页这些 push 上去的页面有自己的返回栈，
  /// 不会走到这里（PopScope 只拦它所在的那个 route）。
  void _handleBack() {
    if (_index != 0) {
      setState(() => _index = 0);
      _tabIndex.value = 0;
      return;
    }

    // 用 Timer 而不是比较 DateTime 前后差值：
    // 窗口到期要自动复位状态，Timer 天然做到；而且 widget 测试里
    // pump 能推进 Timer，却推不动 DateTime.now()。
    if (!_awaitingExit) {
      _awaitingExit = true;
      _exitTimer?.cancel();
      _exitTimer = Timer(_exitWindow, () => _awaitingExit = false);

      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(context.tr('再按一次返回键退出')),
          // 提示与判定窗口同步，条子消失即意味着「再按也没用了」。
          duration: _exitWindow,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    _exitTimer?.cancel();
    _awaitingExit = false;
    SystemNavigator.pop();
  }

  @override
  void dispose() {
    _exitTimer?.cancel();
    _tabIndex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;

    // web 上「后退」是浏览器导航语义，不是退出 App。拦下来只会让用户
    // 退不出页面，所以只在移动端/桌面端接管返回键。
    final interceptBack = !kIsWeb;

    // canPop: false 表示「系统返回键一律先交给我判断」。
    // 真正的退出由 _handleBack 里的 SystemNavigator.pop() 执行。
    return PopScope(
      canPop: !interceptBack,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !interceptBack) return;
        _handleBack();
      },
      child: Scaffold(
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
            ChatPage(controller: widget.aiController),
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
              aiController: widget.aiController,
              noteController: widget.noteController,
              onAccentChanged: widget.onAccentChanged,
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
              // 换了 Tab 就重置窗口，否则切回来时残留的「等待退出」状态
              // 会让第一次返回被当成第二次，直接退出。
              _exitTimer?.cancel();
              _awaitingExit = false;
            },
            // 去掉 const：label 要调 context.tr，常量表达式不允许。
            destinations: [
              NavigationDestination(
                icon: const Icon(Icons.lightbulb_outline),
                selectedIcon: const Icon(Icons.lightbulb),
                label: context.tr('想法'),
              ),
              NavigationDestination(
                icon: const Icon(Icons.article_outlined),
                selectedIcon: const Icon(Icons.article),
                label: context.tr('文章'),
              ),
              const NavigationDestination(
                icon: Icon(Icons.auto_awesome_outlined),
                selectedIcon: Icon(Icons.auto_awesome),
                label: 'AI',
              ),
              NavigationDestination(
                icon: const Icon(Icons.folder_outlined),
                selectedIcon: const Icon(Icons.folder),
                label: context.tr('站点'),
              ),
              NavigationDestination(
                icon: const Icon(Icons.settings_outlined),
                selectedIcon: const Icon(Icons.settings),
                label: context.tr('设置'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}