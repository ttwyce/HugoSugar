import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hugosugar/app/theme/app_colors.dart';
import 'package:hugosugar/app/theme/app_theme.dart';
import 'package:hugosugar/app/shell.dart';
import 'package:hugosugar/core/ai/ai_controller.dart';
import 'package:hugosugar/core/note/note_controller.dart';
import 'package:hugosugar/core/note/note_store.dart';
import 'package:hugosugar/core/settings/settings_controller.dart';
import 'package:hugosugar/core/site/site_controller.dart';
import 'package:path/path.dart' as p;

/// 建一个临时笔记库，避免测试碰到真实的 App 私有目录
Future<NoteController> _tempNoteController() async {
  final dir = Directory.systemTemp.createTempSync('hs_shell_test');
  final store = await NoteStore.openAt(p.join(dir.path, 'notes.json'));
  return NoteController(store: store);
}

Widget _wrap({
  required ThemeMode mode,
  required NoteController notes,
  required SiteController site,
}) {
  return MaterialApp(
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    themeMode: mode,
    home: AppShell(
      themeMode: mode,
      onThemeModeChanged: (_) {},
      // 测试里不调 load()，控制器保持 empty 状态，不碰文件系统
      siteController: site,
      noteController: notes,
      settingsController: SettingsController(),
      aiController: AiController(
        noteController: notes,
        siteController: site,
      ),
    ),
  );
}

void main() {
  late NoteController notes;
  late SiteController site;

  setUp(() async {
    notes = await _tempNoteController();
    site = SiteController();
  });

  tearDown(() {
    notes.dispose();
    site.dispose();
  });

  testWidgets('外壳渲染出 5 个 Tab', (tester) async {
    await tester.pumpWidget(_wrap(mode: ThemeMode.light, notes: notes, site: site));
    await tester.pumpAndSettle();

    expect(find.text('文章'), findsWidgets);
    expect(find.text('想法'), findsWidgets);
    expect(find.text('AI'), findsWidgets);
    expect(find.text('站点'), findsWidgets);
    expect(find.text('设置'), findsWidgets);
  });

  testWidgets('亮色与暗色主题的 token 不同', (tester) async {
    await tester.pumpWidget(_wrap(mode: ThemeMode.light, notes: notes, site: site));
    await tester.pumpAndSettle();
    final lightBg = tester
        .widget<MaterialApp>(find.byType(MaterialApp))
        .theme!
        .extension<AppColors>()!
        .background;

    await tester.pumpWidget(_wrap(mode: ThemeMode.dark, notes: notes, site: site));
    await tester.pumpAndSettle();
    final darkBg = tester
        .widget<MaterialApp>(find.byType(MaterialApp))
        .darkTheme!
        .extension<AppColors>()!
        .background;

    expect(lightBg, isNot(darkBg));
  });

  testWidgets('切换 Tab 到设置页', (tester) async {
    await tester.pumpWidget(_wrap(mode: ThemeMode.light, notes: notes, site: site));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(find.text('外观'), findsOneWidget);
    expect(find.text('跟随系统'), findsOneWidget);
  });

  testWidgets('想法是第一个 Tab，文章第二', (tester) async {
    await tester.pumpWidget(
      _wrap(mode: ThemeMode.light, notes: notes, site: site),
    );
    await tester.pumpAndSettle();

    // NavigationBar 的 destination 顺序即 Tab 顺序
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    final labels = bar.destinations
        .cast<NavigationDestination>()
        .map((e) => e.label)
        .toList();
    expect(labels.first, '想法', reason: '想法应该是默认首屏');
    expect(labels[1], '文章');
    expect(labels.length, 5);
  });

  testWidgets('切到想法 Tab 显示空状态', (tester) async {
    await tester.pumpWidget(_wrap(mode: ThemeMode.light, notes: notes, site: site));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.lightbulb_outline));
    await tester.pumpAndSettle();

    expect(find.textContaining('还没有想法'), findsOneWidget);
  });

  // ── 返回键拦截 ──

  /// 模拟按一次系统返回键。
  ///
  /// 走的是 WidgetsBinding.handlePopRoute，和真机上按下返回键的路径一致：
  /// 它会依次问每个 observer，最终落到根路由的 PopScope。
  Future<void> pressBack(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await tester.pump();
  }

  /// 拦截平台通道，用来断言是否真的调用了退出。
  List<String> capturePlatformCalls(WidgetTester tester) {
    final calls = <String>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call.method);
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });
    return calls;
  }

  testWidgets('在非首个 Tab 按返回，先回到想法 Tab，不退出', (tester) async {
    final calls = capturePlatformCalls(tester);
    await tester.pumpWidget(
      _wrap(mode: ThemeMode.light, notes: notes, site: site),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      4,
    );

    await pressBack(tester);

    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      0,
      reason: '非首个 Tab 按返回应该只回到想法，不该直接退出 App',
    );
    expect(calls, isNot(contains('SystemNavigator.pop')));
  });

  testWidgets('在首个 Tab 按返回，只提示，不退出', (tester) async {
    final calls = capturePlatformCalls(tester);
    await tester.pumpWidget(
      _wrap(mode: ThemeMode.light, notes: notes, site: site),
    );
    await tester.pumpAndSettle();

    await pressBack(tester);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('再按一次返回键退出'), findsOneWidget);
    expect(calls, isNot(contains('SystemNavigator.pop')));

    // 等提示自然消失，避免测试结束时留下未触发的 Timer
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('2 秒内再按一次才真正退出', (tester) async {
    final calls = capturePlatformCalls(tester);
    await tester.pumpWidget(
      _wrap(mode: ThemeMode.light, notes: notes, site: site),
    );
    await tester.pumpAndSettle();

    await pressBack(tester);
    await tester.pump(const Duration(milliseconds: 300));
    await pressBack(tester);

    expect(calls, contains('SystemNavigator.pop'));
  });

  testWidgets('超过 2 秒窗口后再按，重新计时而不是直接退出', (tester) async {
    final calls = capturePlatformCalls(tester);
    await tester.pumpWidget(
      _wrap(mode: ThemeMode.light, notes: notes, site: site),
    );
    await tester.pumpAndSettle();

    await pressBack(tester);
    await tester.pump(const Duration(seconds: 3)); // 窗口过期

    await pressBack(tester);
    await tester.pump(const Duration(milliseconds: 300));

    expect(calls, isNot(contains('SystemNavigator.pop')));
    expect(find.text('再按一次返回键退出'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
  });
}