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
/// 返回 null 表示通过。
String? validateFetchUrl(Uri uri) {
  if (uri.scheme != 'https') return '只允许 https';

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