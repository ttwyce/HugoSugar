import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hugosugar/app/theme/app_theme.dart';
import 'package:hugosugar/app/theme/reading_prefs.dart';

/// 回归测试：正文字号/字体改动要能实时反映到编辑器文字样式上。
void main() {
  testWidgets('改字号后编辑器文字 style 立即变化', (tester) async {
    var sizeIndex = 2;
    var family = '';
    late StateSetter setOuter;

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          setOuter = setState;
          return MaterialApp(
            theme: AppTheme.light(
              reading: ReadingPrefs(
                fontSize: ReadingPrefs.sizeForIndex(sizeIndex),
                fontFamily: family,
              ),
            ),
            home: Builder(
              builder: (ctx) => Scaffold(
                body: Text(
                  '正文',
                  key: const Key('body'),
                  style: ctx.reading.apply(
                    AppTypography.editorBody.copyWith(color: Colors.black),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );

    double currentSize() {
      final w = tester.widget<Text>(find.byKey(const Key('body')));
      return w.style!.fontSize!;
    }

    expect(currentSize(), 17);

    // 调到最大档
    setOuter(() => sizeIndex = 4);
    await tester.pumpAndSettle();
    expect(currentSize(), 20);

    // 改字体
    setOuter(() => family = 'serif');
    await tester.pumpAndSettle();
    final w = tester.widget<Text>(find.byKey(const Key('body')));
    expect(w.style!.fontFamily, 'serif');
  });
}