import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hugosugar/app/theme/app_theme.dart';
import 'package:hugosugar/core/ai/ai_controller.dart';
import 'package:hugosugar/core/ai/ai_endpoint.dart';
import 'package:hugosugar/core/ai/chat_store.dart';
import 'package:hugosugar/features/ai/chat_page.dart';

/// 复现「发送消息后列表空白、且没有任何回复」。
///
/// 这里不 mock 网络，只验证**渲染与早退路径**：
/// 1. entries 里有 user 消息时，ListView 必须能画出来（不能抛布局异常）
/// 2. 发送前置检查失败时，输入不能丢、必须有可见提示
void main() {
  Widget wrap(AiController c) => MaterialApp(
        theme: AppTheme.light(),
        home: ChatPage(controller: c),
      );

  /// 造一个「有端点、已选模型」的配置
  AiConfig configured({String model = 'gpt-4o-mini'}) => AiConfig(
        endpoints: [
          AiEndpoint(
            id: 'ep_1',
            name: '测试端点',
            baseUrl: 'https://api.example.com/v1',
            model: model,
          ),
        ],
        activeId: 'ep_1',
      );

  ChatSession sessionWith(List<ChatEntry> entries) => ChatSession(
        id: 'chat_t',
        title: '测试',
        updatedAt: DateTime.now(),
        endpointId: 'ep_1',
        model: 'gpt-4o-mini',
        entries: entries,
      );

  testWidgets('user 消息能正常渲染（不能有 layout 异常）', (tester) async {
    final ctrl = AiController();
    addTearDown(ctrl.dispose);

    // 跳过 init()：它走 path_provider，测试环境里拿不到真实目录会卡住
    ctrl.debugSetConfig(configured());
    ctrl.debugSetSession(sessionWith([
      ChatEntry(role: 'user', text: '帮我写一篇文章', at: DateTime.now()),
    ]));

    await tester.pumpWidget(wrap(ctrl));
    await tester.pump();

    final err = tester.takeException();
    expect(err, isNull, reason: '列表渲染抛异常：$err');
    expect(find.text('帮我写一篇文章'), findsOneWidget);
  });

  testWidgets('user + assistant 混合也能渲染', (tester) async {
    final ctrl = AiController();
    addTearDown(ctrl.dispose);

    ctrl.debugSetConfig(configured());
    ctrl.debugSetSession(sessionWith([
      ChatEntry(role: 'user', text: '第一条问题', at: DateTime.now()),
      ChatEntry(role: 'assistant', text: '第一条回答', at: DateTime.now()),
      ChatEntry(role: 'user', text: '第二条问题', at: DateTime.now()),
    ]));

    await tester.pumpWidget(wrap(ctrl));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('第一条问题'), findsOneWidget);
    expect(find.text('第一条回答'), findsOneWidget);
    expect(find.text('第二条问题'), findsOneWidget);
  });

  testWidgets('没选模型时发送：输入要保留，且给出可见提示', (tester) async {
    final ctrl = AiController();
    addTearDown(ctrl.dispose);

    // 端点存在但没选模型 —— validateSend 会拦下
    ctrl.debugSetConfig(configured(model: ''));

    await tester.pumpWidget(wrap(ctrl));
    await tester.pump();

    await tester.enterText(find.byType(TextField), '这条消息应该留在输入框里');
    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    // 关键断言：输入不能被吞掉
    final tf = tester.widget<TextField>(find.byType(TextField));
    expect(tf.controller!.text, '这条消息应该留在输入框里');

    // 必须有可见提示（不是只写进 controller 的私有字段）
    expect(find.textContaining('选择模型'), findsWidgets);
  });

  testWidgets('lastError 会显示成错误条，且能关掉', (tester) async {
    final ctrl = AiController();
    addTearDown(ctrl.dispose);

    ctrl.debugSetConfig(configured());
    ctrl.debugSetSession(sessionWith(const []));

    await tester.pumpWidget(wrap(ctrl));
    await tester.pump();
    expect(find.text('连接失败：超时'), findsNothing);

    ctrl.debugSetError('连接失败：超时');
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('连接失败：超时'), findsOneWidget);

    // 点掉
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(find.text('连接失败：超时'), findsNothing);
  });
}
