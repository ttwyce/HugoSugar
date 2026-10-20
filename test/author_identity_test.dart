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
        authorName: 'ttwyce',
        authorEmail: '3238084478@qq.com',
      );
      final back = AppSettings.fromJson(s.toJson());
      expect(back.authorName, 'ttwyce');
      expect(back.authorEmail, '3238084478@qq.com');
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
          authorName: 'ttwyce',
          authorEmail: '3238084478@qq.com',
        ));
        final loaded = await store.load();
        expect(loaded.authorName, 'ttwyce');
        expect(loaded.authorEmail, '3238084478@qq.com');
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });
}