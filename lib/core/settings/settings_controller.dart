import 'package:flutter/foundation.dart';

import 'app_settings.dart' show AppSettings, DateFormatStyle, FileNameStyle, SettingsControllerLike, SettingsStore;

/// 偏好设置的全局持有者。
///
/// 用 ChangeNotifier 而不是把 AppSettings 一路往下传：
/// 日期格式和命名规则是在「写入文件」的那一刻才用到的，
/// 而写文件发生在 SiteController / 各种弹窗里，硬传会把签名污染一大片。
class SettingsController extends ChangeNotifier implements SettingsControllerLike {
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
  Future<void> setAiMaxTokensPerRound(int tokens) async {
    final v = tokens < 1000 ? 1000 : tokens;
    if (_value.aiMaxTokensPerRound == v) return;
    _value = _value.copyWith(aiMaxTokensPerRound: v);
    notifyListeners();
    await _store?.save(_value);
  }
}