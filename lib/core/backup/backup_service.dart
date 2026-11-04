import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../note/note.dart';
import '../note/note_store.dart';
import 'backup_config.dart';
import 'backup_crypto.dart';
import 'webdav_client.dart';

/// 当前平台是否支持真正的后台 isolate。
///
/// `dart:isolate` 在 web 上只有 stub，调用会抛 UnsupportedError。
/// 用编译期常量判断，dart2js 下整段分支会被 tree-shake 掉。
const bool _supportsIsolate = bool.hasEnvironment('dart.library.io');

/// 备份包的明文结构（加密前）。
///
/// 只在内存里存在，落到云端的永远是密文。
/// 字段刻意保持扁平：将来换加密实现时，这一层不用动。
class BackupPayload {
  const BackupPayload({
    required this.exportedAt,
    required this.notes,
    required this.categories,
  });

  /// 当前备份格式版本。以后字段有增删时提升它。
  static const int schema = 1;

  final DateTime exportedAt;
  final List<Note> notes;
  final List<NoteCategory> categories;

  Map<String, Object?> toJson() => {
        'app': 'HugoSugar',
        'schema': schema,
        'exportedAt': exportedAt.toIso8601String(),
        'notes': notes.map((n) => n.toJson()).toList(),
        'categories': categories.map((c) => c.toJson()).toList(),
      };

  static BackupPayload fromJson(Map<String, Object?> j) {
    final schemaVersion = (j['schema'] as num?)?.toInt() ?? 0;
    if (schemaVersion > schema) {
      throw const BackupCryptoException('备份来自更新版本的 HugoSugar，请先升级 App');
    }
    final rawNotes = j['notes'];
    final rawCategories = j['categories'];
    return BackupPayload(
      exportedAt:
          DateTime.tryParse(j['exportedAt'] as String? ?? '') ?? DateTime(1970),
      notes: rawNotes is List
          ? rawNotes
              .whereType<Map<Object?, Object?>>()
              .map((m) => Note.fromJson(Map<String, Object?>.from(m)))
              .where((n) => n.id.isNotEmpty)
              .toList()
          : const [],
      categories: rawCategories is List
          ? rawCategories
              .whereType<Map<Object?, Object?>>()
              .map((m) => NoteCategory.fromJson(Map<String, Object?>.from(m)))
              .where((c) => c.id.isNotEmpty)
              .toList()
          : const [],
    );
  }
}

/// 备份/恢复的结果。
///
/// 失败不抛异常，而是把原因放进 [message] —— UI 直接弹 SnackBar，
/// 不需要在每个调用点写 try/catch。
class BackupOutcome {
  const BackupOutcome({
    required this.ok,
    this.message,
    this.bytes = 0,
    this.noteCount = 0,
    this.report,
  });

  final bool ok;
  final String? message;
  final int bytes;
  final int noteCount;

  /// 仅恢复时有值
  final NoteMergeStats? report;
}

/// 云端备份的元数据（解密后、写入本地前展示给用户确认）。
class BackupPreview {
  const BackupPreview({
    required this.exportedAt,
    required this.noteCount,
    required this.trashedCount,
    required this.categoryCount,
    required this.sizeBytes,
  });

  final DateTime exportedAt;
  final int noteCount;
  final int trashedCount;
  final int categoryCount;
  final int sizeBytes;
}

/// 想法备份服务：快照 → 压缩 → 加密 → WebDAV。
///
/// 这一层只管流程，不碰 UI，也不持有任何全局状态 ——
/// 每次调用都用传入的 [config] 构造新客户端，改配置后立即生效。
class BackupService {
  BackupService({required this.store, required this.config});

  final NoteStore store;
  final BackupConfig config;

  /// 云端固定文件名。**不按日期分文件**：文件数量和修改时间
  /// 会泄露「多久写一次、哪天写得多」，这与内容加密的初衷矛盾。
  static const String remoteFileName = 'notes.hsbak';

