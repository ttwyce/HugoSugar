import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../core/ai/ai_client.dart';
import '../../core/ai/ai_controller.dart';

/// 快速切换端点 / 模型的底部面板。
///
/// 之前换模型要：进端点页 → 点卡片 → 滚到模型框 → 获取列表 → 点选 → 保存，
/// 六步还得等网络。这里压到两步：点一下、选一下。
///
/// 结构是「两段式」：
///   1. 端点列表（当前端点打勾）
///   2. 当前端点的模型列表（可刷新、可手填）
///
/// 换端点后模型列表会切到新端点；如果新端点还没有模型，
/// 就允许直接手填 —— 很多中转站不实现 `/models`，不能因为拉不到
/// 列表就把用户卡死在这里。
Future<void> showModelSwitcher(
  BuildContext context,
  AiController controller,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ModelSwitcherSheet(controller: controller),
  );
}

class _ModelSwitcherSheet extends StatefulWidget {
  const _ModelSwitcherSheet({required this.controller});

  final AiController controller;

  @override
  State<_ModelSwitcherSheet> createState() => _ModelSwitcherSheetState();
}

class _ModelSwitcherSheetState extends State<_ModelSwitcherSheet> {
  /// 面板内**临时**选中的端点，不立刻写盘。
  /// 点了端点马上切换会让「只是看看另一个端点有哪些模型」变成破坏性操作。
  late String _pickedEndpointId;

  List<String> _models = const [];
  bool _loading = false;
  String? _error;

  /// 手填模型名
  final _manual = TextEditingController();
  bool _manualMode = false;

  AiController get ctrl => widget.controller;

  @override
  void initState() {
    super.initState();
    _pickedEndpointId = ctrl.activeEndpoint?.id ?? '';
    _manual.text = ctrl.activeEndpoint?.model ?? '';
    // 有缓存就直接显示，不打断用户；没有再去拉
    final cached = ctrl.cachedModels(_pickedEndpointId);
    if (cached != null) {
      _models = cached;
    } else if (_pickedEndpointId.isNotEmpty) {
      _fetch(force: false);
    }
  }

  @override
  void dispose() {
    _manual.dispose();
    super.dispose();
  }

