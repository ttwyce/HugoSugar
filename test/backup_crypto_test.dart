import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hugosugar/core/backup/backup_crypto.dart';

/// 加解密测试。
///
/// 迭代次数用 10000（下限）而不是默认的 210000：
/// 单测要跑十几次加解密，用默认值会让 CI 多花半分钟以上。
/// 安全性由默认值保证，这里只验证**逻辑正确性**。
void main() {
  const passphrase = 'correct horse battery staple';
  const fastIterations = 10000;

  final plain = Uint8List.fromList(
    utf8.encode('{"schema":1,"notes":[{"id":"note_1","content":"想法"}]}'),
  );

  Uint8List seal({String pass = passphrase}) => BackupCrypto.encrypt(
        plaintext: plain,
        passphrase: pass,
        iterations: fastIterations,
      );

  group('BackupCrypto', () {
    test('加密后能用同一口令解回原文', () {
      final sealed = seal();
      expect(BackupCrypto.looksLikeBackup(sealed), isTrue);

      final opened = BackupCrypto.decrypt(
        container: sealed,
        passphrase: passphrase,
      );
      expect(opened, equals(plain));
    });

    test('相同明文两次加密得到不同密文', () {
      // nonce 与盐都随机；如果两次结果相同，说明随机源坏了
      final a = seal();
      final b = seal();
      expect(a, isNot(equals(b)));
      expect(a.length, equals(b.length));
    });

    test('中文口令可用', () {
      const chinese = '这是一个中文备份口令';
      final sealed = seal(pass: chinese);
      final opened = BackupCrypto.decrypt(
        container: sealed,
        passphrase: chinese,
      );
      expect(opened, equals(plain));
    });

    test('错误口令解不开', () {
      final sealed = seal();
      expect(
        () => BackupCrypto.decrypt(
          container: sealed,
          passphrase: 'wrong-passphrase-here',
        ),
        throwsA(isA<BackupCryptoException>()),
      );
    });

    test('篡改密文末尾（tag）会被拒绝', () {
      final sealed = seal();
      final tampered = Uint8List.fromList(sealed);
      tampered[tampered.length - 1] ^= 0xFF;

      expect(
        () => BackupCrypto.decrypt(container: tampered, passphrase: passphrase),
        throwsA(isA<BackupCryptoException>()),
      );
    });

    test('篡改密文正文会被拒绝', () {
      final sealed = seal();
      final tampered = Uint8List.fromList(sealed);
      // 头部之后第一个字节就是密文
      final bodyStart = sealed.length - plain.length - 16;
      tampered[bodyStart] ^= 0x01;

      expect(
        () => BackupCrypto.decrypt(container: tampered, passphrase: passphrase),
        throwsA(isA<BackupCryptoException>()),
      );
    });

    test('篡改头部迭代次数会导致 AAD 不匹配（防降级攻击）', () {
      final sealed = seal();
      final tampered = Uint8List.fromList(sealed);
      // offset 6..9 是大端迭代次数，改最低字节
      tampered[9] ^= 0x01;

      expect(
        () => BackupCrypto.decrypt(container: tampered, passphrase: passphrase),
        throwsA(isA<BackupCryptoException>()),
      );
    });

    test('空口令拒绝加密', () {
      expect(
        () => BackupCrypto.encrypt(plaintext: plain, passphrase: ''),
        throwsA(isA<BackupCryptoException>()),
      );
    });

    test('截断的文件被识别为不完整', () {
      final sealed = seal();
      final truncated = Uint8List.sublistView(sealed, 0, 8);
      expect(
        () => BackupCrypto.decrypt(
          container: truncated,
          passphrase: passphrase,
        ),
        throwsA(isA<BackupCryptoException>()),
      );
    });

    test('非本应用的文件不会被误判', () {
      final foreign = Uint8List.fromList(List<int>.filled(64, 0x41));
      expect(BackupCrypto.looksLikeBackup(foreign), isFalse);
      expect(
        () => BackupCrypto.decrypt(container: foreign, passphrase: passphrase),
        throwsA(isA<BackupCryptoException>()),
      );
    });
  });
}