  /// 上传用的临时名。先写它再 MOVE 覆盖正式名，
  /// 避免传到一半断网把唯一的旧备份冲掉。
  static const String tempFileName = '.notes.hsbak.tmp';

  /// 备份口令最短长度。
  ///
  /// 10 位不是安全边界（PBKDF2 迭代次数才是），
  /// 而是防止用户随手设个 `123456` —— 那种口令再高迭代也救不了。
  static const int minPassphraseLength = 10;

  String get _remotePath => '${config.remoteDir}/$remoteFileName';
  String get _tempPath => '${config.remoteDir}/$tempFileName';

  WebDavClient _client() => WebDavClient(
        baseUrl: config.serverUrl,
        username: config.username,
        password: config.password,
        allowBadCertificate: config.allowBadCertificate,
      );

  /// 立即备份。包含回收站里的想法（带 deletedAt 原样保留），
  /// 这样恢复后还能继续从回收站捞回来。
  Future<BackupOutcome> backupNow({required String passphrase}) async {
    final problem = _validate(passphrase);
    if (problem != null) return BackupOutcome(ok: false, message: problem);

    try {
      final payload = BackupPayload(
        exportedAt: DateTime.now(),
        notes: store.all,
        categories: store.categories,
      );
      final jsonBytes = utf8.encode(jsonEncode(payload.toJson()));

      // 顺序不能反：GCM 密文不可压缩，必须先压后加。
      // 压缩与加密一起丢到后台 isolate，主线程不参与。
      final sealed = await _seal(jsonBytes, passphrase);

      final client = _client();
      await client.ensureCollection(config.remoteDir);
      await client.put(_tempPath, sealed);
      try {
        await client.move(_tempPath, _remotePath);
      } on WebDavException {
        // 少数服务器不支持 MOVE。退化成「直接覆盖 + 清理临时文件」，
        // 代价是覆盖瞬间不是原子的，但至少能备份成功。
        await client.put(_remotePath, sealed);
        try {
          await client.delete(_tempPath);
        } on WebDavException {
          // 临时文件清不掉不影响备份结果
        }
      }

      return BackupOutcome(
        ok: true,
        bytes: sealed.length,
        noteCount: payload.notes.where((n) => !n.isDeleted).length,
      );
    } on WebDavException catch (e) {
      return BackupOutcome(ok: false, message: e.message);
    } on BackupCryptoException catch (e) {
      return BackupOutcome(ok: false, message: e.message);
    } catch (e) {
      return BackupOutcome(ok: false, message: '备份失败：$e');
    }
  }

  /// 下载并解密，只返回元数据，**不写入本地**。
  Future<({BackupPreview? preview, String? error})> peek({
    required String passphrase,
  }) async {
    final problem = _validate(passphrase);
    if (problem != null) return (preview: null, error: problem);

    try {
      final payload = await _downloadPayload(passphrase);
      if (payload == null) {
        return (preview: null, error: '云端还没有备份文件');
      }
      return (
        preview: BackupPreview(
          exportedAt: payload.exportedAt,
          noteCount: payload.notes.where((n) => !n.isDeleted).length,
          trashedCount: payload.notes.where((n) => n.isDeleted).length,
          categoryCount: payload.categories.length,
          sizeBytes: 0,
        ),
        error: null,
      );
    } on WebDavException catch (e) {
      return (preview: null, error: e.message);
    } on BackupCryptoException catch (e) {
      return (preview: null, error: e.message);
    } catch (e) {
      return (preview: null, error: '读取备份失败：$e');
    }
  }