  Future<void> _fetch({required bool force}) async {
    if (_loading) return;
    if (_pickedEndpointId.isEmpty) return;

    if (!force) {
      final cached = ctrl.cachedModels(_pickedEndpointId);
      if (cached != null) {
        setState(() => _models = cached);
        return;
      }
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final list = await ctrl.loadModels(_pickedEndpointId);
      if (!mounted) return;
      setState(() {
        _models = list;
        _loading = false;
        if (list.isEmpty) {
          _manualMode = true;
          _error = '这个端点没有返回模型列表，直接手填模型名';
        }
      });
    } on AiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        // 拉不到列表不算失败：允许手填
        _manualMode = true;
        _error = '${e.message}${e.hint == null ? '' : '\n${e.hint}'}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _manualMode = true;
        _error = '$e';
      });
    }
  }

  Future<void> _apply({String? model}) async {
    final ok = await ctrl.switchModel(
      endpointId: _pickedEndpointId,
      model: model,
    );
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('正在生成中，稍后再切换')),
      );
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final cfg = ctrl.config;
    final activeId = cfg.active?.id ?? '';

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        // 与端点编辑面板同样的坑：modal bottom sheet 里横向无界，
        // 必须给死宽度，否则 Row/Expanded 会抛 infinite width。
        child: SizedBox(
          width: MediaQuery.sizeOf(context).width,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.72,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpace.md,
                    AppSpace.md,
                    AppSpace.md,
                    4,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.bolt, size: 16, color: c.accent),
                      const SizedBox(width: 6),
                      Text(
                        '切换端点与模型',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: c.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),

                // ── 端点段 ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpace.md, 6, AppSpace.md, 2),
                  child: Text(
                    '端点',
                    style: TextStyle(fontSize: 11, color: c.textTertiary),
                  ),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 160),
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
                    children: [
                      for (final ep in cfg.endpoints)
                        _PickRow(
                          label: ep.name,
                          sub: ep.model.isEmpty ? '未选模型' : ep.model,
                          selected: ep.id == _pickedEndpointId,
                          isActive: ep.id == activeId,
                          onTap: () {
                            setState(() {
                              _pickedEndpointId = ep.id;
                              _manual.text = ep.model;
                              _models = const [];
                              _error = null;
                              _manualMode = false;
                            });
                            _fetch(force: false);
                          },
                        ),
                    ],
                  ),
                ),

                Divider(height: 16, color: c.divider),

                // ── 模型段 ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, 2),
                  child: Row(
                    children: [
                      Text(
                        '模型',
                        style: TextStyle(fontSize: 11, color: c.textTertiary),
                      ),
                      const Spacer(),
                      if (_loading)
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: c.accent,
                          ),
                        )
                      else
                        InkWell(
                          onTap: () => _fetch(force: true),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.refresh, size: 12, color: c.accent),
                                const SizedBox(width: 3),
                                Text(
                                  '刷新',
                                  style: TextStyle(fontSize: 11, color: c.accent),
                                ),
                              ],
                            ),
                          ),
                        ),
                      InkWell(
                        onTap: () => setState(() => _manualMode = !_manualMode),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          child: Text(
                            _manualMode ? '从列表选' : '手动输入',
                            style: TextStyle(fontSize: 11, color: c.accent),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                if (_manualMode)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpace.md,
                      4,
                      AppSpace.md,
                      4,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _manual,
                            autocorrect: false,
                            style: const TextStyle(fontSize: 13),
                            decoration: const InputDecoration(
                              isDense: true,
                              hintText: '例如 gpt-4o-mini',
                              hintStyle: TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpace.xs),
                        FilledButton(
                          onPressed: () {
                            final m = _manual.text.trim();
                            if (m.isEmpty) return;
                            _apply(model: m);
                          },
                          child: const Text('确定'),
                        ),
                      ],
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 260),
                    child: _models.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.fromLTRB(
                              AppSpace.md,
                              8,
                              AppSpace.md,
                              12,
                            ),
                            child: Text(
                              _loading ? '正在获取模型列表…' : '（还没有可选的模型）',
                              style: TextStyle(fontSize: 12, color: c.textTertiary),
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpace.md,
                            ),
                            itemCount: _models.length,
                            itemBuilder: (_, i) {
                              final m = _models[i];
                              final selected =
                                  m == (ctrl.activeEndpoint?.model ?? '');
                              return _PickRow(
                                label: m,
                                mono: true,
                                selected: selected,
                                onTap: () => _apply(model: m),
                              );
                            },
                          ),
                  ),

                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpace.md,
                      4,
                      AppSpace.md,
                      8,
                    ),
                    child: Text(
                      _error!,
                      style: TextStyle(fontSize: 11, height: 1.5, color: c.danger),
                    ),
                  ),

                const SizedBox(height: 10),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PickRow extends StatelessWidget {
  const _PickRow({
    required this.label,
    required this.selected,
    required this.onTap,
    this.sub,
    this.isActive = false,
    this.mono = false,
  });

  final String label;
  final String? sub;
  final bool selected;

  /// 是「当前生效的端点」（区别于面板内临时选中）
  final bool isActive;
  final bool mono;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              size: 15,
              color: selected ? c.accent : c.textTertiary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontFamily: mono ? 'monospace' : null,
                      color: selected ? c.accent : c.textPrimary,
                    ),
                  ),
                  if (sub != null)
                    Text(
                      sub!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10, color: c.textTertiary),
                    ),
                ],
              ),
            ),
            if (isActive)
              Container(
                margin: const EdgeInsets.only(left: 6),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: c.accentSoft,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  '当前',
                  style: TextStyle(fontSize: 9, color: c.accent),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
