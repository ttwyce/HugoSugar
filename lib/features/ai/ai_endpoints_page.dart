import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/ai/ai_client.dart';
import '../../../core/ai/ai_controller.dart';
import '../../../core/ai/ai_endpoint.dart';

/// AI 端点管理页：增删改 + 拉模型列表。
///
/// 支持多个端点是核心需求 —— 用户可能在便宜的小模型和强模型之间切换，
/// 或者国内直连一个、备用一个。
class AiEndpointsPage extends StatefulWidget {
  const AiEndpointsPage({super.key, required this.controller});

  final AiController controller;

  @override
  State<AiEndpointsPage> createState() => _AiEndpointsPageState();
}

class _AiEndpointsPageState extends State<AiEndpointsPage> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final cfg = widget.controller.config;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 端点'),
        actions: [
          IconButton(
            tooltip: '添加',
            onPressed: _add,
            icon: const Icon(Icons.add),
          ),
          const SizedBox(width: AppSpace.xs),
        ],
      ),
      body: cfg.endpoints.isEmpty
          ? _EmptyHint(onAdd: _add)
          : ListView.separated(
              padding: const EdgeInsets.all(AppSpace.md),
              itemCount: cfg.endpoints.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpace.sm),
              itemBuilder: (_, i) {
                final ep = cfg.endpoints[i];
                return _EndpointCard(
                  endpoint: ep,
                  active: ep.id == cfg.activeId,
                  // 点卡片 = 切换。这是最符合直觉的动作：
                  // 列表页上点一行，就是把这一行「选中」。
                  // 编辑挪到右侧菜单，避免「只想切换却打开了编辑面板」。
                  onTap: () => widget.controller.setActiveEndpoint(ep.id),
                  onEdit: () => _edit(ep),
                  onDelete: () => _confirmDelete(ep),
                );
              },
            ),
      bottomNavigationBar: cfg.endpoints.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.md),
                child: Text(
                  '当前使用：${cfg.active?.name ?? '-'}',
                  style: TextStyle(fontSize: 12, color: c.textTertiary),
                ),
              ),
            ),
    );
  }

  Future<void> _add() async {
    final ok = await _showEditor(null);
    if (ok && mounted) setState(() {});
  }

  Future<void> _edit(AiEndpoint ep) async {
    final ok = await _showEditor(ep);
    if (ok && mounted) setState(() {});
  }

  Future<bool> _showEditor(AiEndpoint? existing) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          _EndpointEditor(controller: widget.controller, existing: existing),
    );
    return result == true;
  }

  Future<void> _confirmDelete(AiEndpoint ep) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除端点'),
        content: Text('删除「${ep.name}」？它的 API Key 也会一起删掉。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: context.appColors.danger,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await widget.controller.removeEndpoint(ep.id);
      if (mounted) setState(() {});
    }
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.smart_toy_outlined, size: 44, color: c.textTertiary),
            const SizedBox(height: AppSpace.md),
            Text(
              '还没有配置 AI 端点',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpace.xs),
            Text(
              '填一个兼容 OpenAI 协议的地址就能用。\n'
              'OpenAI、DeepSeek、各家中转站、本地 Ollama 都支持。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.6,
                color: c.textTertiary,
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            FilledButton(onPressed: onAdd, child: const Text('添加端点')),
          ],
        ),
      ),
    );
  }
}

