import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// 备份加解密失败。
///
/// **对外文案不要区分「口令错」和「文件损坏」**：
/// 两者在 AES-GCM 里都是同一个认证失败，如果提示不同，
/// 攻击者就能拿它当 oracle 逐步试探口令是否正确。
/// 所有解密失败一律落到 [badPassphraseOrCorrupt]。
class BackupCryptoException implements Exception {
  const BackupCryptoException(this.message);

  /// 可直接展示给用户的中文说明。
  final String message;

  @override
  String toString() => 'BackupCryptoException: $message';
}

/// 备份文件的加解密。
///
/// ## 为什么是这套参数
///
/// | 环节 | 选择 | 理由 |
/// |---|---|---|
/// | KDF | PBKDF2-HMAC-SHA256 / 210,000 轮 / 32B 盐 | 纯 Dart 可实现；手机上约 1-2 秒 |
/// | 加密 | AES-256-GCM / 12B nonce / 128-bit tag | 认证加密，篡改必然解不开 |
/// | 压缩 | 调用方先 gzip 再加密 | GCM 密文不可压缩，顺序不能反 |
///
/// Argon2id 抗 GPU 更好，但纯 Dart 实现要几十秒，手机上不可接受，
/// 所以用「PBKDF2 + 高迭代次数 + 每个备份独立随机盐」的折中。
///
/// ## 容器格式
///
/// ```
/// offset  长度  内容
/// 0       4     magic "HSBK"
/// 4       1     版本（当前 1）
/// 5       1     KDF 算法（1 = PBKDF2-HMAC-SHA256）
/// 6       4     迭代次数，大端
/// 10      1     盐长度
/// 11      n     盐
/// 11+n    1     nonce 长度
/// 12+n    m     nonce
/// 12+n+m  ...   GCM 密文 ‖ 16 字节 tag
/// ```
///
/// 头部（magic 到 nonce）整体作为 **AAD** 参与认证。这样攻击者
/// 无法把迭代次数改小来做降级攻击 —— 改一个字节，解密必然失败。
class BackupCrypto {
  const BackupCrypto._();

  static const List<int> _magic = [0x48, 0x53, 0x42, 0x4B]; // HSBK
  static const int _version = 1;
  static const int _kdfPbkdf2 = 1;

  /// 默认迭代次数。提高它会让老备份仍可解（参数写在文件头里），
  /// 但新备份更慢，所以不做无上限的加法。
  static const int defaultIterations = 210000;

  static const int _saltLength = 32;
  static const int _nonceLength = 12;
  static const int _keyLength = 32;
  static const int _tagBits = 128;

  /// 迭代次数下限。低于它的文件视为异常（正常文件不会这么小）。
  static const int _minIterations = 10000;

  /// 迭代次数上限。防止构造一个 iterations=2^31 的文件
  /// 让手机在派生密钥时卡死（拒绝服务）。
  static const int _maxIterations = 1000000;

  /// 解密失败的统一文案。
  static const String badPassphraseOrCorrupt = '口令错误，或备份文件已损坏';

  /// 加密。[plaintext] 应已经是 gzip 压缩后的字节。
  static Uint8List encrypt({
    required Uint8List plaintext,
    required String passphrase,
    int iterations = defaultIterations,
  }) {
    if (passphrase.isEmpty) {
      throw const BackupCryptoException('备份口令不能为空');
    }
    if (iterations < _minIterations || iterations > _maxIterations) {
      throw const BackupCryptoException('迭代次数超出允许范围');
    }

    final salt = _randomBytes(_saltLength);
    final nonce = _randomBytes(_nonceLength);
    final header = _buildHeader(
      iterations: iterations,
      salt: salt,
      nonce: nonce,
    );
    final key = _deriveKey(passphrase, salt, iterations);

    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(KeyParameter(key), _tagBits, nonce, header),
      );
    final sealed = cipher.process(plaintext);

