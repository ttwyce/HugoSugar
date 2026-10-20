import 'package:flutter/material.dart';

import '../app/theme/app_colors.dart';

/// 空状态：图标 + 一行说明，不用插画（见设计规范 §4）
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: c.textTertiary),
          const SizedBox(height: AppSpace.sm),
          Text(
            text,
            style: TextStyle(fontSize: 14, height: 1.5, color: c.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// 小节标题，例如「置顶 · 3」
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.md,
        AppSpace.lg,
        AppSpace.md,
        AppSpace.xs,
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          height: 1.4,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.6,
          color: context.appColors.textTertiary,
        ),
      ),
    );
  }
}

/// 列表分割线：左边缩进 16，不顶到屏幕边
class IndentedDivider extends StatelessWidget {
  const IndentedDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      indent: AppSpace.md,
      color: context.appColors.divider,
    );
  }
}

/// 小标签，例如 tags / draft
class MiniTag extends StatelessWidget {
  const MiniTag(this.text, {super.key, this.emphasized = false});

  final String text;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: 2),
      decoration: BoxDecoration(
        color: emphasized ? c.accentSoft : c.surface,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          height: 1.4,
          fontWeight: FontWeight.w500,
          color: emphasized ? c.accent : c.textSecondary,
        ),
      ),
    );
  }
}