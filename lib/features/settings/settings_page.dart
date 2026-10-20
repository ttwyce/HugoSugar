import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../core/site/site_controller.dart';
import '../../shared/widgets.dart';

/// 设置页：标准 iOS 风格分组列表。
class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.siteController,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final SiteController siteController;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final sc = siteController;
    final cfg = sc.config;

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          const SectionHeader('外观'),
          _SegmentedThemeMode(
            value: themeMode,
            onChanged: onThemeModeChanged,
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
            subtitle: const Text('在接入站点时填写'),
            trailing: const Icon(Icons.chevron_right, size: 18),
            onTap: () {},
          ),

          const SectionHeader('AI'),
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
            subtitle: const Text('使用默认模板'),
            trailing: const Icon(Icons.chevron_right, size: 18),
            onTap: () {},
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