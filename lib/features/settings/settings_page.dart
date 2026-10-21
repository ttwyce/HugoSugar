import 'package:flutter/material.dart';

import '../../app/theme/accent_presets.dart';
import '../../app/theme/app_colors.dart';
import '../../core/ai/ai_controller.dart';
import '../../core/ai/default_prompt.dart';
import '../../core/settings/app_settings.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/site/site_controller.dart';
import '../../shared/widgets.dart';
import 'author_identity_dialog.dart';
import 'author_suggestion.dart';
import 'memory_page.dart';
import 'token_dialog.dart';
import 'tool_skill_page.dart';

/// 设置页：标准 iOS 风格分组列表。
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.siteController,
    required this.settingsController,
    required this.aiController,
    this.onAccentChanged,
  });

  /// 强调色改完后通知外层重建主题。
  ///
  /// 为什么要上报而不是这里自己 setState：
  /// ThemeData 是 MaterialApp 的属性，只有它重建才能生效。
  final VoidCallback? onAccentChanged;

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final SiteController siteController;
  final SettingsController settingsController;
  final AiController aiController;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _tokenHint = '未设置';

  @override
  void initState() {
    super.initState();
    _refreshToken();
  }

  Future<void> _refreshToken() async {
    final m = await loadTokenMask();
    if (!mounted) return;
    setState(() => _tokenHint = m.hasToken ? '已设置 ${m.masked}' : '未设置');
  }

  Future<void> _editToken(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const TokenDialog(),
    );
    await _refreshToken();
  }

  /// 「提交作者」副标题：显示实际会写进 commit 的值
  String _authorHint() {
    final sc = widget.settingsController;
    final name = sc.authorName;
    final email = sc.authorEmail;
    if (name.isEmpty && email.isEmpty) return '自动（跟随 GitHub 账号）';
    if (email.isEmpty) return '$name · 邮箱自动推断';
    return '${name.isEmpty ? "名称自动" : name} · $email';
  }

  /// 编辑 System Prompt。
  ///
  /// 规格要求「可查看、修改、一键恢复默认」——
  /// 恢复默认的做法是把覆盖值清空（存空串），
  /// 而不是把默认值复制一份存进去。
  Future<void> _editSystemPrompt() async {
    final sc = widget.settingsController;
    final ctrl = TextEditingController(
      text: sc.aiSystemPrompt.trim().isEmpty
          ? kDefaultSystemPrompt
          : sc.aiSystemPrompt,
    );

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('System Prompt'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '决定 AI 的角色、文章规范与行为边界。'
                '「恢复默认」会丢弃你的修改。',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: ctx.appColors.textTertiary,
                ),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 340),
                child: TextField(
                  controller: ctrl,
                  maxLines: null,
                  minLines: 10,
                  style: const TextStyle(fontSize: 13, height: 1.5),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('reset'),
            child: const Text('恢复默认'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );

    _disposeAfterDialog(ctrl);
    if (action == null) return;
    await sc.setAiSystemPrompt(action == 'reset' ? '' : action);
    if (mounted) setState(() {});
  }

  /// 编辑单轮 token 上限
  String _memorySubtitle() {
    final store = widget.aiController.memoryStore;
    final n = store?.all.length ?? 0;
    if (n == 0) return '还没有记忆，AI 会在对话中自动学习';
    return '已记住 $n 条（可查看、修改、删除）';
  }

  Future<void> _openMemory() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MemoryPage(controller: widget.aiController),
      ),
    );
    if (mounted) setState(() {});
  }

  String _toolsSubtitle() {
    final off = widget.settingsController.aiDisabledTools;
    if (off.isEmpty) return '全部工具可用';
    return '已关掉 ${off.length} 个（模型看不到它们）';
  }

  Future<void> _openToolToggles() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ToolTogglesSheet(
        settingsController: widget.settingsController,
        aiController: widget.aiController,
      ),
    );
    if (mounted) setState(() {});
  }

  String _skillsSubtitle() {
    final store = widget.aiController.skillStore;
    final total = store?.all.length ?? 0;
    final active = widget.aiController.skillIds.length;
    if (total == 0) return '尚未加载';
    if (active == 0) return '$total 个可用，当前未启用';
    return '当前启用 $active 个 / 共 $total 个';
  }

  Future<void> _pickAccent() async {
    final current = widget.settingsController.accentPreset;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    await showModalBottomSheet<void>(
      context: context,
      builder: (bctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '强调色',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                '只改强调色，错误红和警告黄保持不变——它们的颜色本身就是语义。',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(bctx).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (var i = 0; i < kAccentPresets.length; i++)
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () async {
                        await widget.settingsController.setAccentPreset(i);
                        widget.onAccentChanged?.call();
                        if (bctx.mounted) Navigator.of(bctx).pop();
                        if (mounted) setState(() {});
                      },
                      child: Column(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: kAccentPresets[i].accent(isDark),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: current == i
                                    ? kAccentPresets[i].accent(isDark)
                                    : Colors.transparent,
                                width: 2,
                              ),
                            ),
                            child: current == i
                                ? const Icon(
                                    Icons.check,
                                    color: Colors.white,
                                    size: 20,
                                  )
                                : null,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            kAccentPresets[i].name,
                            style: const TextStyle(fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openSkills() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SkillsPage(controller: widget.aiController),
      ),
    );
    if (mounted) setState(() {});
  }

  /// 延迟释放一个 TextEditingController。
  ///
  /// 为什么不能在 showDialog 返回后立即 dispose：
  /// showDialog 的 Future 在 pop 那一刻就完成了，但弹窗还在
  /// 播退场动画，里面的 TextField 仍挂在树上并持有这个 controller。
  /// 提前 dispose 会让它在卸载时碰到已销毁的对象，
  /// 在 debug 下直接触发框架断言（InheritedElement._dependents 不为空）。
  /// 等一帧再释放就能避开这个时序。
  void _disposeAfterDialog(TextEditingController c) {
    WidgetsBinding.instance.addPostFrameCallback((_) => c.dispose());
  }

  /// 编辑上下文压缩阈值。
  ///
  /// 两个数字必须一起改：保留条数 >= 阈值时，
  /// ContextCompressor 会判定「要压缩」但保留的比阈值还多，
  /// 压缩完反而更长。所以在一个弹窗里同时收这两个值。
  Future<void> _editCompress() async {
    var threshold = widget.settingsController.aiCompressThreshold;
    var keep = widget.settingsController.aiKeepRecent;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('上下文压缩'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Expanded(child: Text('触发阈值（条）')),
                  SizedBox(
                    width: 64,
                    child: TextField(
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.right,
                      controller: TextEditingController(text: '$threshold'),
                      onChanged: (v) => threshold =
                          (int.tryParse(v) ?? threshold).clamp(4, 200),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Expanded(child: Text('保留最近（条）')),
                  SizedBox(
                    width: 64,
                    child: TextField(
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.right,
                      controller: TextEditingController(text: '$keep'),
                      onChanged: (v) =>
                          keep = (int.tryParse(v) ?? keep).clamp(2, 199),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '超过阈值后，较早的消息会被折叠成摘要，'
                '最近几条原样保留。\n'
                '下限 4 / 上限 200。保留数必须小于阈值。',
                style: TextStyle(
                  fontSize: 11,
                  color: ctx.appColors.textTertiary,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );

    if (ok != true) return;
    await widget.settingsController.setAiCompressThreshold(threshold);
    await widget.settingsController.setAiKeepRecent(keep);
    if (mounted) setState(() {});
  }

  Future<void> _editMaxTokens() async {
    final sc = widget.settingsController;
    final ctrl = TextEditingController(text: '${sc.aiMaxTokensPerRound}');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('单轮 token 上限'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '一次回答里累计超过这个数就中止，防止长对话烧掉大量额度。',
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: ctx.appColors.textTertiary,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
                suffixText: 'tokens',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('保存'),
          ),
        ],
      ),
    );

    // 先读值，再延迟释放 controller。
    final v = ok == true ? int.tryParse(ctrl.text.trim()) : null;
    _disposeAfterDialog(ctrl);
    if (ok != true) return;
    if (v != null) {
      await sc.setAiMaxTokensPerRound(v);
      if (mounted) setState(() {});
    }
  }

  Future<void> _editAuthor() async {
    // 关键：**先把请求发出去，但不 await**，弹窗立刻出现。
    //
    // 早先这里是 `await fetchProfile(...)` 再弹窗，于是用户点「提交作者」
    // 后要干等两个 HTTP 往返（/user + /user/emails，各 20 秒超时）。
    // 而这份数据的唯一用途只是输入框里的灰色占位提示 ——
    // 让一个纯装饰性的提示阻塞交互，是完全本末倒置的。
    final suggestions = _fetchAuthorSuggestions();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AuthorIdentityDialog(
        controller: widget.settingsController,
        suggestions: suggestions,
      ),
    );
    if (mounted) setState(() {});
  }

  /// 查询账号资料，仅用于对话框里的占位提示。
  ///
  /// 实现已抽到 author_suggestion.dart，和「首次登录自动填作者」共用，
  /// 避免两处各写一份、超时配置改了一处忘了另一处。
  Future<AuthorSuggestion?> _fetchAuthorSuggestions() =>
      fetchAuthorSuggestion();

  @override
  Widget build(BuildContext context) {
    // 设置项变化后要立刻反映到这一页（副标题里的当前值），
    // 所以用 AnimatedBuilder 监听控制器，而不是等父级重建。
    return AnimatedBuilder(
      animation: widget.settingsController,
      builder: (context, _) => _buildPage(context),
    );
  }

  Widget _buildPage(BuildContext context) {
    final c = context.appColors;
    final sc = widget.siteController;
    final cfg = sc.config;

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          const SectionHeader('写作'),
          ListTile(
            leading: const Icon(Icons.event_outlined),
            title: const Text('日期格式'),
            subtitle: Text(
              '${widget.settingsController.dateFormat.label} · '
              '${widget.settingsController.dateFormat.sample}',
              style: TextStyle(fontSize: 12, color: c.textTertiary),
            ),
            trailing: const Icon(Icons.chevron_right, size: 18),
            onTap: () => _pickDateFormat(context),
          ),
          const IndentedDivider(),
          ListTile(
            leading: const Icon(Icons.insert_drive_file_outlined),
            title: const Text('新建文件名'),
            subtitle: Text(
              '${widget.settingsController.fileNameStyle.label}'
              '${_fileNameHint(widget.settingsController.fileNameStyle)}',
              style: TextStyle(fontSize: 12, color: c.textTertiary),
            ),
            trailing: const Icon(Icons.chevron_right, size: 18),
            onTap: () => _pickFileNameStyle(context),
          ),

          const SectionHeader('外观'),
          _SegmentedThemeMode(
            value: widget.themeMode,
            onChanged: widget.onThemeModeChanged,
          ),
          const IndentedDivider(),
          ListTile(
            title: const Text('强调色'),
            subtitle: Text(
              accentPresetAt(widget.settingsController.accentPreset).name,
              style: TextStyle(fontSize: 12, color: c.textTertiary),
            ),
            trailing: const Icon(Icons.chevron_right, size: 18),
            onTap: _pickAccent,
          ),
          const IndentedDivider(),
          ListTile(
            title: const Text('正文字体'),
            subtitle: const Text('系统黑体'),
            trailing: const Icon(Icons.chevron_right, size: 18),
            onTap: () {},
          ),
          const IndentedDivider(),
          ListTile(
            title: const Text('正文字号'),
            subtitle: const Text('17'),
            trailing: const Icon(Icons.chevron_right, size: 18),
            onTap: () {},
          ),

          const SectionHeader('站点'),
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: const Text('当前站点'),
            subtitle: Text(
              cfg == null ? '未接入' : '${cfg.displayName} · ${cfg.repoSlug}',
            ),
            trailing: const Icon(Icons.chevron_right, size: 18),
            onTap: () {},
          ),
          const IndentedDivider(),
          ListTile(
            leading: const Icon(Icons.key_outlined),
            title: const Text('GitHub 访问令牌'),
            subtitle: Text(
              _tokenHint,
              style: TextStyle(fontSize: 12, color: c.textTertiary),
            ),
            trailing: const Icon(Icons.chevron_right, size: 18),
            onTap: () => _editToken(context),
          ),
          const IndentedDivider(),
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: const Text('提交作者'),
            subtitle: Text(
              _authorHint(),
              style: TextStyle(fontSize: 12, color: c.textTertiary),
            ),
            trailing: const Icon(Icons.chevron_right, size: 18),
            onTap: _editAuthor,
          ),

          const SectionHeader('AI'),
          // 隐私相关的总开关，默认关闭。
          // 想法是私人草稿区，没经过用户明确同意不该被送进第三方模型。
          SwitchListTile(
            value: widget.settingsController.aiReadNotes,
            onChanged: (v) async {
              await widget.settingsController.setAiReadNotes(enabled: v);
              if (mounted) setState(() {});
            },
            secondary: const Icon(Icons.lightbulb_outline),
            title: const Text('允许 AI 读取想法'),
            subtitle: Text(
              widget.settingsController.aiReadNotes
                  ? '开启后 AI 可以读到你的想法'
                  : '关闭时 AI 看不到任何想法（在对话里指定分组或想法除外）',
              style: TextStyle(fontSize: 12, color: c.textTertiary),
            ),
          ),
          if (widget.settingsController.aiReadNotes)
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const Text('允许读取的分组'),
              subtitle: Text(
                widget.settingsController.aiNoteCategoryIds.isEmpty
                    ? '全部（可在「想法」页的 AI 菜单里指定分组）'
                    : '已选 ${widget.settingsController.aiNoteCategoryIds.length} 个',
                style: TextStyle(fontSize: 12, color: c.textTertiary),
              ),
              // 分组选择需要 NoteStore，而设置页拿不到它。
              // 与其为了一个开关把 NoteController 一路传进设置页，
              // 不如把入口放在「想法」页 —— 那里本来就有分类数据和上下文。
              trailing: Text(
                '在想法页设置',
                style: TextStyle(fontSize: 12, color: c.textTertiary),
              ),
            ),
          const IndentedDivider(),
          ListTile(
            leading: const Icon(Icons.api),
            title: const Text('API 配置'),
            subtitle: const Text('未配置'),
            trailing: const Icon(Icons.chevron_right, size: 18),
            onTap: () {},
          ),
          const IndentedDivider(),
          ListTile(
            leading: const Icon(Icons.tune),
            title: const Text('System Prompt'),
            subtitle: Text(
              widget.settingsController.aiSystemPrompt.trim().isEmpty
                  ? '使用默认模板'
                  : '已自定义（${widget.settingsController.aiSystemPrompt.length} 字）',
              style: TextStyle(fontSize: 12, color: c.textTertiary),
            ),
            trailing: const Icon(Icons.chevron_right, size: 18),
            onTap: _editSystemPrompt,
          ),
          const IndentedDivider(),
          ListTile(
            leading: const Icon(Icons.psychology_outlined),
            title: const Text('记忆库'),
            subtitle: Text(
              _memorySubtitle(),
              style: TextStyle(fontSize: 12, color: c.textTertiary),
            ),
            trailing: const Icon(Icons.chevron_right, size: 18),
            onTap: _openMemory,
          ),
          const IndentedDivider(),
          ListTile(
            leading: const Icon(Icons.compress),
            title: const Text('上下文压缩'),
            subtitle: Text(
              '超过 ${widget.settingsController.aiCompressThreshold} 条开始折叠，'
              '保留最近 ${widget.settingsController.aiKeepRecent} 条',
              style: TextStyle(fontSize: 12, color: c.textTertiary),
            ),
            trailing: const Icon(Icons.chevron_right, size: 18),
            onTap: _editCompress,
          ),
          const IndentedDivider(),
          ListTile(
            leading: const Icon(Icons.speed),
            title: const Text('单轮 token 上限'),
            subtitle: Text(
              '${widget.settingsController.aiMaxTokensPerRound}'
              '（超过即中止本轮）',
              style: TextStyle(fontSize: 12, color: c.textTertiary),
            ),
            trailing: const Icon(Icons.chevron_right, size: 18),
            onTap: _editMaxTokens,
          ),

          const IndentedDivider(),
          ListTile(
            leading: const Icon(Icons.handyman_outlined),
            title: const Text('工具开关'),
            subtitle: Text(
              _toolsSubtitle(),
              style: TextStyle(fontSize: 12, color: c.textTertiary),
            ),
            trailing: const Icon(Icons.chevron_right, size: 18),
            onTap: _openToolToggles,
          ),
          const IndentedDivider(),
          ListTile(
            leading: const Icon(Icons.auto_fix_high),
            title: const Text('Skill / 工作模式'),
            subtitle: Text(
              _skillsSubtitle(),
              style: TextStyle(fontSize: 12, color: c.textTertiary),
            ),
            trailing: const Icon(Icons.chevron_right, size: 18),
            onTap: _openSkills,
          ),

          const SectionHeader('关于'),
          ListTile(
            title: const Text('版本'),
            subtitle: const Text('0.1.0 (M1)'),
            trailing: Text(
              '检查更新',
              style: TextStyle(fontSize: 13, color: c.accent),
            ),
            onTap: () {},
          ),

          // 「开发者」分组下的 Git 冒烟测试页已在 M1 移除：
          // M0 验证通过，git 能力已沉淀到 core/site/git_service.dart。
        ],
      ),
    );
  }

  String _fileNameHint(FileNameStyle s) => switch (s) {
    FileNameStyle.fromTitle => '（如 hello-world.md）',
    FileNameStyle.timestamp => '（如 post-20240501-080309.md）',
    FileNameStyle.dateAndTitle => '（如 20240501-hello-world.md）',
  };

  void _pickDateFormat(BuildContext context) {
    _showChoiceSheet<DateFormatStyle>(
      context: context,
      title: '日期格式',
      note:
          '写入 Front Matter 的 date 字段。Hugo 三种都能解析，'
          '但如果主题或时间线功能要求严格 ISO8601，选带时区那种。',
      values: DateFormatStyle.values,
      current: widget.settingsController.dateFormat,
      labelOf: (v) => v.label,
      sampleOf: (v) => v.sample,
      onPick: (v) => widget.settingsController.setDateFormat(v),
    );
  }

  void _pickFileNameStyle(BuildContext context) {
    _showChoiceSheet<FileNameStyle>(
      context: context,
      title: '新建文件名',
      note:
          '只影响以后新建的文章，已存在的文件不会改名。'
          '同名时自动加 -2、-3 后缀，绝不覆盖。',
      values: FileNameStyle.values,
      current: widget.settingsController.fileNameStyle,
      labelOf: (v) => v.label,
      sampleOf: (v) => _fileNameHint(v),
      onPick: (v) => widget.settingsController.setFileNameStyle(v),
    );
  }

  void _showChoiceSheet<T>({
    required BuildContext context,
    required String title,
    required String note,
    required List<T> values,
    required T current,
    required String Function(T) labelOf,
    required String Function(T) sampleOf,
    required ValueChanged<T> onPick,
  }) {
    final c = context.appColors;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.md,
                AppSpace.sm,
                AppSpace.md,
                4,
              ),
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: c.textPrimary,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.md,
                0,
                AppSpace.md,
                AppSpace.xs,
              ),
              child: Text(
                note,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.55,
                  color: c.textTertiary,
                ),
              ),
            ),
            for (final v in values)
              ListTile(
                title: Text(labelOf(v)),
                subtitle: Text(
                  sampleOf(v),
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    fontFamily: 'monospace',
                    color: c.textTertiary,
                  ),
                ),
                trailing: v == current
                    ? Icon(Icons.check, size: 18, color: c.accent)
                    : null,
                onTap: () {
                  Navigator.pop(ctx);
                  onPick(v);
                },
              ),
            const SizedBox(height: AppSpace.xs),
          ],
        ),
      ),
    );
  }
}

/// 主题模式：跟随系统 / 亮色 / 暗色
class _SegmentedThemeMode extends StatelessWidget {
  const _SegmentedThemeMode({required this.value, required this.onChanged});

  final ThemeMode value;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.md,
        vertical: AppSpace.xs,
      ),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          children: [
            _item(context, ThemeMode.system, '跟随系统'),
            _item(context, ThemeMode.light, '亮色'),
            _item(context, ThemeMode.dark, '暗色'),
          ],
        ),
      ),
    );
  }

  Widget _item(BuildContext context, ThemeMode mode, String label) {
    final c = context.appColors;
    final selected = mode == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(mode),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? c.background : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 6,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              height: 1.3,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? c.textPrimary : c.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
