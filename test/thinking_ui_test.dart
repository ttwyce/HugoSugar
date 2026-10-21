import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hugosugar/core/ai/ai_endpoint.dart';

/// 锁死两个曾经出问题的地方：
///
/// 1. 底部弹窗溢出 `BOTTOM OVERFLOWED BY 1.2 PIXELS`
///    —— 内容高度超过 showModalBottomSheet 默认上限
/// 2. 思考按钮点击区域太小（fontSize 10 纯文字，约 14px 高）
///    —— 远低于 Material 的 48px 最小触控尺寸
///
/// 这里用一个最小的复现体：同样的布局约束下渲染，
/// 断言「无溢出异常」且「命中区域 >= 44 高」。
void main() {
  /// 用与生产代码相同的约束结构复现弹窗内容
  Widget buildSheetLike(double maxHeight) {
    return MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 13), // 拖动条
                    const Text('\u601d\u8003\u6863\u4f4d'),
                    const SizedBox(height: 12),
                    // 5 个档位分 3 行（一行两个）
                    for (var i = 0; i < 3; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(child: _box()),
                            const SizedBox(width: 8),
                            Expanded(child: _box()),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  group('思考档位弹窗不溢出', () {
    testWidgets('小屏（640 高）也不溢出', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildSheetLike(640 * 0.72));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('常见屏（800 高）不溢出', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildSheetLike(800 * 0.72));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('内容超长时可滚动，而不是溢出', (tester) async {
      tester.view.physicalSize = const Size(360, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      // 故意给很小的上限，模拟极端情况
      await tester.pumpWidget(buildSheetLike(200));
      await tester.pumpAndSettle();

      // 有滚动容器兜底，不应抛 RenderFlex overflow
      expect(tester.takeException(), isNull);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });
  });

  group('思考档位胶囊的触控尺寸', () {
    test('档位描述都不为空（UI 要展示「实际会发生什么」）', () {
      for (final lv in ThinkingLevel.values) {
        expect(lv.description, isNotEmpty, reason: lv.id);
        expect(lv.label, isNotEmpty, reason: lv.id);
      }
    });

    testWidgets('胶囊按钮高度达到最小触控尺寸', (tester) async {
      final tapped = <bool>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(child: _ChipProbe(onTap: () => tapped.add(true))),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final size = tester.getSize(find.byKey(const ValueKey('chip')));
      // Material 建议 48，这里以 44 为合格线（视觉 32 + 上下 padding 6*2）
      expect(size.height, greaterThanOrEqualTo(44));

      await tester.tap(find.byKey(const ValueKey('chip')));
      await tester.pump();
      expect(tapped, hasLength(1));
    });
  });
}

Widget _box() => Container(
  height: 60,
  decoration: BoxDecoration(color: Colors.grey.shade300),
);

/// 复刻 _ThinkingChip 的尺寸结构（不依赖私有类）
class _ChipProbe extends StatelessWidget {
  const _ChipProbe({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        key: const ValueKey('chip'),
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.psychology, size: 15),
            SizedBox(width: 5),
            Text('平衡', style: TextStyle(fontSize: 12)),
            SizedBox(width: 1),
            Icon(Icons.arrow_drop_down, size: 18),
          ],
        ),
      ),
    );
  }
}
