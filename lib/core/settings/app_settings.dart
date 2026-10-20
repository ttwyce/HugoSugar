import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Hugo 写入 Front Matter 时的日期格式。
///
/// 这不是「显示格式」，而是**写进文件里的字面量**。
/// Hugo 对以下几种都能解析，但不同主题/工具链对带时区的 ISO8601 更友好。
enum DateFormatStyle {
  /// 2024-05-01 08:03:09
  space('空格分隔', '2024-05-01 08:03:09'),

  /// 2024-05-01T08:03:09+08:00
  iso('ISO8601 带时区', '2024-05-01T08:03:09+08:00'),

  /// 2024-05-01
  dateOnly('仅日期', '2024-05-01');

  const DateFormatStyle(this.label, this.sample);

  final String label;

  /// 设置页里的预览示例
  final String sample;

  String get id => name;

  static DateFormatStyle fromId(String? id) {
    for (final v in values) {
      if (v.name == id) return v;
    }
    return DateFormatStyle.iso;
  }
}

/// 新建文章时的文件名规则。
enum FileNameStyle {
  /// 与标题一致：把标题转成 slug（中文标题用时间戳兜底）
  fromTitle('跟随标题（推荐）'),
  /// 固定用时间戳：post-20240501-080309
  timestamp('时间戳'),
  /// 日期 + 标题 slug：20240501-hello
  dateAndTitle('日期 + 标题');

  const FileNameStyle(this.label);

  final String label;

  String get id => name;

  static FileNameStyle fromId(String? id) {
    for (final v in values) {
      if (v.name == id) return v;
    }
    return FileNameStyle.fromTitle;
  }
}

/// 本地偏好设置（不是站点配置）。
///
/// 存储位置：应用私有目录 `settings.json`。
/// 之所以单独一个文件而不是塞进站点配置：这些设置**跨站点共享**，
/// 换一个仓库写文章时，日期格式和命名习惯不应该跟着变。
class AppSettings {
  const AppSettings({
    this.dateFormat = DateFormatStyle.iso,
    this.fileNameStyle = FileNameStyle.fromTitle,
    this.authorName = '',
    this.authorEmail = '',
    this.aiReadNotes = false,
    this.aiNoteCategoryIds = const [],
  });

  final DateFormatStyle dateFormat;
  final FileNameStyle fileNameStyle;

  /// git 提交作者名。空串表示「用令牌对应的 GitHub 登录名」。
  ///
  /// 留空是合理默认：多数人希望提交显示为自己的 GitHub 账号。
  final String authorName;

  /// git 提交作者邮箱。空串表示「自动推断」。
  ///
  /// **为什么需要手填**：自动推断只能拿到 GitHub 的公开邮箱或
  /// noreply 地址，而用户很可能希望提交指向自己的真实邮箱。
  /// GitHub 靠邮箱把提交关联到账号，所以这个值填错会导致
  /// 贡献格子不亮，必须允许用户自己定。
  ///
  /// 注意：**不要在代码里硬编码任何真实邮箱**，否则会随仓库公开。
  /// 这里只存用户自己填的值。
  final String authorEmail;

  /// AI 是否可以读取想法。
  ///
  /// **默认关闭**。想法是私人草稿区，用户没明确打开之前，
  /// 不应该有任何内容被送进第三方模型。这是一个需要主动授予的权限，
  /// 而不是一个默认享受的便利。
  ///
  /// 注意：即使关闭，用户**明确指定**某个分组或某条想法时，
  /// 仍然会读取被指定的部分 —— 明确的单次指令优先于全局开关。
  /// 这个例外由 NoteContextBuilder 处理，不在这里。
  final bool aiReadNotes;

  /// AI 允许读取的分组 id。
  ///
  /// 空列表 = 不限制分组（读全部）。
  /// 非空时，即使 [aiReadNotes] 为 false，也会读取这些分组里的想法，
  /// 因为用户主动勾选了它们，意图是明确的。
  final List<String> aiNoteCategoryIds;

  AppSettings copyWith({
    DateFormatStyle? dateFormat,
    FileNameStyle? fileNameStyle,
    String? authorName,
    String? authorEmail,
    bool? aiReadNotes,
    List<String>? aiNoteCategoryIds,
  }) {
    return AppSettings(
      dateFormat: dateFormat ?? this.dateFormat,
      fileNameStyle: fileNameStyle ?? this.fileNameStyle,
      authorName: authorName ?? this.authorName,
      authorEmail: authorEmail ?? this.authorEmail,
      aiReadNotes: aiReadNotes ?? this.aiReadNotes,
      aiNoteCategoryIds: aiNoteCategoryIds ?? this.aiNoteCategoryIds,
    );
  }

  Map<String, Object?> toJson() => {
        'dateFormat': dateFormat.id,
        'fileNameStyle': fileNameStyle.id,
        'authorName': authorName,
        'authorEmail': authorEmail,
        'aiReadNotes': aiReadNotes,
        'aiNoteCategoryIds': aiNoteCategoryIds,
      };

  static AppSettings fromJson(Map<String, Object?> j) => AppSettings(
        dateFormat: DateFormatStyle.fromId(j['dateFormat'] as String?),
        fileNameStyle: FileNameStyle.fromId(j['fileNameStyle'] as String?),
        authorName: j['authorName'] as String? ?? '',
        authorEmail: j['authorEmail'] as String? ?? '',
        aiReadNotes: j['aiReadNotes'] as bool? ?? false,
        aiNoteCategoryIds:
            (j['aiNoteCategoryIds'] as List?)?.cast<String>() ?? const [],
      );
}

/// 只读的偏好设置视图。
///
/// 定义在这里而不是 settings_controller.dart，是为了让 core/site 只依赖
/// 「取值能力」而不依赖具体实现，避免两个控制器互相 import。
abstract class SettingsControllerLike {
  DateFormatStyle get dateFormat;
  FileNameStyle get fileNameStyle;
  String get authorName;
  String get authorEmail;
  bool get aiReadNotes;
  List<String> get aiNoteCategoryIds;
}

/// 读写 `settings.json`。
///
/// 读失败一律回落到默认值 —— 设置文件损坏不该让 App 打不开，
/// 大不了恢复成默认格式，用户再改一次即可。
class SettingsStore {
  SettingsStore(this.file);

  final File file;

  static Future<SettingsStore> open() async {
    final dir = await getApplicationSupportDirectory();
    return SettingsStore(File('${dir.path}/settings.json'));
  }

  Future<AppSettings> load() async {
    try {
      if (!await file.exists()) return const AppSettings();
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return const AppSettings();
      final j = jsonDecode(raw);
      if (j is! Map) return const AppSettings();
      return AppSettings.fromJson(Map<String, Object?>.from(j));
    } catch (_) {
      return const AppSettings();
    }
  }

  Future<void> save(AppSettings s) async {
    try {
      await file.parent.create(recursive: true);
      // 先写临时文件再 rename，避免写一半被杀导致文件损坏
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(jsonEncode(s.toJson()), flush: true);
      await tmp.rename(file.path);
    } catch (_) {
      // 设置写失败不致命，下次再写
    }
  }
}