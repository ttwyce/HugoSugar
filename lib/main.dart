import 'package:flutter/material.dart';
import 'package:git2dart/git2dart.dart';

import 'app/theme/app_theme.dart';
import 'app/shell.dart';
import 'core/site/site_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ★ M0 关键：移动端必须先初始化 git2dart 的平台支持，
  //   否则 clone / remote / credential 相关 API 会直接失败（Android 需要
  //   定位 libgit2 的 so，iOS 需要配置动态库路径）。
  await PlatformSpecific.initialize();

  runApp(const HugoSugarApp());
}

class HugoSugarApp extends StatefulWidget {
  const HugoSugarApp({super.key});

  @override
  State<HugoSugarApp> createState() => _HugoSugarAppState();
}

class _HugoSugarAppState extends State<HugoSugarApp> {
  ThemeMode _themeMode = ThemeMode.system;

  // 站点状态放这里，M1 只有一个站点，全局单例足够。
  // 以后上多站点再考虑换成 InheritedNotifier。
  final _siteController = SiteController();

  @override
  void initState() {
    super.initState();
    // 异步恢复上次接入的站点，不阻塞首帧
    _siteController.load();
  }

  @override
  void dispose() {
    _siteController.dispose();
    super.dispose();
  }

  void _onThemeModeChanged(ThemeMode mode) {
    setState(() => _themeMode = mode);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HugoSugar',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: _themeMode,
      home: AppShell(
        themeMode: _themeMode,
        onThemeModeChanged: _onThemeModeChanged,
        siteController: _siteController,
      ),
    );
  }
}