import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hugosugar/app/theme/app_theme.dart';
import 'package:hugosugar/app/theme/reading_prefs.dart';
import 'package:hugosugar/core/settings/settings_controller.dart';

/// 集成回归：模拟 main.dart 的结构——顶层订阅 SettingsController，
/// 并用 push 出一个「编辑器页」（模拟真实压栈路由），
/// 设置改字号后，压栈路由上的正文 TextField 字号必须实时更新。
void main() {
  testWidgets('压栈路由上的正文随设置实时变化', (tester) async {
    final ctrl = SettingsController();
    addTearDown(ctrl.dispose);
    final navKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(_Host(ctrl: ctrl, navKey: navKey));

    // 打开编辑器页（压栈）
    navKey.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => const _EditorStub(),
    ));
    await tester.pumpAndSettle();

    double bodySize() {
      final tf = tester.widget<TextField>(find.byKey(const Key('body')));
      return tf.style!.fontSize!;
    }

    expect(bodySize(), 17);

    await ctrl.setBodySizeIndex(4);
    await tester.pumpAndSettle();
    expect(bodySize(), 20, reason: '压栈路由上的正文也应实时变 20px');

    await ctrl.setBodyFontFamily('serif');
    await tester.pumpAndSettle();
    final tf = tester.widget<TextField>(find.byKey(const Key('body')));
    expect(tf.style!.fontFamily, 'serif');
  });
}

class _EditorStub extends StatelessWidget {
  const _EditorStub();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Builder(
        builder: (ctx) => TextField(
          key: const Key('body'),
          style: ctx.reading.apply(AppTypography.editorBody),
        ),
      ),
    );
  }
}

class _Host extends StatefulWidget {
  const _Host({required this.ctrl, required this.navKey});
  final SettingsController ctrl;
  final GlobalKey<NavigatorState> navKey;
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  @override
  void initState() {
    super.initState();
    widget.ctrl.addListener(_on);
  }

  void _on() => setState(() {});

  @override
  void dispose() {
    widget.ctrl.removeListener(_on);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reading = ReadingPrefs(
      fontSize: ReadingPrefs.sizeForIndex(widget.ctrl.bodySizeIndex),
      fontFamily: widget.ctrl.bodyFontFamily,
    );
    return MaterialApp(
      navigatorKey: widget.navKey,
      theme: AppTheme.light(reading: reading),
      home: const Scaffold(body: SizedBox()),
    );
  }
}