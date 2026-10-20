import 'package:flutter_test/flutter_test.dart';
import 'package:hugosugar/core/post/front_matter.dart';
import 'package:hugosugar/core/settings/app_settings.dart';

void main() {
  group('ISO8601 日期格式', () {
    test('带 T 和 +08:00 时区后缀', () {
      final d = DateTime(2024, 5, 1, 8, 3, 9);
      final s = FrontMatterBuilder.formatIso8601(d);
      // 本机时区可能不是 +08:00，所以校验结构而不是写死偏移
      expect(RegExp(r'^2024-05-01T08:03:09[+-]\d{2}:\d{2}$').hasMatch(s), isTrue,
          reason: '实际输出：$s');
    });

    test('不是 toIso8601String 那种带毫秒无时区的样子', () {
      final s = FrontMatterBuilder.formatIso8601(DateTime(2024, 5, 1, 8, 3, 9));
      expect(s.contains('.000'), isFalse);
      expect(RegExp(r'[+-]\d{2}:\d{2}$').hasMatch(s), isTrue);
    });

    test('空格格式保持原样', () {
      final s = FrontMatterBuilder.formatSpace(DateTime(2024, 5, 1, 8, 3, 9));
      expect(s, '2024-05-01 08:03:09');
    });

    test('仅日期格式', () {
      final s = FrontMatterBuilder.formatDateOnly(DateTime(2024, 5, 1, 8, 3, 9));
      expect(s, '2024-05-01');
    });

    test('build 按 dateFormat 参数输出不同写法', () {
      final d = DateTime(2024, 5, 1, 8, 3, 9);

      final iso = FrontMatterBuilder.build(
        original: const {},
        format: 'yaml',
        title: 'T',
        body: 'B',
        date: d,
        dateFormat: 'iso',
      );
      expect(iso.contains('2024-05-01T08:03:09'), isTrue);

      final space = FrontMatterBuilder.build(
        original: const {},
        format: 'yaml',
        title: 'T',
        body: 'B',
        date: d,
        dateFormat: 'space',
      );
      expect(space.contains('2024-05-01 08:03:09'), isTrue);

      final only = FrontMatterBuilder.build(
        original: const {},
        format: 'yaml',
        title: 'T',
        body: 'B',
        date: d,
        dateFormat: 'dateOnly',
      );
      expect(only.contains('date: 2024-05-01'), isTrue);
    });

    test('createNew 也接受 dateFormat', () {
      final out = FrontMatterBuilder.createNew(
        title: 'T',
        date: DateTime(2024, 5, 1, 8, 3, 9),
        dateFormat: 'iso',
      );
      expect(out.contains('T08:03:09'), isTrue);
    });

    test('ISO 字符串能被解析器读回同一天', () {
      final d = DateTime(2024, 5, 1, 8, 3, 9);
      final out = FrontMatterBuilder.build(
        original: const {},
        format: 'yaml',
        title: 'T',
        body: 'B',
        date: d,
        dateFormat: 'iso',
      );
      final doc = FrontMatter.parse(
        relativePath: 'content/posts/a.md',
        fileName: 'a.md',
        content: out,
      );
      expect(doc.date?.year, 2024);
      expect(doc.date?.month, 5);
      expect(doc.date?.day, 1);
    });
  });

  group('AppSettings 序列化', () {
    test('默认是 iso + 跟随标题', () {
      const s = AppSettings();
      expect(s.dateFormat, DateFormatStyle.iso);
      expect(s.fileNameStyle, FileNameStyle.fromTitle);
    });

    test('toJson / fromJson 往返一致', () {
      const s = AppSettings(
        dateFormat: DateFormatStyle.space,
        fileNameStyle: FileNameStyle.timestamp,
      );
      final back = AppSettings.fromJson(s.toJson());
      expect(back.dateFormat, DateFormatStyle.space);
      expect(back.fileNameStyle, FileNameStyle.timestamp);
    });

    test('未知 id 回落到默认值而不是崩溃', () {
      final s = AppSettings.fromJson({
        'dateFormat': 'nonsense',
        'fileNameStyle': 'whatever',
      });
      expect(s.dateFormat, DateFormatStyle.iso);
      expect(s.fileNameStyle, FileNameStyle.fromTitle);
    });

    test('三个枚举的 id 唯一', () {
      final ids = DateFormatStyle.values.map((e) => e.id).toSet();
      expect(ids.length, DateFormatStyle.values.length);
    });
  });
}