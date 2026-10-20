import 'dart:async';
import 'dart:io';

/// Deploy Hook 调用结果。
class DeployResult {
  const DeployResult._({
    required this.ok,
    this.message,
    this.statusCode,
  });

  final bool ok;

  /// 失败原因（成功时为 null）
  final String? message;

  final int? statusCode;

  static DeployResult success(int code) =>
      DeployResult._(ok: true, statusCode: code);

  static DeployResult failure(String msg) =>
      DeployResult._(ok: false, message: msg);
}

/// 触发 Vercel / Netlify 等平台的 Deploy Hook。
///
/// 为什么需要它：push 之后 Vercel 会自己监听 GitHub 仓库并构建，
/// 但**有延迟**（几秒到几十秒），而且如果之前构建失败、或者 hook 被手动
/// 暂停过，只 push 不一定会重新触发。主动打一次 hook 能让用户点完就能看到
/// 部署在跑。
///
/// 安全约束（见 FEATURE_SPEC 风险清单）：
/// - 只允许 https
/// - 拒绝私网 / 环回 / 链路本地地址，防 SSRF
/// - 有超时，不让 UI 卡死
class DeployHookService {
  DeployHookService._();

  static const _timeout = Duration(seconds: 15);

  /// 常见平台的 hook 域名。不强制校验，只用于给用户更明确的错误提示。
  static const knownHosts = [
    'api.vercel.com',
    'hooks.netlify.com',
    'api.netlify.com',
    'api.cloudflare.com',
    'api.render.com',
  ];

  /// 校验 URL 是否可用。返回 null 表示 OK，否则返回错误文案。
  static String? validate(String url) {
    final raw = url.trim();
    if (raw.isEmpty) return '请填写 Deploy Hook 地址';

    final uri = Uri.tryParse(raw);
    if (uri == null) return '地址格式不正确';

    if (uri.scheme != 'https') {
      return '只支持 https 地址（当前是 ${uri.scheme.isEmpty ? "空" : uri.scheme}）';
    }
    if (uri.host.isEmpty) return '地址缺少域名';

    if (_isPrivateHost(uri.host)) {
      return '不允许访问内网地址';
    }
    return null;
  }

  /// 判断是否指向内网 / 环回 / 链路本地。
  ///
  /// 这是 SSRF 的第一道闸。域名解析后还应该再校验一次 IP，
  /// 但 Flutter 的 HttpClient 不暴露解析结果，所以这里只做字面量判断，
  /// 配合「只允许 https + 已知平台域名提示」足够挡住绝大多数误用。
  static bool _isPrivateHost(String host) {
    final h = host.toLowerCase();

    if (h == 'localhost' || h.endsWith('.localhost')) return true;
    if (h == '0.0.0.0' || h == '[::]' || h == '::1') return true;

    final ip = InternetAddress.tryParse(h);
    if (ip != null) {
      if (ip.isLoopback || ip.isLinkLocal) return true;
      final raw = ip.rawAddress;
      if (ip.type == InternetAddressType.IPv4 && raw.length == 4) {
        final a = raw[0];
        final b = raw[1];
        // 10.0.0.0/8
        if (a == 10) return true;
        // 172.16.0.0/12
        if (a == 172 && b >= 16 && b <= 31) return true;
        // 192.168.0.0/16
        if (a == 192 && b == 168) return true;
        // 169.254.0.0/16 已在 isLinkLocal 覆盖，这里兜一层
        if (a == 169 && b == 254) return true;
      }
      return false;
    }

    // 内网常用主机名后缀
    for (final suffix in ['.local', '.internal', '.lan', '.home']) {
      if (h.endsWith(suffix)) return true;
    }
    return false;
  }

  /// 触发 hook。POST，不带 body —— Vercel/Netlify 的 hook 都不需要。
  static Future<DeployResult> trigger(String url) async {
    final err = validate(url);
    if (err != null) return DeployResult.failure(err);

    final uri = Uri.parse(url.trim());
    final client = HttpClient()..connectionTimeout = _timeout;

    try {
      final req = await client.postUrl(uri).timeout(_timeout);
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      req.headers.contentLength = 0;

      final resp = await req.close().timeout(_timeout);
      // 必须把响应体读空，否则连接不会释放
      await resp.drain<void>().timeout(_timeout);

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        return DeployResult.success(resp.statusCode);
      }
      if (resp.statusCode == 401 || resp.statusCode == 403) {
        return DeployResult.failure(
          'Hook 认证失败（HTTP ${resp.statusCode}），地址可能已失效',
        );
      }
      if (resp.statusCode == 404) {
        return DeployResult.failure('Hook 不存在（HTTP 404），请检查地址');
      }
      return DeployResult.failure('部署平台返回 HTTP ${resp.statusCode}');
    } on TimeoutException {
      return DeployResult.failure('请求超时（${_timeout.inSeconds} 秒）');
    } on SocketException catch (e) {
      return DeployResult.failure('网络不可达：${e.message}');
    } catch (e) {
      return DeployResult.failure('$e');
    } finally {
      client.close(force: true);
    }
  }

  /// 生成默认的 commit message。
  ///
  /// 格式：`更新文章：标题1、标题2` 或 `更新 3 个文件`。
  /// 比 `update` 这种无意义 message 好 —— 以后在 GitHub 网页上翻历史时
  /// 能一眼看出这次改了什么。
  static String suggestCommitMessage(List<String> changedPaths) {
    if (changedPaths.isEmpty) return '更新站点内容';

    // 优先从 content 目录下的 md 文件名推标题
    final titles = <String>[];
    for (final path in changedPaths) {
      final name = path.split('/').last;
      if (!name.endsWith('.md')) continue;
      var t = name.substring(0, name.length - 3);
      // 去掉常见的日期前缀，如 20240501-hello
      t = t.replaceFirst(RegExp(r'^\d{8}-'), '');
      if (t.isNotEmpty) titles.add(t);
    }

    if (titles.isEmpty) {
      final n = changedPaths.length;
      return n == 1 ? '更新 ${changedPaths.first}' : '更新 $n 个文件';
    }
    if (titles.length == 1) return '更新文章：${titles.first}';
    if (titles.length <= 3) {
      return '更新文章：${titles.join('、')}';
    }
    return '更新文章：${titles.take(2).join('、')} 等 ${titles.length} 篇';
  }
}