import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as pkg;

/// 路径护栏：限制 AI 只能写文章目录里的 `.md` 文件。
///
/// 规格里砍掉了整套 Safety 体系（因为工具集里没有 run_command /
/// delete_path），剩下的唯一风险面就是「AI 往哪儿写」。
/// 所以只需要这一个函数。
///
/// 返回 null 表示通过，否则返回拒绝原因（会原样回灌给模型）。
String? validatePostPath({
  required String contentDirAbs,
  required String relPath,
}) {
  final raw = relPath.trim();
  if (raw.isEmpty) return '路径不能为空';

  // 统一分隔符：Windows 风格的 `\` 在这里一律当路径分隔符处理，
  // 否则 `..\..\etc\x.md` 能绕过检查
  final norm = pkg.normalize(raw.replaceAll('\\', '/'));

  if (pkg.isAbsolute(norm)) return '不允许绝对路径';
  if (norm.startsWith('..')) return '路径越界';

  // 允许写子目录（如 posts/2026/x.md），但必须是 .md
  if (!norm.toLowerCase().endsWith('.md')) return '只允许 .md 文件';

  final abs = pkg.normalize(pkg.join(contentDirAbs, norm));
  if (!pkg.isWithin(contentDirAbs, abs)) return '路径越界';

  // 显式再排一次：pkg.isWithin 对同路径返回 true，但 abs == dir 时
  // 拼接结果是目录本身，写下去会失败
  if (abs == pkg.normalize(contentDirAbs)) return '路径越界';

  return null;
}

/// fetch_url 的地址校验（SSRF 防护）。
///
/// **必须在每一跳重定向后重新调用**，否则攻击方式是：
/// 公网 URL → 302 到 `http://127.0.0.1:8080`。
/// 只在第一跳检查的话这个绕法完全有效。
///
/// ## 为什么允许 http
///
/// 早期这里是 `if (uri.scheme != 'https') return '只允许 https'`。
/// 结果是大量 2000 年代的中文站点（比如各种老资料站、BBS 存档）
/// 完全抓不了 —— 它们只提供 http，没有证书，也不会升级。
///
/// **关键认识：SSRF 的风险不在协议，在目标地址。**
/// 真正危险的是「让服务器去访问自己内网的 127.0.0.1 / 10.x / 192.168.x」，
/// 而这一点由下面的 [isPrivateAddress] 独立负责，与 http/https 无关。
/// 只认 https 是一种「看起来安全」的省事做法：
/// 攻击者手上只要有一个 https 域名，照样能打；
/// 而正常用户抓老站则被完全挡住。
///
/// 明文传输的残留风险（内容被中间人篡改）对「抓一篇文章给模型看」
/// 这个场景可以接受 —— 模型本来就会被告知不要相信网页里的指令。
///
/// 返回 null 表示通过。
String? validateFetchUrl(Uri uri) {
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    return '只支持 http / https';
  }

  final host = uri.host.toLowerCase();
  if (host.isEmpty) return '地址缺少主机名';

  // 直接给 IP 的情况
  final ip = InternetAddress.tryParse(host);
  if (ip != null) {
    if (isPrivateAddress(ip)) return '不允许访问内网地址';
    return null;
  }

  // 明显的内网主机名
  if (host == 'localhost' || host.endsWith('.localhost')) {
    return '不允许访问内网地址';
  }
  if (host.endsWith('.local') || host.endsWith('.internal')) {
    return '不允许访问内网地址';
  }

  // 形如 0x7f.0.0.1 / 2130706433 这类十进制/十六进制 IP 伪装。
  // 这些最终会被解析成私网地址，但字符串层面看不出来，
  // 所以对「全是数字和点」的主机名直接拒绝。
  if (RegExp(r'^[0-9a-fx.]+$').hasMatch(host) && host.contains('.')) {
    return '不允许使用数字形式的主机名';
  }

  return null;
}

/// 判断是否私网 / 保留地址。
bool isPrivateAddress(InternetAddress ip) {
  if (ip.isLoopback) return true;
  if (ip.isLinkLocal) return true;

  final raw = ip.rawAddress;
  if (ip.type == InternetAddressType.IPv4) {
    if (raw.length != 4) return true;
    final a = raw[0];
    final b = raw[1];

    if (a == 10) return true; // 10/8
    if (a == 172 && b >= 16 && b <= 31) return true; // 172.16/12
    if (a == 192 && b == 168) return true; // 192.168/16
    if (a == 169 && b == 254) return true; // 169.254/16
    if (a == 127) return true; // 127/8
    if (a == 0) return true; // 0/8
    if (a >= 224) return true; // 组播 + 保留
    return false;
  }

  // IPv6
  if (raw.length != 16) return true;
  // ::1 已被 isLoopback 覆盖；再挡 fc00::/7（唯一本地地址）
  if ((raw[0] & 0xFE) == 0xFC) return true;

  // IPv4 映射地址 ::ffff:a.b.c.d —— 必须解出内层再判一次，
  // 否则 `https://[::ffff:127.0.0.1]/` 能绕过所有 IPv4 检查
  final isMapped =
      raw.sublist(0, 10).every((b) => b == 0) && raw[10] == 0xFF && raw[11] == 0xFF;
  if (isMapped) {
    final v4 = InternetAddress.fromRawAddress(
      Uint8List.fromList(raw.sublist(12)),
      type: InternetAddressType.IPv4,
    );
    return isPrivateAddress(v4);
  }

  return false;
}