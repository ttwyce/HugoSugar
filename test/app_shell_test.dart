import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hugosugar/app/theme/app_colors.dart';
import 'package:hugosugar/app/theme/app_theme.dart';
import 'package:hugosugar/app/shell.dart';
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
    expect(find.text('笔记'), findsWidgets);
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

  testWidgets('切到笔记 Tab 显示空状态', (tester) async {
    await tester.pumpWidget(_wrap(mode: ThemeMode.light, notes: notes, site: site));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.lightbulb_outline));
    await tester.pumpAndSettle();

    expect(find.textContaining('还没有笔记'), findsOneWidget);
  });
}