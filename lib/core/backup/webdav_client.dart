import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// WebDAV 请求失败。
///
/// [message] 是可以直接展示给用户的中文说明；
/// [statusCode] 只在需要区分「没权限」和「路径不存在」时使用。
class WebDavException implements Exception {
  const WebDavException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'WebDavException(${statusCode ?? '-'}): $message';
}

/// 极简 WebDAV 客户端。
///
/// ## 为什么手写而不引 webdav_client
///
/// 只需要 5 个动词（PROPFIND / MKCOL / PUT / GET / MOVE / DELETE），
/// 手写约 150 行；而现成的包会拖进 dio + xml 两条依赖链。
/// 本项目对依赖的态度是「能用 SDK 就不加包」（见 AGENTS.md）。
///
/// ## 为什么用 dart:io 而不是 http 包
///
/// 自签证书需要 `badCertificateCallback`，只有 `HttpClient` 提供。
/// 很多人的 WebDAV 是群晖/自建服务器，证书是自签的，
/// 不允许用户打开这个开关等于直接不可用。
class WebDavClient {
  WebDavClient({
    required String baseUrl,
    required this.username,
    required this.password,
    this.allowBadCertificate = false,
  }) : baseUrl = _normalize(baseUrl);

  /// 已去掉尾部斜杠的服务器根地址。
  final String baseUrl;
  final String username;
  final String password;

  /// 是否接受自签/无效证书。**默认关闭**，由用户显式打开。
  final bool allowBadCertificate;

  /// 明文 HTTP 是否允许。默认不允许 —— 密码和密文都会在路上裸奔。
  bool get isSecure => baseUrl.toLowerCase().startsWith('https://');

  /// 测试连通性与认证：对根目录做一次 Depth:0 的 PROPFIND。
  Future<void> testConnection() async {
    final res = await _send(
      'PROPFIND',
      '',
      headers: const {'Depth': '0'},
      body: _propfindBody,
    );
    if (res.status == 401) {
      throw const WebDavException('账号或密码不正确', statusCode: 401);
    }
    if (res.status != 207 && res.status != 200) {
      throw WebDavException(
        '服务器返回 HTTP ${res.status}，请确认地址是 WebDAV 根目录',
        statusCode: res.status,
      );
    }
  }

  /// 逐级创建目录。已存在的层级（405 Method Not Allowed）视为成功。
  Future<void> ensureCollection(String path) async {
    final segments = path
        .split('/')
        .where((s) => s.trim().isNotEmpty)
        .toList(growable: false);
    var current = '';
    for (final segment in segments) {
      current = current.isEmpty ? segment : '$current/$segment';
      final res = await _send('MKCOL', current);
      // 201 新建成功；405 已存在；301/302 某些服务器会重定向到带斜杠的地址
      if (res.status == 201 || res.status == 405 || res.status == 301) {
        continue;
      }
      if (res.status == 401) {
        throw const WebDavException('账号或密码不正确', statusCode: 401);
      }
      if (res.status == 403) {
        throw WebDavException(
          '没有权限在「$current」创建目录（HTTP 403）',
          statusCode: 403,
        );
      }
      throw WebDavException(
        '创建目录「$current」失败（HTTP ${res.status}）',
        statusCode: res.status,
      );
    }
  }

  /// 文件是否存在。
  Future<bool> exists(String path) async {
    final res = await _send(
      'PROPFIND',
      path,
      headers: const {'Depth': '0'},
      body: _propfindBody,
    );
    if (res.status == 207 || res.status == 200) return true;
    if (res.status == 404) return false;
    if (res.status == 401) {
      throw const WebDavException('账号或密码不正确', statusCode: 401);
    }
    throw WebDavException('检查文件失败（HTTP ${res.status}）',
        statusCode: res.status);
  }

  /// 上传（覆盖）。201 = 新建，204 = 覆盖成功。
  Future<void> put(String path, Uint8List bytes) async {
    final res = await _send('PUT', path, body: bytes);
    if (res.status == 201 || res.status == 204 || res.status == 200) return;
    if (res.status == 401) {
      throw const WebDavException('账号或密码不正确', statusCode: 401);
    }
    if (res.status == 403) {
      throw const WebDavException('没有写入权限（HTTP 403）', statusCode: 403);
    }
    if (res.status == 507) {
      throw const WebDavException('云端空间不足（HTTP 507）', statusCode: 507);
    }
    throw WebDavException('上传失败（HTTP ${res.status}）', statusCode: res.status);
  }

