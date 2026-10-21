import 'package:flutter/material.dart';
import 'package:git2dart/git2dart.dart';

import 'app/theme/app_theme.dart';
import 'app/shell.dart';
import 'core/ai/ai_controller.dart';
import 'core/note/note_controller.dart';
import 'core/note/note_store.dart';
import 'core/settings/app_settings.dart';
import 'core/settings/settings_controller.dart';
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
  final _settingsController = SettingsController();
  late final _siteController = SiteController(settings: _settingsController);

  /// 笔记库。异步打开，打开前 UI 显示空列表（而不是转圈），
  /// 因为本地文件读取通常 <50ms，值得用「直接可用」换掉闪一下的加载态。
  NoteController? _noteController;

  /// AI 控制器。它依赖笔记与站点，所以要等这两个就绪后再建。
  AiController? _aiController;

  @override
  void initState() {
    super.initState();
    // 异步恢复上次接入的站点，不阻塞首帧
    _siteController.load();
    _initSettings();
    _initNotes();
  }

  /// 偏好设置要在站点读取配置之前尽量就位，但它影响的是「写文件」，
  /// 不阻塞首帧显示，所以和 load 并行就好。
  Future<void> _initSettings() async {
    final store = await SettingsStore.open();
    await _settingsController.load(store: store);
  }

  Future<void> _initNotes() async {
    final store = await NoteStore.open();
    if (!mounted) return;
    final notes = NoteController(store: store, site: _siteController);

    // AI 必须在笔记之后建：它要用 NoteController 读想法。
    final ai = AiController(
      noteController: notes,
      siteController: _siteController,
      // 让 AI 能读到用户自定义的 System Prompt 与 token 上限
      settings: _settingsController,
    );
    await ai.init();

    if (!mounted) {
      ai.dispose();
      notes.dispose();
      return;
    }
    setState(() {
      _noteController = notes;
      _aiController = ai;
    });
  }

  @override
  void dispose() {
    _aiController?.dispose();
    _noteController?.dispose();
    _siteController.dispose();
    _settingsController.dispose();
    super.dispose();
  }

  void _onThemeModeChanged(ThemeMode mode) {
    setState(() => _themeMode = mode);
  }

  @override
  Widget build(BuildContext context) {
    final notes = _noteController;
    final ai = _aiController;

    return MaterialApp(
      title: 'HugoSugar',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(
          accentIndex: _settingsController.accentPreset),
      darkTheme: AppTheme.dark(
          accentIndex: _settingsController.accentPreset),
      themeMode: _themeMode,
      home: notes == null || ai == null
          // 笔记库打开前的极短占位。用空白而不是转圈，
          // 避免一闪而过的加载动画更刺眼。
          ? Scaffold(backgroundColor: Theme.of(context).scaffoldBackgroundColor)
          : AppShell(
              themeMode: _themeMode,
              onThemeModeChanged: _onThemeModeChanged,
              onAccentChanged: () => setState(() {}),
              siteController: _siteController,
              noteController: notes,
              settingsController: _settingsController,
              aiController: ai,
            ),
    );
  }
}