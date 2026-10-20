/// 增量解析 OpenAI 的 SSE 流。
///
/// ## 为什么不能一行一行读
///
/// SSE 的网络分片和文本行**不是一回事**：一个 `data: {...}` 可能被
/// 拆成两三个 TCP 包，也可能一个包里塞了好几行。所以必须自己缓冲，
/// 只在遇到 `\n\n`（事件分隔）时才产出，剩下的半截留着等下一个包。
///
/// 直接按 `\n` 切会偶发 JSON 解析失败 —— 而且这种失败在网速好的时候
/// 几乎复现不出来，非常难查。
class SseParser {
  final StringBuffer _buf = StringBuffer();

  /// 喂入一段原始文本，返回其中已经完整的 `data:` 载荷。
  ///
  /// 不含 `data: ` 前缀，已去掉首尾空白，空行和 `[DONE]` 会保留原样，
  /// 由调用方判断。
  List<String> push(String chunk) {
    _buf.write(chunk);
    final text = _buf.toString();

    final out = <String>[];
    var start = 0;

    // 事件以空行分隔；兼容 \r\n
    while (true) {
      final nl = text.indexOf('\n\n', start);
      final crnl = text.indexOf('\r\n\r\n', start);
      int sep;
      int sepLen;
      if (nl == -1 && crnl == -1) break;
      if (nl != -1 && (crnl == -1 || nl < crnl)) {
        sep = nl;
        sepLen = 2;
      } else {
        sep = crnl;
        sepLen = 4;
      }

      final event = text.substring(start, sep);
      start = sep + sepLen;

      for (final line in event.split('\n')) {
        final l = line.trimRight();
        if (l.isEmpty) continue;
        if (!l.startsWith('data:')) continue; // 忽略 event:/id:/:
        final payload = l.substring(5).trim();
        if (payload.isEmpty) continue;
        out.add(payload);
      }
    }

    // 只保留未处理完的尾巴
    final rest = text.substring(start);
    _buf.clear();
    _buf.write(rest);

    return out;
  }

  /// 流结束时把残留内容也吐出来（有的服务端末尾不发空行）
  List<String> flush() {
    final text = _buf.toString();
    _buf.clear();
    final out = <String>[];
    for (final line in text.split('\n')) {
      final l = line.trimRight();
      if (!l.startsWith('data:')) continue;
      final payload = l.substring(5).trim();
      if (payload.isEmpty) continue;
      out.add(payload);
    }
    return out;
  }
}