  /// 下载。文件不存在返回 null（不是异常 —— 「还没有备份」是正常状态）。
  Future<Uint8List?> get(String path) async {
    final res = await _send('GET', path);
    if (res.status == 404) return null;
    if (res.status == 200) return res.body;
    if (res.status == 401) {
      throw const WebDavException('账号或密码不正确', statusCode: 401);
    }
    throw WebDavException('下载失败（HTTP ${res.status}）', statusCode: res.status);
  }

  /// 移动/重命名（用于「临时名 → 正式名」的原子替换）。
  Future<void> move(String from, String to) async {
    final res = await _send(
      'MOVE',
      from,
      headers: {
        'Destination': _resolve(to).toString(),
        'Overwrite': 'T',
      },
    );
    if (res.status == 201 || res.status == 204 || res.status == 200) return;
    throw WebDavException('替换备份文件失败（HTTP ${res.status}）',
        statusCode: res.status);
  }

  /// 删除。404 视为成功（目标已不存在）。
  Future<void> delete(String path) async {
    final res = await _send('DELETE', path);
    if (res.status == 204 || res.status == 200 || res.status == 404) return;
    throw WebDavException('删除失败（HTTP ${res.status}）', statusCode: res.status);
  }

  // ── 内部实现 ────────────────────────────────────────

  Future<_Response> _send(
    String method,
    String path, {
    Uint8List? body,
    Map<String, String>? headers,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20)
      ..idleTimeout = const Duration(seconds: 10);
    if (allowBadCertificate) {
      // 只在用户明确允许时放开；否则自签证书一律握手失败
      client.badCertificateCallback = (_, __, ___) => true;
    }

    try {
      final uri = _resolve(path);
      final request = await client.openUrl(method, uri);
      request.headers.set(HttpHeaders.authorizationHeader, _basicAuth);
      request.headers.set(HttpHeaders.userAgentHeader, 'HugoSugar/1.0');
      if (headers != null) {
        headers.forEach((key, value) => request.headers.set(key, value));
      }
      if (body != null) {
        request.headers.contentType = ContentType.binary;
        request.contentLength = body.length;
        request.add(body);
      }
      final response = await request.close();
      final chunks = await response.fold<List<int>>(
        <int>[],
        (acc, chunk) => acc..addAll(chunk),
      );
      return _Response(response.statusCode, Uint8List.fromList(chunks));
    } on SocketException catch (e) {
      throw WebDavException('无法连接服务器：${e.message}');
    } on HandshakeException {
      throw const WebDavException(
        'TLS 握手失败。若服务器使用自签证书，请打开「允许自签证书」',
      );
    } on HttpException catch (e) {
      throw WebDavException('请求失败：${e.message}');
    } on TimeoutException {
      throw const WebDavException('连接超时，请检查服务器地址和网络');
    } finally {
      client.close(force: true);
    }
  }

  Uri _resolve(String path) {
    final segments = <String>[];
    for (final raw in path.split('/')) {
      final s = raw.trim();
      if (s.isEmpty || s == '.') continue;
      segments.add(Uri.encodeComponent(s));
    }
    final tail = segments.isEmpty ? '' : '/${segments.join('/')}';
    return Uri.parse('$baseUrl$tail');
  }

  String get _basicAuth {
    final raw = '$username:$password';
    return 'Basic ${base64Encode(utf8.encode(raw))}';
  }

  static String _normalize(String url) {
    var s = url.trim();
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  /// 只请求 resourcetype，响应体最小。很多服务器对空 body 的 PROPFIND 报 400。
  static final Uint8List _propfindBody = Uint8List.fromList(
    utf8.encode(
      '<?xml version="1.0" encoding="utf-8"?>'
      '<d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/></d:prop></d:propfind>',
    ),
  );
}

class _Response {
  const _Response(this.status, this.body);

  final int status;
  final Uint8List body;
}
