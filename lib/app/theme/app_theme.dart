import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import 'app_colors.dart';

/// 排版规范。编辑器正文单独暴露，因为它是「阅读偏好」可调的。
abstract final class AppTypography {
  /// 列表标题
  static const listTitle = TextStyle(
    fontSize: 16,
    height: 1.4,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
  );

  /// 列表摘要 / 时间 / 说明
  static const listSubtitle = TextStyle(
    fontSize: 13,
    height: 1.5,
    fontWeight: FontWeight.w400,
  );

  /// 小节标题（如「置顶 · 3」）
  static const sectionLabel = TextStyle(
    fontSize: 12,
    height: 1.4,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.6,
  );

  /// 页面大标题（如「文章」）
  static const pageTitle = TextStyle(
    fontSize: 28,
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
  );

  /// 编辑器里的标题
  static const editorTitle = TextStyle(
    fontSize: 22,
    height: 1.4,
    fontWeight: FontWeight.w600,
  );

  /// 编辑器正文 —— 行高 1.75 是重点，中文长文最舒服的值
  static const editorBody = TextStyle(
    fontSize: 17,
    height: 1.75,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.2,
  );

  /// 预览正文
  static const previewBody = TextStyle(
    fontSize: 16.5,
    height: 1.8,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.2,
  );

  /// 按钮
  static const button = TextStyle(
    fontSize: 15,
    height: 1.2,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.3,
  );

  /// 构造 TextTheme（Material 组件会用到其中的字段）
  static TextTheme textTheme(Color primary) => TextTheme(
        bodyLarge: listTitle.copyWith(color: primary),
        bodyMedium: listSubtitle.copyWith(color: primary),
        bodySmall: listSubtitle.copyWith(color: primary),
        titleLarge: pageTitle.copyWith(color: primary),
        titleMedium: listTitle.copyWith(color: primary),
        labelLarge: button.copyWith(color: primary),
      );
}

/// 主题构建。亮暗两套都基于同一套 token，只换颜色。
abstract final class AppTheme {
  static ThemeData light() => _build(AppColors.light, Brightness.light);
  static ThemeData dark() => _build(AppColors.dark, Brightness.dark);

  static ThemeData _build(AppColors c, Brightness brightness) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.accent,
      onPrimary: brightness == Brightness.light ? Colors.white : c.background,
      secondary: c.accent,
      onSecondary: c.background,
      error: c.danger,
      onError: Colors.white,
      surface: c.background,
      onSurface: c.textPrimary,
      surfaceContainerHighest: c.surface,
      outline: c.divider,
      outlineVariant: c.divider,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.background,
      canvasColor: c.background,
      dividerColor: c.divider,
      splashFactory: InkSparkle.splashFactory,
      extensions: <ThemeExtension<dynamic>>[c],
      textTheme: AppTypography.textTheme(c.textPrimary),

      // AppBar：无阴影、无痕，只留标题
      appBarTheme: AppBarTheme(
        backgroundColor: c.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: c.textPrimary, size: 22),
        titleTextStyle: AppTypography.pageTitle.copyWith(color: c.textPrimary),
      ),

      // 底部导航：无阴影，只有一条 1px 分割线
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 56,
        indicatorColor: Colors.transparent,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11,
            height: 1.3,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? c.accent : c.textTertiary,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 22,
            color: selected ? c.accent : c.textTertiary,
          );
        }),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: c.accent,
        foregroundColor: brightness == Brightness.light ? Colors.white : c.background,
        elevation: 2,
        highlightElevation: 2,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.md)),
        ),
      ),

      // 输入框：无边框、靠底色分层
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surface,
        hintStyle: AppTypography.listSubtitle.copyWith(color: c.textTertiary),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: c.accent, width: 1.5),
        ),
      ),

      // 主按钮：全宽 48 高
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          backgroundColor: c.accent,
          foregroundColor: brightness == Brightness.light ? Colors.white : c.background,
          elevation: 0,
          textStyle: AppTypography.button,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
      ),

      // 次按钮：描边
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          foregroundColor: c.accent,
          side: BorderSide(color: c.accent, width: 1),
          textStyle: AppTypography.button,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.accent,
          textStyle: AppTypography.button,
        ),
      ),

      // 底部面板：顶部圆角
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        showDragHandle: true,
        dragHandleColor: c.divider,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: c.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.surfaceHigh,
        contentTextStyle: AppTypography.listSubtitle.copyWith(color: c.textPrimary),
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),

      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
        iconColor: c.textSecondary,
        titleTextStyle: AppTypography.listTitle.copyWith(color: c.textPrimary),
        subtitleTextStyle:
            AppTypography.listSubtitle.copyWith(color: c.textSecondary),
      ),

      dividerTheme: DividerThemeData(
        color: c.divider,
        thickness: 1,
        space: 1,
      ),

      /// Chip 统一走「浅色底 + 深色字」，与筛选栏的 `_Chip` 视觉一致。
      ///
      /// 之前只设了 backgroundColor，没管 labelStyle 的颜色，
      /// InputChip 会去取 ColorScheme 的次级容器色（深墨绿）配对默认前景色，
      /// 结果就是「绿底白字」，在亮色主题下几乎看不清。
      chipTheme: ChipThemeData(
        backgroundColor: c.accentSoft,
        // 明确指定前景色，不让 Material 去猜
        labelStyle: TextStyle(
          fontSize: 12,
          height: 1.2,
          fontWeight: FontWeight.w500,
          color: c.accent,
        ),
        secondaryLabelStyle: TextStyle(
          fontSize: 12,
          height: 1.2,
          color: c.accent,
        ),
        secondarySelectedColor: c.accentSoft,
        selectedColor: c.accentSoft,
        disabledColor: c.surface,
        deleteIconColor: c.accent.withValues(alpha: 0.7),
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.xs,
          vertical: 2,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
      ),

      // 页面切换动画统一，避免默认的从下往上
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}