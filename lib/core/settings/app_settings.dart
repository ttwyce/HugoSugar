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
  });

  final DateFormatStyle dateFormat;
  final FileNameStyle fileNameStyle;

  AppSettings copyWith({
    DateFormatStyle? dateFormat,
    FileNameStyle? fileNameStyle,
  }) {
    return AppSettings(
      dateFormat: dateFormat ?? this.dateFormat,
      fileNameStyle: fileNameStyle ?? this.fileNameStyle,
    );
  }

  Map<String, Object?> toJson() => {
        'dateFormat': dateFormat.id,
        'fileNameStyle': fileNameStyle.id,
      };

  static AppSettings fromJson(Map<String, Object?> j) => AppSettings(
        dateFormat: DateFormatStyle.fromId(j['dateFormat'] as String?),
        fileNameStyle: FileNameStyle.fromId(j['fileNameStyle'] as String?),
      );
}

/// 只读的偏好设置视图。
///
/// 定义在这里而不是 settings_controller.dart，是为了让 core/site 只依赖
/// 「取值能力」而不依赖具体实现，避免两个控制器互相 import。
abstract class SettingsControllerLike {
  DateFormatStyle get dateFormat;
  FileNameStyle get fileNameStyle;
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