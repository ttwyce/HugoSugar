import 'dart:convert';
import 'dart:typed_data';

import 'package:fast_gbk/fast_gbk.dart';

/// 网页字符集检测与解码。
///
/// ## 为什么需要这个文件
///
/// 之前 `UrlFetcher` 无脑 `utf8.decode(bytes, allowMalformed: true)`，
/// 于是所有非 UTF-8 的页面变成乱码。典型症状：
///
/// ```
/// 标题：ʥ���γ�--�����̽���: ��һ�� Ψһ�İ�ο
/// ```
///
/// 这不是「解码失败」，而是更糟的情况：`allowMalformed: true` 把非法
/// 字节全部替换成 `�`，**不抛异常、静默产出垃圾**，然后照常回灌给模型。
/// 模型拿到这种文本只会胡说，而用户完全不知道为什么。
///
/// ## 为什么不能只看 HTTP 头
///
/// 实测 `https://godoor.net/.../hdc01.htm` 的响应头是：
///
/// ```
/// content-type: text/html          ← 没有 charset！
/// ```
///
/// 真正的编码写在 HTML 内部：`<meta http-equiv="Content-Type"
/// content="text/html; charset=gb2312">`。
/// 只读响应头会漏掉大量 2000 年代的中文站点。
///
/// ## 检测顺序
///
/// 1. HTTP `Content-Type` 里的 `charset=`
/// 2. HTML 里的 `<meta charset>` / `<meta http-equiv>`
/// 3. XML 声明 `<?xml encoding=...?>`
/// 4. UTF-8 BOM
/// 5. 字节启发式（合法的多字节 UTF-8 序列 → UTF-8，否则 GBK）
///
/// 顺序不能反：头部声明是服务器明说的，优先级最高；
/// 启发式只在前面全都没有时才用，它本质是猜测。
class PageDecoder {
  /// 把响应字节解成字符串。
  ///
  /// [contentType] 是 HTTP 响应头的 content-type 原文（可为空）。
  static String decode(List<int> bytes, {String contentType = ''}) {
    if (bytes.isEmpty) return '';

    final charset = detectCharset(bytes, contentType: contentType);
    return decodeAs(bytes, charset);
  }

  /// 检测字符集，返回规范化后的名字（小写）。
  ///
  /// 返回值示例：`utf-8`、`gbk`、`gb18030`、`big5`、`iso-8859-1`
  static String detectCharset(
    List<int> bytes, {
    String contentType = '',
  }) {
    // 1) HTTP 头
    final fromHeader = _charsetFromContentType(contentType);
    if (fromHeader != null) return _normalize(fromHeader);

    // 4) BOM 要早于 meta 检查：带 BOM 的页面几乎不可能被误标成 GBK，
    //    而 BOM 是比 meta 更硬的证据。
    final bom = _charsetFromBom(bytes);
    if (bom != null) return bom;

    // 2) / 3) 头部
    final fromHead = _charsetFromHtmlHead(bytes);
    if (fromHead != null) return _normalize(fromHead);

    // 5) 启发式
    return _looksLikeUtf8(bytes) ? 'utf-8' : 'gbk';
  }

  /// 按指定字符集解码。未知字符集回落到 UTF-8。
  static String decodeAs(List<int> bytes, String charset) {
    final cs = _normalize(charset);

    // 所有 GB 系（gb2312 / gbk / gb18030）统一用 GBK 解。
    //
    // 理由：GB2312 是 GBK 的子集，GB18030 是超集。用 GBK 解码器
    // 处理前两者不会出错，覆盖面还更大 —— 大量页面标着 gb2312
    // 但实际塞了 GBK 才有的字。GB18030 的四字节序列 GBK 解不了，
    // 但那种页面极少，且解出来是 � 而不是崩溃。
    if (_isGbFamily(cs)) {
      try {
        return gbk.decode(bytes, allowMalformed: true);
      } catch (_) {
        // fast_gbk 在极少数畸形输入上仍可能抛异常，兜一层
        return utf8.decode(bytes, allowMalformed: true);
      }
    }

    if (cs == 'utf-8' || cs == 'utf8') {
      return utf8.decode(bytes, allowMalformed: true);
    }

    // Big5（繁体中文站）与 latin1：Dart 没有内置解码器。
    // 先按 latin1 保底（单字节，永不失败），至少英文和结构完整。
    // 不引入更多依赖：Big5 的使用频率远低于 GBK，
    // 为一个边缘场景再加一个包不划算。
    if (cs == 'big5' || cs == 'big5-hkscs' || cs == 'cp950') {
      return _decodeSingleByteFallback(bytes);
    }

    return utf8.decode(bytes, allowMalformed: true);
  }

