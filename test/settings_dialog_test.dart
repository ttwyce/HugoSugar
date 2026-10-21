import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hugosugar/app/theme/app_theme.dart';
import 'package:hugosugar/core/ai/ai_controller.dart';
import 'package:hugosugar/core/note/note_controller.dart';
import 'package:hugosugar/core/note/note_store.dart';
import 'package:hugosugar/core/settings/settings_controller.dart';
import 'package:hugosugar/core/site/site_controller.dart';
import 'package:hugosugar/features/settings/settings_page.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePP extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePP(this.root);
  final String root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
  @override
  Future<String?> getTemporaryPath() async => root;
}

/// 建好页面所需的依赖。
///
/// **必须在 runAsync 里跑**：testWidgets 默认用 FakeAsync，
/// 真实文件 IO 的 Future 永远不会被推进，await 会挂到超时。
/// 这也是为什么最初几个探测测试全都「did not complete」。
Future<void> _scrollTo(WidgetTester tester, String text) async {
  final f = find.text(text);
  if (f.evaluate().isNotEmpty) return;
  await tester.scrollUntilVisible(
    f,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pump();
}

Future<Widget> _build(WidgetTester tester) async {
  late Widget page;
  await tester.runAsync(() async {
    final tmp = Directory.systemTemp.createTempSync('hs_pp');
    PathProviderPlatform.instance = _FakePP(tmp.path);

    final dir = Directory.systemTemp.createTempSync('hs_n');
    final store = await NoteStore.openAt(p.join(dir.path, 'notes.json'));
    final notes = NoteController(store: store);
    final settings = SettingsController();
    final site = SiteController(settings: settings);
    final ai = AiController(noteController: notes, siteController: site);

    page = MaterialApp(
      theme: AppTheme.light(),
      home: SettingsPage(
        themeMode: ThemeMode.light,
        onThemeModeChanged: (_) {},
        siteController: site,
        settingsController: settings,
        aiController: ai,
      ),
    );
  });
  return page;
}

void main() {
  testWidgets('token 上限弹窗：点取消不崩', (tester) async {
    await tester.pumpWidget(await _build(tester));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await _scrollTo(tester, '单轮 token 上限');
    await tester.tap(find.text('单轮 token 上限'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('tokens'), findsWidgets);

    await tester.tap(find.text('取消'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('设置'), findsWidgets);
  });

  testWidgets('token 上限弹窗：点保存不崩', (tester) async {
    await tester.pumpWidget(await _build(tester));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await _scrollTo(tester, '单轮 token 上限');
    await tester.tap(find.text('单轮 token 上限'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.text('保存'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('上下文压缩弹窗：取消与保存都不崩', (tester) async {
    await tester.pumpWidget(await _build(tester));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await _scrollTo(tester, '上下文压缩');
    await tester.tap(find.text('上下文压缩'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('取消'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await _scrollTo(tester, '上下文压缩');
    await tester.tap(find.text('上下文压缩'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('保存'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('设置'), findsWidgets);
  });

  testWidgets('反复开关 token 弹窗不崩', (tester) async {
    await tester.pumpWidget(await _build(tester));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    for (var i = 0; i < 3; i++) {
      await _scrollTo(tester, '单轮 token 上限');
    await tester.tap(find.text('单轮 token 上限'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('取消'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('设置'), findsWidgets);
  });
}