import 'package:flutter_test/flutter_test.dart';
import 'package:hugosugar/core/ai/ai_controller.dart';
import 'package:hugosugar/core/ai/ai_endpoint.dart';

/// 端点 / 模型的切换逻辑。
///
/// 用户反馈：「多 api 接口时无法切换 api，还有无法快速切换模型」。
/// 根因是 UI 把「点卡片」绑成了编辑、切换藏在二级菜单里，
/// 而且换模型必须走「编辑 → 获取列表 → 选 → 保存」六步。
///
/// 这些测试覆盖 controller 层的行为约束 —— 不论 UI 怎么摆，
/// 「切换是否真的生效、是否原子、生成中是否被拦住」都必须成立。
void main() {
  const epA = AiEndpoint(
    id: 'ep_a',
    name: 'A 端点',
    baseUrl: 'https://a.example.com/v1',
    model: 'model-a1',
  );
  const epB = AiEndpoint(
    id: 'ep_b',
    name: 'B 端点',
    baseUrl: 'https://b.example.com/v1',
    model: 'model-b1',
  );

  AiController makeController({String activeId = 'ep_a'}) {
    final c = AiController();
    c.debugSetConfig(
      AiConfig(endpoints: const [epA, epB], activeId: activeId),
    );
    return c;
  }

  group('setActiveEndpoint', () {
    test('切换后 activeEndpoint 指向新端点', () async {
      final c = makeController();
      expect(c.activeEndpoint?.id, 'ep_a');

      await c.setActiveEndpoint('ep_b');
      expect(c.activeEndpoint?.id, 'ep_b');
      // 模型要跟着端点走，不能还留着 A 的模型名
      expect(c.activeEndpoint?.model, 'model-b1');
    });

    test('切到不存在的 id 时不会被当成有效选中', () async {
      final c = makeController();
      await c.setActiveEndpoint('ep_not_exist');
      // activeId 被写成了不存在的值，但 active 会回落到第一个 —— 
      // 界面不会空着，这比抛异常好。
      expect(c.activeEndpoint, isNotNull);
      expect(c.activeEndpoint?.id, 'ep_a');
    });
  });

  group('switchModel（快速切换）', () {
    test('只传 model：在同一个端点内换模型', () async {
      final c = makeController();
      final ok = await c.switchModel(model: 'model-a2');

      expect(ok, isTrue);
      expect(c.activeEndpoint?.id, 'ep_a', reason: '端点不该变');
      expect(c.activeEndpoint?.model, 'model-a2');
    });

    test('同时传 endpointId 和 model：一次到位', () async {
      final c = makeController();
      final ok = await c.switchModel(
        endpointId: 'ep_b',
        model: 'model-b9',
      );

      expect(ok, isTrue);
      expect(c.activeEndpoint?.id, 'ep_b');
      expect(c.activeEndpoint?.model, 'model-b9');
    });

    test('只传 endpointId：切端点，保留该端点原有模型', () async {
      final c = makeController();
      await c.switchModel(endpointId: 'ep_b');

      expect(c.activeEndpoint?.id, 'ep_b');
      // 不能把 A 的模型名带到 B 上
      expect(c.activeEndpoint?.model, 'model-b1');
    });

    test('两个参数都不传：不产生非法状态', () async {
      final c = makeController();
      // endpointId 为空时回落到当前端点，model 为空表示不改
      final ok = await c.switchModel();

      expect(ok, isTrue);
      expect(c.activeEndpoint?.id, 'ep_a');
      expect(c.activeEndpoint?.model, 'model-a1');
    });

    test('空白字符串不被当成有效模型名', () async {
      final c = makeController();
      await c.switchModel(model: '   ');
      // 不能被空格覆盖成空模型
      expect(c.activeEndpoint?.model, 'model-a1');
    });
  });

  group('生成中禁止切换', () {
    test('busy 时 switchModel 返回 false 且配置完全不变', () async {
      final c = makeController();
      c.debugSetBusy(true);

      final ok = await c.switchModel(endpointId: 'ep_b', model: 'model-b9');

      expect(ok, isFalse, reason: '生成中必须拒绝切换');
      // 关键：不能出现「端点没换但模型换了」这种半生效状态
      expect(c.activeEndpoint?.id, 'ep_a');
      expect(c.activeEndpoint?.model, 'model-a1');
    });

    test('busy 时 setActiveEndpoint 也不生效', () async {
      final c = makeController();
      c.debugSetBusy(true);

      await c.setActiveEndpoint('ep_b');

      expect(c.activeEndpoint?.id, 'ep_a');
    });

    test('busy 解除后可以正常切换', () async {
      final c = makeController();
      c.debugSetBusy(true);
      expect((await c.switchModel(endpointId: 'ep_b')), isFalse);

      c.debugSetBusy(false);
      expect((await c.switchModel(endpointId: 'ep_b')), isTrue);
      expect(c.activeEndpoint?.id, 'ep_b');
    });
  });

  group('模型缓存', () {
    test('未拉取过的端点没有缓存', () {
      final c = makeController();
      expect(c.cachedModels('ep_a'), isNull);
    });
  });
}