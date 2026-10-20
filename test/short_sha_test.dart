import 'package:flutter_test/flutter_test.dart';

/// 短 SHA 的生成规则。
///
/// 单独测一份纯逻辑，因为真正的 `GitService.commitAll` 需要 libgit2，
/// 在宿主机（Linux x86/arm64）上加载不了 .so，跑不起来。
///
/// 这里锁住的是「不能用 Oid.toString()」这个坑：
/// git2dart 的 Oid 把 toString() 重写成 `Oid{sha: ...}`，
/// 直接插值会在 UI 上出现一串调试表示。
void main() {
  group('短 SHA', () {
    test('64 位十六进制取前 7 位', () {
      expect(shortSha('a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0'), 'a1b2c3d');
    });

    test('短于 7 位时原样返回，不越界', () {
      expect(shortSha('abc'), 'abc');
      expect(shortSha('abcdefg'), 'abcdefg');
    });

    test('结果里不能出现 Oid{ 这类调试包装', () {
      final s = shortSha('0123456789abcdef0123456789abcdef01234567');
      expect(s.contains('Oid'), isFalse);
      expect(s.contains('{'), isFalse);
      expect(s, '0123456');
    });
  });
}

/// 与 GitService.commitAll 里保持一致：取 .sha 后截 7 位
String shortSha(String sha) => sha.length > 7 ? sha.substring(0, 7) : sha;