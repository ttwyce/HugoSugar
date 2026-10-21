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
    this.aiSystemPrompt = '',
    this.aiMaxTokensPerRound = 120000,
    this.aiCompressThreshold = 20,
    this.aiKeepRecent = 8,
    this.aiDisabledTools = const [],
    this.skillIds = const [],
    this.accentPreset = 0,
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

  /// 用户自定义的 System Prompt。
  ///
  /// 空串 = 用 [kDefaultSystemPrompt]。
  /// 用「空串表示未覆盖」而不是「存一份副本」的原因：
  /// 默认值将来改进时，没改过 Prompt 的用户能自动受益。
  final String aiSystemPrompt;

  /// 单轮 token 上限（规格：由配置决定）。
  final int aiMaxTokensPerRound;

  /// 历史消息超过多少条时触发上下文压缩。
  ///
  /// 为什么可配：这个值取决于模型的实际上下文窗口。
  /// DeepSeek 是 64K，一些本地小模型只有 8K ——
  /// 写死一个数字，要么长上下文模型被过早砍掉历史，
  /// 要么小模型直接超限报错。
  final int aiCompressThreshold;

  /// 压缩时原样保留最近多少条。
  ///
  /// 必须小于 [aiCompressThreshold]，否则「判定要压缩」
  /// 但保留的比阈值还多，压缩完反而更长（见 ContextCompressor 的注释）。
  final int aiKeepRecent;

  /// 被关掉的工具名。
  ///
  /// 为什么存「关掉的」而不是「开启的」：
  /// 工具会增加（以后可能再加新工具），存黑名单时新增的工具默认可用；
  /// 存白名单的话，升级后新工具会默认被关，用户会以为「功能坏了」。
  final List<String> aiDisabledTools;

  /// 启用的 Skill id。空表示不套用任何 Skill。
  final List<String> skillIds;

  /// 主题强调色预设索引。索引对应 [kAccentPresets]。
  ///
  /// 存索引而不是颜色值：颜色值变了时（比如调整饱和度）老用户
  /// 能自动跟上；而且预设有亮/暗两套值，单存一个 Color 无法表达。
  final int accentPreset;

  AppSettings copyWith({
    DateFormatStyle? dateFormat,
    FileNameStyle? fileNameStyle,
    String? authorName,
    String? authorEmail,
    bool? aiReadNotes,
    List<String>? aiNoteCategoryIds,
    String? aiSystemPrompt,
    int? aiMaxTokensPerRound,
    int? aiCompressThreshold,
    int? aiKeepRecent,
    List<String>? aiDisabledTools,
    List<String>? skillIds,
    int? accentPreset,
  }) {
    return AppSettings(
      dateFormat: dateFormat ?? this.dateFormat,
      fileNameStyle: fileNameStyle ?? this.fileNameStyle,
      authorName: authorName ?? this.authorName,
      authorEmail: authorEmail ?? this.authorEmail,
      aiReadNotes: aiReadNotes ?? this.aiReadNotes,
      aiNoteCategoryIds: aiNoteCategoryIds ?? this.aiNoteCategoryIds,
      aiSystemPrompt: aiSystemPrompt ?? this.aiSystemPrompt,
      aiMaxTokensPerRound: aiMaxTokensPerRound ?? this.aiMaxTokensPerRound,
      aiCompressThreshold: aiCompressThreshold ?? this.aiCompressThreshold,
      aiKeepRecent: aiKeepRecent ?? this.aiKeepRecent,
      aiDisabledTools: aiDisabledTools ?? this.aiDisabledTools,
      skillIds: skillIds ?? this.skillIds,
      accentPreset: accentPreset ?? this.accentPreset,
    );
  }

  Map<String, Object?> toJson() => {
    'dateFormat': dateFormat.id,
    'fileNameStyle': fileNameStyle.id,
    'authorName': authorName,
    'authorEmail': authorEmail,
    'aiReadNotes': aiReadNotes,
    'aiNoteCategoryIds': aiNoteCategoryIds,
    'aiSystemPrompt': aiSystemPrompt,
    'aiMaxTokensPerRound': aiMaxTokensPerRound,
    'aiCompressThreshold': aiCompressThreshold,
    'aiKeepRecent': aiKeepRecent,
    'aiDisabledTools': aiDisabledTools,
    'skillIds': skillIds,
    'accentPreset': accentPreset,
  };

  static AppSettings fromJson(Map<String, Object?> j) => AppSettings(
    dateFormat: DateFormatStyle.fromId(j['dateFormat'] as String?),
    fileNameStyle: FileNameStyle.fromId(j['fileNameStyle'] as String?),
    authorName: j['authorName'] as String? ?? '',
    authorEmail: j['authorEmail'] as String? ?? '',
    aiReadNotes: j['aiReadNotes'] as bool? ?? false,
    aiNoteCategoryIds:
        (j['aiNoteCategoryIds'] as List?)?.cast<String>() ?? const [],
    aiSystemPrompt: j['aiSystemPrompt'] as String? ?? '',
    // 旧版本文件里没有这个字段，回落到默认值而不是 0 ——
    // 0 会让第一轮请求立刻判定「超限」
    aiMaxTokensPerRound: (j['aiMaxTokensPerRound'] as num?)?.toInt() ?? 120000,
    // 下限保护：0 会让「压缩」在同一轮里反复触发，
    // 1 会让最近消息只留一条，等于把上下文全折叠掉
    aiCompressThreshold: ((j['aiCompressThreshold'] as num?)?.toInt() ?? 20)
        .clamp(4, 200),
    aiKeepRecent: ((j['aiKeepRecent'] as num?)?.toInt() ?? 8).clamp(2, 100),
    aiDisabledTools:
        (j['aiDisabledTools'] as List?)?.cast<String>() ?? const [],
    skillIds: (j['skillIds'] as List?)?.cast<String>() ?? const [],
    accentPreset: ((j['accentPreset'] as num?)?.toInt() ?? 0).clamp(0, 20),
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
  String get aiSystemPrompt;
  int get aiMaxTokensPerRound;
  int get aiCompressThreshold;
  int get aiKeepRecent;
  List<String> get aiDisabledTools;
  List<String> get skillIds;
  int get accentPreset;
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
