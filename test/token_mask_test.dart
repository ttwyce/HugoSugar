import 'package:flutter_test/flutter_test.dart';
import 'package:hugosugar/features/settings/token_dialog.dart';

void main() {
  group('令牌打码', () {
    test('长令牌保留头尾，中间打点', () {
      final m = maskToken('ghp_abcdefghijklmnopqrstuvwxyz123456');
      expect(m.startsWith('ghp_ab'), isTrue);
      expect(m.endsWith('3456'), isTrue);
      expect(m.contains('••••'), isTrue);
      // 不能泄露中间部分
      expect(m.contains('mnopqr'), isFalse);
    });

    test('短令牌整体打码，不泄露任何字符', () {
      expect(maskToken('abc'), '••••••');
      expect(maskToken('1234567890'), '••••••');
    });

    test('打码结果长度远小于原文', () {
      final raw = 'github_pat_${'x' * 60}';
      expect(maskToken(raw).length, lessThan(raw.length));
    });
  });
}