    final out = Uint8List(header.length + sealed.length);
    out.setRange(0, header.length, header);
    out.setRange(header.length, out.length, sealed);
    return out;
  }

  /// 解密，返回 gzip 压缩后的明文。失败统一抛 [BackupCryptoException]。
  static Uint8List decrypt({
    required Uint8List container,
    required String passphrase,
  }) {
    final header = _parseHeader(container);
    final key = _deriveKey(passphrase, header.salt, header.iterations);

    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        false,
        AEADParameters(
          KeyParameter(key),
          _tagBits,
          header.nonce,
          header.aad,
        ),
      );
    try {
      return cipher.process(container.sublist(header.bodyOffset));
    } catch (_) {
      // 认证失败、密文截断、tag 不匹配都到这里。
      // 故意不区分原因，避免成为口令试探的 oracle。
      throw const BackupCryptoException(badPassphraseOrCorrupt);
    }
  }

  /// 只读文件头，用于在不解密的情况下判断「这是不是我们的备份」。
  static bool looksLikeBackup(Uint8List bytes) {
    if (bytes.length < 6) return false;
    for (var i = 0; i < _magic.length; i++) {
      if (bytes[i] != _magic[i]) return false;
    }
    return bytes[4] == _version;
  }

  // ── 内部实现 ────────────────────────────────────────

  static Uint8List _buildHeader({
    required int iterations,
    required Uint8List salt,
    required Uint8List nonce,
  }) {
    final b = BytesBuilder(copy: false)
      ..add(_magic)
      ..addByte(_version)
      ..addByte(_kdfPbkdf2)
      ..add(_uint32(iterations))
      ..addByte(salt.length)
      ..add(salt)
      ..addByte(nonce.length)
      ..add(nonce);
    return b.toBytes();
  }

  static _Header _parseHeader(Uint8List data) {
    // magic(4) + ver(1) + kdf(1) + iters(4) + saltLen(1) + nonceLen(1)
    const minLength = 12;
    if (data.length < minLength) {
      throw const BackupCryptoException('备份文件不完整');
    }
    for (var i = 0; i < _magic.length; i++) {
      if (data[i] != _magic[i]) {
        throw const BackupCryptoException('这不是 HugoSugar 的备份文件');
      }
    }
    if (data[4] != _version) {
      throw BackupCryptoException('备份格式版本不支持（v${data[4]}）');
    }
    if (data[5] != _kdfPbkdf2) {
      throw const BackupCryptoException('备份使用了不支持的加密算法');
    }

    final iterations =
        ByteData.sublistView(data, 6, 10).getUint32(0, Endian.big);
    if (iterations < _minIterations || iterations > _maxIterations) {
      throw const BackupCryptoException('备份文件的加密参数不合法');
    }

    var offset = 10;
    final saltLength = data[offset++];
    if (saltLength == 0 || offset + saltLength > data.length) {
      throw const BackupCryptoException('备份文件不完整');
    }
    final salt = data.sublist(offset, offset + saltLength);
    offset += saltLength;

    if (offset >= data.length) {
      throw const BackupCryptoException('备份文件不完整');
    }
    final nonceLength = data[offset++];
    if (nonceLength == 0 || offset + nonceLength > data.length) {
      throw const BackupCryptoException('备份文件不完整');
    }
    final nonce = data.sublist(offset, offset + nonceLength);
    offset += nonceLength;

    // AAD 必须与加密时逐字节一致，所以这里取原始切片而不是重建
    final aad = data.sublist(0, offset);

    return _Header(
      iterations: iterations,
      salt: salt,
      nonce: nonce,
      aad: aad,
      bodyOffset: offset,
    );
  }

  static Uint8List _deriveKey(
    String passphrase,
    Uint8List salt,
    int iterations,
  ) {
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, iterations, _keyLength));
    // 用手动 UTF-8 编码，支持中文口令
    return derivator.process(Uint8List.fromList(utf8.encode(passphrase)));
  }

  static Uint8List _uint32(int value) {
    final data = ByteData(4)..setUint32(0, value, Endian.big);
    return data.buffer.asUint8List();
  }

  static Uint8List _randomBytes(int length) {
    // Random.secure() 走平台 CSPRNG；不能用普通 Random(种子)
    final random = Random.secure();
    final out = Uint8List(length);
    for (var i = 0; i < length; i++) {
      out[i] = random.nextInt(256);
    }
    return out;
  }
}

class _Header {
  const _Header({
    required this.iterations,
    required this.salt,
    required this.nonce,
    required this.aad,
    required this.bodyOffset,
  });

  final int iterations;
  final Uint8List salt;
  final Uint8List nonce;
  final Uint8List aad;
  final int bodyOffset;
}
