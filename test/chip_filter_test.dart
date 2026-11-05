import 'package:flutter_test/flutter_test.dart';
import 'package:hugosugar/shared/chip_editor.dart';

void main() {
  const all = ['flutter', 'dart', 'hugo', 'kotlin-fluent', 'Fluently'];

  group('filterSuggestions', () {
    test('输入为空时原样返回（保持使用频率序）', () {
      final out = filterSuggestions(all: all, selected: const [], typed: '');
      expect(out, all);
    });

    test('已选中的项不会出现在候选里', () {
      final out = filterSuggestions(
        all: all,
        selected: const ['flutter'],
        typed: '',
      );
      expect(out.contains('flutter'), isFalse);
      expect(out.length, all.length - 1);
    });

    test('前缀匹配排在包含匹配之前', () {
      final out = filterSuggestions(
        all: all,
        selected: const [],
        typed: 'flu',
      );
      // flutter / Fluently 是前缀命中，kotlin-fluent 只是包含
      expect(out.length, 3);
      expect(out.indexOf('kotlin-fluent'), 2);
    });

    test('大小写不敏感', () {
      final upper = filterSuggestions(all: all, selected: const [], typed: 'FLU');
      final lower = filterSuggestions(all: all, selected: const [], typed: 'flu');
      expect(upper, lower);
    });

    test('无匹配时返回空列表', () {
      final out = filterSuggestions(
        all: all,
        selected: const [],
        typed: 'zzz',
      );
      expect(out, isEmpty);
    });

    test('已选中的项即使用输入词命中也不出现', () {
      final out = filterSuggestions(
        all: all,
        selected: const ['flutter'],
        typed: 'flu',
      );
      expect(out.contains('flutter'), isFalse);
      expect(out.contains('Fluently'), isTrue);
    });
  });
}
