import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:operit_flutter_project/app/theme/app_colors.dart';
import 'package:operit_flutter_project/app/theme/app_theme.dart';
import 'package:operit_flutter_project/app/shell.dart';
import 'package:operit_flutter_project/core/site/site_controller.dart';

Widget _wrap({required ThemeMode mode}) {
  return MaterialApp(
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    themeMode: mode,
    home: AppShell(
      themeMode: mode,
      onThemeModeChanged: (_) {},
      // 测试里不调 load()，控制器保持 empty 状态，不碰文件系统
      siteController: SiteController(),
    ),
  );
}

void main() {
  testWidgets('外壳渲染出 5 个 Tab', (tester) async {
    await tester.pumpWidget(_wrap(mode: ThemeMode.light));
    await tester.pumpAndSettle();

    expect(find.text('文章'), findsWidgets);
    expect(find.text('笔记'), findsWidgets);
    expect(find.text('AI'), findsWidgets);
    expect(find.text('站点'), findsWidgets);
    expect(find.text('设置'), findsWidgets);
  });

  testWidgets('亮色与暗色主题的 token 不同', (tester) async {
    await tester.pumpWidget(_wrap(mode: ThemeMode.light));
    await tester.pumpAndSettle();
    final lightBg = tester
        .widget<MaterialApp>(find.byType(MaterialApp))
        .theme!
        .extension<AppColors>()!
        .background;

    await tester.pumpWidget(_wrap(mode: ThemeMode.dark));
    await tester.pumpAndSettle();
    final darkBg = tester
        .widget<MaterialApp>(find.byType(MaterialApp))
        .darkTheme!
        .extension<AppColors>()!
        .background;

    expect(lightBg, isNot(darkBg));
  });

  testWidgets('切换 Tab 到设置页', (tester) async {
    await tester.pumpWidget(_wrap(mode: ThemeMode.light));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(find.text('外观'), findsOneWidget);
    expect(find.text('跟随系统'), findsOneWidget);
  });
}