  static bool _isGbFamily(String cs) =>
      cs == 'gbk' ||
      cs == 'gb2312' ||
      cs == 'gb_2312-80' ||
      cs == 'gb18030' ||
      cs == 'cp936' ||
      // Windows 上「简体中文」的别名
      cs == 'x-gbk' ||
      cs == 'gb';

  // ── 各个来源 ────────────────────────────────────────

  /// 从 `text/html; charset=gb2312` 里取 charset
  static String? _charsetFromContentType(String contentType) {
    if (contentType.trim().isEmpty) return null;
    final m = RegExp(
      r'charset\s*=\s*["' "'" r']?\s*([a-zA-Z0-9_\-:.]+)',
      caseSensitive: false,
    ).firstMatch(contentType);
    return m?.group(1);
  }

  /// 从 BOM 判断
  static String? _charsetFromBom(List<int> b) {
    if (b.length >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF) {
      return 'utf-8';
    }
    // UTF-16 的 BOM：HTML 里出现得极少，但既然要检测就一起判掉，
    // 免得后面按 UTF-8 解出一堆 \u0000
    if (b.length >= 2) {
      if (b[0] == 0xFF && b[1] == 0xFE) return 'utf-16le';
      if (b[0] == 0xFE && b[1] == 0xFF) return 'utf-16be';
    }
    return null;
  }

  /// 在文档头部找 `<meta charset>` / `<?xml encoding=?>`。
  ///
  /// 为什么只扫前 4KB：`<meta>` 按规范必须在 head 里，
  /// 而 head 不会太长。全文件扫描在 512KB 页面上纯属浪费。
  static String? _charsetFromHtmlHead(List<int> bytes) {
    final head = bytes.length > 4096 ? bytes.sublist(0, 4096) : bytes;

    // 这里必须按单字节读，不能先 utf8.decode 再找 ——
    // 声明本身就是 ASCII，而正文可能是任意编码，
    // 先解码会把声明之外的部分弄成 �，虽然不影响正则匹配，
    // 但会给调试带来困扰。
    final ascii = String.fromCharCodes(
      head.map((b) => b < 128 ? b : 0x20), // 非 ASCII 一律换成空格
    );

    // <meta charset="gb2312">
    final direct = RegExp(
      r'<meta[^>]+charset\s*=\s*["' "'" r']?\s*([a-zA-Z0-9_\-:.]+)',
      caseSensitive: false,
    ).firstMatch(ascii);
    if (direct != null) return direct.group(1);

    // <?xml version="1.0" encoding="gb2312"?>
    final xml = RegExp(
      r'<\?xml[^>]+encoding\s*=\s*["' "'" r']\s*([a-zA-Z0-9_\-:.]+)',
      caseSensitive: false,
    ).firstMatch(ascii);
    return xml?.group(1);
  }

  /// 字节启发式：整段能否用 UTF-8 严格解码。
  ///
  /// 只做一件事：严格解码一遍，抛 FormatException 就说明不是 UTF-8。
  /// 这比统计字节区间可靠得多 —— 手写「高位字节比例」之类的规则
  /// 在短文本上误判率很高。
  static bool _looksLikeUtf8(List<int> bytes) {
    // 纯 ASCII 时 UTF-8 与 GBK 等价，随便当哪个都行
    var hasHigh = false;
    for (final b in bytes) {
      if (b >= 0x80) {
        hasHigh = true;
        break;
      }
    }
    if (!hasHigh) return true;

    try {
      utf8.decode(bytes);
      return true;
    } on FormatException {
      return false;
    }
  }

  /// 单字节兜底：把每个字节当 Latin-1 字符。
  ///
  /// 不会抛异常，英文与 HTML 结构能保住；中文会变成乱码，
  /// 但总好过整个抓取失败。
  static String _decodeSingleByteFallback(List<int> bytes) =>
      latin1.decode(Uint8List.fromList(bytes), allowInvalid: true);

  static String _normalize(String cs) =>
      cs.trim().toLowerCase().replaceAll('_', '-');
}