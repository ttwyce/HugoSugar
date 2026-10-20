import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hugosugar/core/settings/app_settings.dart';

void main() {
  group('提交作者身份', () {
    test('默认留空 = 自动推断', () {
      const s = AppSettings();
      expect(s.authorName, isEmpty);
      expect(s.authorEmail, isEmpty);
    });

    test('toJson / fromJson 往返不丢字段', () {
      const s = AppSettings(
        authorName: 'octocat',
        authorEmail: 'me@example.com',
      );
      final back = AppSettings.fromJson(s.toJson());
      expect(back.authorName, 'octocat');
      expect(back.authorEmail, 'me@example.com');
    });

    test('旧版 settings.json 没有这两个键时安全回落', () {
      // 老版本只存了 dateFormat / fileNameStyle，升级后不能崩
      final back = AppSettings.fromJson({
        'dateFormat': 'space',
        'fileNameStyle': 'timestamp',
      });
      expect(back.authorName, isEmpty);
      expect(back.authorEmail, isEmpty);
      expect(back.dateFormat, DateFormatStyle.space);
    });

    test('保存后能读回（真实文件）', () async {
      final dir = Directory.systemTemp.createTempSync('hugosugar_settings');
      try {
        final store = SettingsStore(File('${dir.path}/settings.json'));
        await store.save(const AppSettings(
          authorName: 'octocat',
          authorEmail: 'me@example.com',
        ));
        final loaded = await store.load();
        expect(loaded.authorName, 'octocat');
        expect(loaded.authorEmail, 'me@example.com');
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });
}