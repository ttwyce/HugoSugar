import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 验证「dialog 返回后延迟释放 controller」这个写法本身是安全的。
///
/// 注意：这里**不**断言「立刻释放一定崩」。实测在当前 Flutter 3.47 下，
/// 立刻释放并不会稳定复现 _dependents.isEmpty 断言。
/// 所以本文件只锁定「我们采用的写法不会引入新问题」，
/// 不假装自己证明了根因。
void main() {
  Future<void> openThenDisposeLater(
    WidgetTester tester, {
    required bool cancel,
  }) async {
    final ctrl = TextEditingController(text: '1');

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                await showDialog<bool>(
                  context: ctx,
                  builder: (dctx) => AlertDialog(
                    content: TextField(controller: ctrl),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(dctx).pop(false),
                        child: const Text('取消'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(dctx).pop(true),
                        child: const Text('确定'),
                      ),
                    ],
                  ),
                );
                WidgetsBinding.instance
                    .addPostFrameCallback((_) => ctrl.dispose());
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(cancel ? '取消' : '确定'));
    await tester.pumpAndSettle();
  }

  testWidgets('取消后延迟释放：无异常', (tester) async {
    await openThenDisposeLater(tester, cancel: true);
    expect(tester.takeException(), isNull);
  });

  testWidgets('确定后延迟释放：无异常', (tester) async {
    await openThenDisposeLater(tester, cancel: false);
    expect(tester.takeException(), isNull);
  });
}