  /// 下载 → 解密 → 与本地合并。
  ///
  /// 合并策略见 [NoteStore.mergeBackup]：同 id 取 updatedAt 更新的那条，
  /// 所以「备份之后新写的想法」不会被旧备份冲掉。
  Future<BackupOutcome> restoreMerge({required String passphrase}) async {
    final problem = _validate(passphrase);
    if (problem != null) return BackupOutcome(ok: false, message: problem);

    try {
      final payload = await _downloadPayload(passphrase);
      if (payload == null) {
        return const BackupOutcome(ok: false, message: '云端还没有备份文件');
      }
      final stats = await store.mergeBackup(
        notes: payload.notes,
        categories: payload.categories,
      );
      return BackupOutcome(
        ok: true,
        noteCount: stats.added + stats.updated,
        report: stats,
      );
    } on WebDavException catch (e) {
      return BackupOutcome(ok: false, message: e.message);
    } on BackupCryptoException catch (e) {
      return BackupOutcome(ok: false, message: e.message);
    } catch (e) {
      return BackupOutcome(ok: false, message: '恢复失败：$e');
    }
  }

  /// 连接测试，不涉及口令。
  Future<String?> testConnection() async {
    if (!config.isConfigured) return '请先填写服务器地址和账号';
    try {
      final client = _client();
      await client.testConnection();
      return null;
    } on WebDavException catch (e) {
      return e.message;
    } catch (e) {
      return '连接失败：$e';
    }
  }

  // ── 内部实现 ────────────────────────────────────────

  Future<BackupPayload?> _downloadPayload(String passphrase) async {
    final client = _client();
    final bytes = await client.get(_remotePath);
    if (bytes == null) return null;
    if (!BackupCrypto.looksLikeBackup(bytes)) {
      throw const BackupCryptoException('这个文件不是 HugoSugar 的备份');
    }
    final plain = await _open(bytes, passphrase);
    final decoded = jsonDecode(plain);
    if (decoded is! Map) {
      throw const BackupCryptoException('备份内容格式不正确');
    }
    return BackupPayload.fromJson(Map<String, Object?>.from(decoded));
  }

  // ── 加解密：一律在后台 isolate 执行 ──────────────────
  //
  // PBKDF2 是 21 万轮纯 Dart 计算，手机上要 1-3 秒。放在主 isolate 上会占满
  // 事件循环：按下「立即备份」之后界面一帧都画不出来，看起来就是卡死。
  // gzip 顺带一起搬进 isolate——数据已经在那儿了，省一次跨 isolate 拷贝。

  static Uint8List _sealSync(Uint8List jsonBytes, String passphrase) {
    final compressed = GZipEncoder().encode(jsonBytes);
    if (compressed == null) {
      throw const BackupCryptoException('压缩失败');
    }
    return BackupCrypto.encrypt(
      plaintext: Uint8List.fromList(compressed),
      passphrase: passphrase,
    );
  }

  static String _openSync(Uint8List container, String passphrase) {
    final plain = BackupCrypto.decrypt(
      container: container,
      passphrase: passphrase,
    );
    return utf8.decode(GZipDecoder().decodeBytes(plain));
  }

  Future<Uint8List> _seal(Uint8List jsonBytes, String passphrase) {
    if (!_supportsIsolate) return Future.value(_sealSync(jsonBytes, passphrase));
    return Isolate.run(() => _sealSync(jsonBytes, passphrase));
  }

  Future<String> _open(Uint8List container, String passphrase) {
    if (!_supportsIsolate) {
      return Future.value(_openSync(container, passphrase));
    }
    return Isolate.run(() => _openSync(container, passphrase));
  }

  String? _validate(String passphrase) {
    if (!config.isConfigured) return '请先配置 WebDAV 服务器';
    if (!config.serverUrl.toLowerCase().startsWith('https://') &&
        !config.allowInsecureHttp) {
      return '服务器地址必须以 https:// 开头。若确实要用明文 HTTP，请打开「允许明文连接」并自行承担风险';
    }
    if (passphrase.trim().length < minPassphraseLength) {
      return '备份口令至少 $minPassphraseLength 位';
    }
    return null;
  }
}
