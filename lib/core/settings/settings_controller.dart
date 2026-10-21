import 'package:flutter/foundation.dart';

import 'app_settings.dart'
    show
        AppSettings,
        DateFormatStyle,
        FileNameStyle,
        SettingsControllerLike,
        SettingsStore;

/// 偏好设置的全局持有者。
///
/// 用 ChangeNotifier 而不是把 AppSettings 一路往下传：
/// 日期格式和命名规则是在「写入文件」的那一刻才用到的，
/// 而写文件发生在 SiteController / 各种弹窗里，硬传会把签名污染一大片。
class SettingsController extends ChangeNotifier
    implements SettingsControllerLike {
  SettingsController({SettingsStore? store}) : _store = store;

  SettingsStore? _store;
  AppSettings _value = const AppSettings();

  AppSettings get value => _value;
  @override
  DateFormatStyle get dateFormat => _value.dateFormat;

  @override
  FileNameStyle get fileNameStyle => _value.fileNameStyle;

  @override
  String get authorName => _value.authorName;

  @override
  String get authorEmail => _value.authorEmail;

  @override
  bool get aiReadNotes => _value.aiReadNotes;

  @override
  List<String> get aiNoteCategoryIds => _value.aiNoteCategoryIds;

  @override
  String get aiSystemPrompt => _value.aiSystemPrompt;

  @override
  int get aiMaxTokensPerRound => _value.aiMaxTokensPerRound;

  @override
  int get aiCompressThreshold => _value.aiCompressThreshold;

  @override
  int get aiKeepRecent => _value.aiKeepRecent;
  @override
  List<String> get aiDisabledTools => _value.aiDisabledTools;
  @override
  List<String> get skillIds => _value.skillIds;
  @override
  int get accentPreset => _value.accentPreset;
  @override
  String get localeId => _value.localeId;

  Future<void> setLocaleId(String id) async {
    if (_value.localeId == id) return;
    _value = _value.copyWith(localeId: id);
    notifyListeners();
    await _store?.save(_value);
  }

  Future<void> setAccentPreset(int index) async {
    final v = index.clamp(0, 20);
    if (_value.accentPreset == v) return;
    _value = _value.copyWith(accentPreset: v);
    notifyListeners();
    await _store?.save(_value);
  }

  /// 打开并载入。失败时保持默认值，不抛异常。
  Future<void> load({SettingsStore? store}) async {
    if (store != null) _store = store;
    if (_store == null) return;
    _value = await _store!.load();
    notifyListeners();
  }

  Future<void> setDateFormat(DateFormatStyle v) async {
    if (_value.dateFormat == v) return;
    _value = _value.copyWith(dateFormat: v);
    notifyListeners();
    await _store?.save(_value);
  }

  Future<void> setFileNameStyle(FileNameStyle v) async {
    if (_value.fileNameStyle == v) return;
    _value = _value.copyWith(fileNameStyle: v);
    notifyListeners();
    await _store?.save(_value);
  }

  /// 设置提交作者名与邮箱。传空串表示恢复「自动推断」。
  Future<void> setAuthorIdentity({
    required String name,
    required String email,
  }) async {
    final n = name.trim();
    final e = email.trim();
    if (_value.authorName == n && _value.authorEmail == e) return;
    _value = _value.copyWith(authorName: n, authorEmail: e);
    notifyListeners();
    await _store?.save(_value);
  }

  /// 设置「AI 是否可以读取想法」。
  ///
  /// 默认关闭。这是隐私相关的开关，只在用户主动打开后才生效。
  Future<void> setAiReadNotes({required bool enabled}) async {
    if (_value.aiReadNotes == enabled) return;
    _value = _value.copyWith(aiReadNotes: enabled);
    notifyListeners();
    await _store?.save(_value);
  }

  /// 设置 AI 可读取的分组（空列表 = 不限制）
  Future<void> setAiNoteCategories(List<String> ids) async {
    if (_value.aiNoteCategoryIds.length == ids.length &&
        _value.aiNoteCategoryIds.toSet().containsAll(ids)) {
      return;
    }
    _value = _value.copyWith(aiNoteCategoryIds: List.of(ids));
    notifyListeners();
    await _store?.save(_value);
  }

  /// 设置自定义 System Prompt。
  ///
  /// 传空串表示「恢复默认」—— 存空串而不是存默认值副本，
  /// 这样以后改进默认 Prompt 时，没改过的用户能自动用上新的。
  Future<void> setAiSystemPrompt(String prompt) async {
    final v = prompt.trim().isEmpty ? '' : prompt;
    if (_value.aiSystemPrompt == v) return;
    _value = _value.copyWith(aiSystemPrompt: v);
    notifyListeners();
    await _store?.save(_value);
  }

  /// 单轮 token 上限。
  ///
  /// 下限保护 1000：设成 0 或负数会让第一轮请求立刻判定超限，
  /// 用户只会看到「本轮 token 已用 0，超过上限 0」这种费解提示。
  /// 上下文压缩阈值。
  ///
  /// 下限 4 / 上限 200：阈值太小会让压缩几乎每轮都触发，
  /// 太大则失去意义（模型上下文早就爆了）。
  Future<void> setAiCompressThreshold(int n) async {
    final v = n.clamp(4, 200);
    if (_value.aiCompressThreshold == v) return;
    // 保留条数必须小于阈值，否则「判定要压缩」但保留的比阈值还多，
    // 压缩完反而更长 → 收敛到阈值减一
    final keep = _value.aiKeepRecent >= v ? v - 1 : _value.aiKeepRecent;
    _value = _value.copyWith(aiCompressThreshold: v, aiKeepRecent: keep);
    notifyListeners();
    await _store?.save(_value);
  }

  /// 压缩时原样保留的最近条数。下限 2。
  Future<void> setAiKeepRecent(int n) async {
    final v = n.clamp(2, _value.aiCompressThreshold - 1);
    if (_value.aiKeepRecent == v) return;
    _value = _value.copyWith(aiKeepRecent: v);
    notifyListeners();
    await _store?.save(_value);
  }

  /// 开关一个工具。
  ///
  /// 关掉的工具会从模型的 schema 里移除，而不是「保留但拒绝」：
  /// 保留 schema 会让模型先花一轮 token 去决定调用、再被拒，
  /// 然后可能反复试—— 既浪费又让它困惑。
  Future<void> setToolEnabled(String name, bool enabled) async {
    final cur = _value.aiDisabledTools.toSet();
    final changed = enabled ? cur.remove(name) : cur.add(name);
    if (!changed) return;
    _value = _value.copyWith(aiDisabledTools: cur.toList()..sort());
    notifyListeners();
    await _store?.save(_value);
  }

  Future<void> setSkillIds(List<String> ids) async {
    if (_listEquals(_value.skillIds, ids)) return;
    _value = _value.copyWith(skillIds: List<String>.from(ids));
    notifyListeners();
    await _store?.save(_value);
  }

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> setAiMaxTokensPerRound(int tokens) async {
    final v = tokens < 1000 ? 1000 : tokens;
    if (_value.aiMaxTokensPerRound == v) return;
    _value = _value.copyWith(aiMaxTokensPerRound: v);
    notifyListeners();
    await _store?.save(_value);
  }
}