class _EndpointCard extends StatelessWidget {
  const _EndpointCard({
    required this.endpoint,
    required this.active,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final AiEndpoint endpoint;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Material(
      // 当前项用浅强调色底 + 边框，让「哪一行是选中的」一眼可见；
      // 之前只有一个小勾，滚动时很容易忽略。
      color: active ? c.accentSoft : c.surface,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: active ? c.accent.withValues(alpha: 0.5) : c.divider,
              width: 1,
            ),
          ),
          padding: const EdgeInsets.all(AppSpace.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (active)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Icon(
                        Icons.check_circle,
                        size: 15,
                        color: c.accent,
                      ),
                    ),
                  Expanded(
                    child: Text(
                      endpoint.name,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: Icon(
                      Icons.more_horiz,
                      size: 18,
                      color: c.textTertiary,
                    ),
                    onSelected: (v) {
                      if (v == 'edit') onEdit();
                      if (v == 'delete') onDelete();
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'edit',
                        child: Text('编辑（地址 / Key / 模型）'),
                      ),
                      PopupMenuItem(value: 'delete', child: Text('删除')),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                endpoint.baseUrl,
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: c.textTertiary,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.tune, size: 12, color: c.textTertiary),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      endpoint.model.isEmpty ? '未选择模型' : endpoint.model,
                      style: TextStyle(fontSize: 11, color: c.textSecondary),
                    ),
                  ),
                  if (endpoint.keyHint.isNotEmpty) ...[
                    Icon(Icons.key, size: 12, color: c.textTertiary),
                    const SizedBox(width: 4),
                    Text(
                      endpoint.keyHint,
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: c.textTertiary,
                      ),
                    ),
                  ] else
                    Text(
                      '未填 Key',
                      style: TextStyle(fontSize: 11, color: c.danger),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 添加 / 编辑端点
class _EndpointEditor extends StatefulWidget {
  const _EndpointEditor({required this.controller, this.existing});

  final AiController controller;
  final AiEndpoint? existing;

  @override
  State<_EndpointEditor> createState() => _EndpointEditorState();
}

class _EndpointEditorState extends State<_EndpointEditor> {
  late final TextEditingController _name;
  late final TextEditingController _baseUrl;
  late final TextEditingController _key;
  late final TextEditingController _model;

  bool _obscure = true;
  bool _busy = false;
  bool _loadingModels = false;
  String? _error;

  List<AiModel> _models = const [];

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _baseUrl = TextEditingController(text: e?.baseUrl ?? '');
    _model = TextEditingController(text: e?.model ?? '');
    _key = TextEditingController();
  }

  @override
  void dispose() {
    _name.dispose();
    _baseUrl.dispose();
    _key.dispose();
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final chatModels = _models.where((m) => m.looksChatCapable).toList();

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        // 必须给一个**明确有限的宽度**。
        //
        // 根因：showModalBottomSheet + isScrollControlled 的 builder
        // 拿到的横向约束是**无界**的（w=Infinity）。于是 Column 的
        // 子项按固有宽度布局，Row 里的 Expanded / OutlinedButton
        // 收到 BoxConstraints(w=Infinity)，布局阶段直接抛
        // 「BoxConstraints forces an infinite width」。
        //
        // 症状就是用户看到的：遮罩出现，内容一片空白 ——
        // 因为渲染在布局阶段就中断了。
        //
        // 注意不能写 maxWidth: double.infinity —— 那仍然是无界，
        // 等于没约束。必须取屏幕实际宽度。
        child: SizedBox(
          width: MediaQuery.sizeOf(context).width,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpace.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isEdit ? '编辑端点' : '添加端点',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSpace.md),

                TextField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: '名称',
                    helperText: '随便起，比如「DeepSeek」「备用」',
                  ),
                ),
                const SizedBox(height: AppSpace.sm),

                TextField(
                  controller: _baseUrl,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: '接口地址',
                    hintText: 'https://api.openai.com/v1',
                    helperText: '填到 /v1 就行，不用写 /chat/completions',
                    helperMaxLines: 2,
                  ),
                ),
                const SizedBox(height: AppSpace.sm),

                TextField(
                  controller: _key,
                  obscureText: _obscure,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: 'API Key',
                    hintText: _isEdit ? '留空则不修改' : 'sk-...',
                    helperText: _isEdit && widget.existing!.keyHint.isNotEmpty
                        ? '已保存：${widget.existing!.keyHint}'
                        : '存在应用私有目录，权限 0600',
                    helperMaxLines: 2,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 18,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpace.sm),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _model,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: '模型',
                          hintText: 'gpt-4o-mini',
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpace.xs),
                    // 按钮不能用 Expanded（会和输入框抢宽度），
                    // 但必须给一个**有限**的宽度约束 —— 否则它在
                    // 无界环境里会被要求撑到 Infinity。
                    SizedBox(
                      width: 92,
                      height: 48,
                      child: OutlinedButton(
                        onPressed: _loadingModels ? null : _loadModels,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                        ),
                        child: Text(
                          _loadingModels ? '获取中' : '获取列表',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: AppSpace.xs),
                // 思考方式不在这里配。
                //
                // 原因：「要不要思考」是业务意图（人对话里选），
                // 「用 enable_thinking 还是 reasoning_effort」是实现细节（App 自己猜）。
                // 把后者摆到用户面前，等于要他背各家 API 的差异。
                // 猜错了也不会报错：服务端说不认这个字段时
                // 会自动去掉重发一次（见 AiClient._isUnsupportedParam）。
                Padding(
                  padding: const EdgeInsets.only(top: 2, left: 2, bottom: 2),
                  child: Row(
                    children: [
                      Icon(Icons.auto_awesome, size: 12, color: c.textTertiary),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '思考深度在对话页选，这里不用管',
                          style: TextStyle(fontSize: 11, color: c.textTertiary),
                        ),
                      ),
                    ],
                  ),
                ),
                if (chatModels.isNotEmpty) ...[
                  const SizedBox(height: AppSpace.sm),
                  Text(
                    '点选模型（已过滤掉 embedding/tts 等不能对话的）',
                    style: TextStyle(fontSize: 11, color: c.textTertiary),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 180),
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: chatModels.length,
                      itemBuilder: (_, i) {
                        final m = chatModels[i];
                        final selected = m.id == _model.text.trim();
                        return InkWell(
                          onTap: () => setState(() => _model.text = m.id),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 9,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  selected
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_unchecked,
                                  size: 15,
                                  color: selected ? c.accent : c.textTertiary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    m.id,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontFamily: 'monospace',
                                      color: selected
                                          ? c.accent
                                          : c.textPrimary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],

                if (_error != null) ...[
                  const SizedBox(height: AppSpace.sm),
                  Text(
                    _error!,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: c.danger,
                    ),
                  ),
                ],

                const SizedBox(height: AppSpace.lg),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () => Navigator.of(context).pop(false),
                        child: const Text('取消'),
                      ),
                    ),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: FilledButton(
                        onPressed: _busy ? null : _save,
                        child: Text(_busy ? '保存中…' : '保存'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _loadModels() async {
    final base = _baseUrl.text.trim();
    if (base.isEmpty) {
      setState(() => _error = '先填接口地址');
      return;
    }

    setState(() {
      _loadingModels = true;
      _error = null;
    });

    try {
      // 用「刚填的 key」优先，其次用已保存的。
      // 用户常常是先填 key 再点获取，此时还没保存。
      final typedKey = _key.text.trim();
      final ep = AiEndpoint(
        id: widget.existing?.id ?? 'tmp',
        name: _name.text,
        baseUrl: base,
        model: _model.text,
      );
      final models = await widget.controller.fetchModels(
        endpoint: ep,
        apiKey: typedKey.isEmpty ? null : typedKey,
      );
      if (!mounted) return;
      setState(() {
        _models = models;
        _loadingModels = false;
        if (models.isEmpty) {
          _error = '这个端点没有返回任何模型，可以直接手填模型名';
        }
      });
    } on AiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingModels = false;
        // 拿不到列表不算致命：允许手填模型名
        _error = '${e.message}\n${e.hint ?? "可以直接手动填写模型名"}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingModels = false;
        _error = '$e';
      });
    }
  }

  /// 当前思考模式的说明。写清楚「会不会真的思考」，
  /// 因为选错的表现是「开关开了但什么都没有」，很容易被当成 bug。
  /// 协议的说明。

  Future<void> _save() async {
    final base = _baseUrl.text.trim();
    if (base.isEmpty) {
      setState(() => _error = '请填写接口地址');
      return;
    }
    if (!base.startsWith('http://') && !base.startsWith('https://')) {
      setState(() => _error = '接口地址要以 http:// 或 https:// 开头');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final name = _name.text.trim();
    final finalName = name.isEmpty ? Uri.parse(base).host : name;

    if (_isEdit) {
      final updated = widget.existing!.copyWith(
        name: finalName,
        baseUrl: base,
        model: _model.text.trim(),
        // 保留用户旧配置；不在 UI 暴露，但也不抹掉
        thinkingProtocol:
            widget.existing?.thinkingProtocol ?? ThinkingProtocol.off,
      );
      await widget.controller.updateEndpoint(
        updated,
        apiKey: _key.text.trim().isEmpty ? null : _key.text.trim(),
      );
    } else {
      await widget.controller.addEndpoint(
        name: finalName,
        baseUrl: base,
        model: _model.text.trim(),
        apiKey: _key.text.trim(),
        thinkingProtocol:
            widget.existing?.thinkingProtocol ?? ThinkingProtocol.off,
      );
    }

    if (mounted) Navigator.of(context).pop(true);
  }
}
