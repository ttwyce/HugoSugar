import 'dart:async';

import 'package:http/http.dart' as http;

import '../../note/note.dart';
import 'ai_tool.dart';
import '../memory_store.dart';
import 'html_text.dart';
import 'page_decoder.dart';
import 'path_guard.dart';

/// 抓取网页正文并转成纯文本。
///
/// 规格里的护栏全部落实在这一个类里：
/// 只 GET、只 https、≤512KB、15s、≤3 跳重定向且每跳重验私网。
class UrlFetcher {
  UrlFetcher({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// 单页上限，超出截断。防大文件拖爆上下文
  static const maxBytes = 512 * 1024;

  /// 单次请求超时
  static const timeout = Duration(seconds: 15);

  /// 最多跳几次重定向
  static const maxRedirects = 3;

  void dispose() => _client.close();

  Future<FetchResult> fetch(String rawUrl) async {
    Uri uri;
    try {
      uri = Uri.parse(rawUrl.trim());
    } catch (_) {
      throw FetchError('网址格式不对');
    }

    // 用户常忘记写协议
    if (!uri.hasScheme) {
      uri = Uri.parse('https://${rawUrl.trim()}');
    }

    var current = uri;
    for (var hop = 0; hop <= maxRedirects; hop++) {
      // 关键：每跳都校验，否则 302 到 127.0.0.1 就能绕过第一关
      final deny = validateFetchUrl(current);
      if (deny != null) throw FetchError(deny);

      http.StreamedResponse res;
      try {
        res = await _client
            .send(
              http.Request('GET', current)
                ..headers['User-Agent'] = 'HugoSugar/1.0 (+https://github.com)',
            )
            .timeout(timeout);
      } on TimeoutException {
        throw FetchError('请求超时（15 秒）');
      } catch (e) {
        throw FetchError('无法访问：$e');
      }

      // 重定向：手动跟，才能每跳校验
      if (res.statusCode >= 300 && res.statusCode < 400) {
        final loc = res.headers['location'];
        if (loc == null || loc.isEmpty) {
          throw FetchError('服务器返回重定向但没有目标地址');
        }
        final next = current.resolve(loc);
        // 主动排空响应体，避免连接泄漏
        try {
          await res.stream.drain<void>();
        } catch (_) {}
        current = next;
        continue;
      }

      if (res.statusCode != 200) {
        throw FetchError('服务器返回 ${res.statusCode}');
      }

      final bytes = await _readLimited(res);
      final contentType = res.headers['content-type'] ?? '';

      // 只处理文本类；二进制（PDF/图片）直接说清楚，
      // 否则解析出一堆乱码回灌给模型，比不抓还糟
      if (contentType.isNotEmpty &&
          !contentType.contains('text') &&
          !contentType.contains('json') &&
          !contentType.contains('xml') &&
          !contentType.contains('html')) {
        throw FetchError('这个地址不是网页（$contentType），无法读取');
      }

      final body = PageDecoder.decode(bytes, contentType: contentType);
      final isHtml =
          contentType.contains('html') ||
          body.trimLeft().toLowerCase().startsWith('<!doctype') ||
          body.trimLeft().toLowerCase().startsWith('<html');

      final title = isHtml ? guessTitle(body) : '';
      final text = isHtml ? htmlToText(body) : body;

      return FetchResult(
        url: current.toString(),
        title: title,
        text: text,
        truncated: bytes.length >= maxBytes,
      );
    }

    throw FetchError('重定向次数过多');
  }

  Future<List<int>> _readLimited(http.StreamedResponse res) async {
    final chunks = <int>[];
    await for (final c in res.stream.timeout(timeout)) {
      chunks.addAll(c);
      if (chunks.length >= maxBytes) break;
    }
    if (chunks.length > maxBytes) {
      return chunks.sublist(0, maxBytes);
    }
    return chunks;
  }
}

class FetchResult {
  const FetchResult({
    required this.url,
    required this.title,
    required this.text,
    required this.truncated,
  });

  final String url;
  final String title;
  final String text;
  final bool truncated;

  /// 回灌给模型的文本：加标题、限制总长
  String toPrompt({int maxChars = 12000}) {
    final buf = StringBuffer();
    if (title.isNotEmpty) buf.writeln('标题：$title');
    buf.writeln('来源：$url');
    buf.writeln();
    final body = text.length > maxChars
        ? '${text.substring(0, maxChars)}\n\n…（正文过长已截断）'
        : text;
    buf.write(body);
    return buf.toString();
  }
}

class FetchError implements Exception {
  FetchError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 构建 6 个工具。
///
/// 参数全部是**已经加载好的数据**（而不是 store 对象），
/// 这样工具本身是纯函数式的，能单测，也不会因为 IO 异常把循环搞崩。
class ToolRegistry {
  ToolRegistry({
    required this.listNotes,
    required this.readNote,
    required this.searchNotes,
    required this.listPosts,
    required this.readPost,
    required this.writePost,
    required this.contentDirAbs,
    this.fetcher,
    this.memoryStore,
    this.disabledTools = const [],
  });

  /// 提供当前可读的想法（已排除回收站）
  final List<Note> Function() listNotes;
  final Note? Function(String id) readNote;

  /// 供未来扩展；当前用 listNotes 做关键词过滤
  final List<Note> Function(String keyword) searchNotes;

  /// 列出站点内文章（相对路径 + 标题）
  final List<({String path, String title})> Function() listPosts;
  final Future<String?> Function(String path) readPost;

  /// 实际写盘。由调用方负责备份与回滚。
  final Future<void> Function(String relPath, String content) writePost;

  /// 站点内容目录的绝对路径，供 PathGuard 校验
  final String contentDirAbs;

  final UrlFetcher? fetcher;

  /// 记忆库。为 null 时三个记忆工具不注册 ——
  /// 比注册了再返回「功能未启用」更干净：模型看不到工具就不会去试。
  final MemoryStore? memoryStore;

  /// 被用户关掉的工具名。
  ///
  /// 这些工具不会出现在 schema 里。用名字而不是索引，
  /// 因为工具列表会变化，索引会错位。
  final List<String> disabledTools;

  /// 网页缓存：同 URL 24h 复用，避免多轮对话反复抓同一页
  final Map<String, _CachedPage> _cache = {};

  List<AiTool> build() {
    final all = _buildAll();
    if (disabledTools.isEmpty) return all;
    final off = disabledTools.toSet();
    return all.where((t) => !off.contains(t.name)).toList();
  }

  List<AiTool> _buildAll() {
    return [
      AiTool(
        name: 'list_notes',
        description:
            '列出用户的想法（笔记）。可用分类或关键词过滤，'
            '返回 id、标题和内容摘要。想了解用户有什么素材时先调这个。',
        parameters: objectSchema(
          properties: {
            'keyword': stringProp('可选，按关键词过滤标题和正文'),
            'limit': intProp('最多返回几条，默认 20'),
          },
        ),
        execute: _execListNotes,
      ),
      AiTool(
        name: 'read_note',
        description: '读取某条想法的完整内容。先用 list_notes 拿到 id。',
        parameters: objectSchema(
          properties: {'id': stringProp('想法的 id')},
          required: ['id'],
        ),
        execute: _execReadNote,
      ),
      AiTool(
        name: 'search_notes',
        description:
            '在所有想法里做关键词全文搜索，返回命中的想法和上下文片段。'
            '需要找具体素材、术语、过往记录时用。',
        parameters: objectSchema(
          properties: {'keyword': stringProp('要搜索的关键词')},
          required: ['keyword'],
        ),
        execute: _execSearchNotes,
      ),
      AiTool(
        name: 'read_post',
        description:
            '读取站点里已有文章的完整内容（含 Front Matter）。'
            '写新文章前先看几篇，能学到用户的格式和文风。',
        parameters: objectSchema(
          properties: {
            'path': stringProp('文章的相对路径（相对 content 目录），如 posts/hello.md'),
          },
          required: ['path'],
        ),
        execute: _execReadPost,
      ),
      AiTool(
        name: 'write_post',
        description:
            '把文章写入站点。会先让用户看到 Diff 并确认，'
            '用户确认后才真正落盘。内容必须包含完整的 Front Matter。',
        parameters: objectSchema(
          properties: {
            'path': stringProp(
              '相对 content 目录的路径，如 posts/my-post.md，必须以 .md 结尾',
            ),
            'content': stringProp('完整的文件内容，含 Front Matter 和正文'),
          },
          required: ['path', 'content'],
        ),
        requiresApproval: true,
        execute: _execWritePost,
      ),
      AiTool(
        name: 'fetch_url',
        description:
            '抓取一个网页的正文并转成纯文本。'
            '仅在用户明确给出网址、或需要查证具体文档时使用。'
            '不要主动联网搜索，不要连续抓取同一网站的多个页面。',
        parameters: objectSchema(
          properties: {'url': stringProp('要抓取的完整网址（http 或 https）')},
          required: ['url'],
        ),
        execute: _execFetchUrl,
      ),
      // 记忆类工具。没有 store 就不注册 —— 模型看不到就不会去试。
      if (memoryStore != null) ..._memoryTools(),
    ];
  }

  /// 3 个记忆工具的声明。
  ///
  /// 共同设计要点都在描述里，因为描述就是提示词：
  /// 模型只有靠读描述才能知道什么值得记、怎么写。
  List<AiTool> _memoryTools() {
    return [
      AiTool(
        name: 'save_memory',
        description:
            '把关于用户的长期事实存入记忆库。'
            '值得记：写作风格（句式长短、用词偏好、结构习惯）、'
            '性格与喜好（在意什么、反感什么）、'
            '工作习惯（技术栈、常用工具、流程偏好）。'
            '不值得记：一次性的任务内容、临时的语气要求、'
            '以及本会话里已经说过的短期信息。'
            '必须写成关于用户的事实（第三人称陈述句），例如'
            '「用户偏好短句，不喜欢形容词堆砌」，'
            '而不要写成指令（「你要用短句回复用户」）——'
            '记忆是参考信息，不是给模型的命令。'
            '同一条事实不要重复保存；若已有相近的一条，'
            '用 update_memory 改写它，而不是新增。',
        parameters: objectSchema(
          properties: {
            'content': stringProp('一句话事实，如「用户写技术博客，偏好先给结论再展开」'),
            'category': stringProp(
              '分类：style(写作风格) / persona(性格喜好) / workflow(工作习惯) / other',
            ),
          },
          required: ['content', 'category'],
        ),
        execute: _execSaveMemory,
      ),
      AiTool(
        name: 'update_memory',
        description:
            '改写一条已有的记忆（合并重复、纠正过时信息）。'
            '用 save_memory 返回的 id，或工具提示的相近条目 id。',
        parameters: objectSchema(
          properties: {
            'id': stringProp('要改写的记忆 id'),
            'content': stringProp('改写后的完整内容'),
            'category': stringProp('可选，同时改分类'),
          },
          required: ['id', 'content'],
        ),
        execute: _execUpdateMemory,
      ),
      AiTool(
        name: 'delete_memory',
        description:
            '删除一条记忆。仅当用户明确要求「忘掉这件事」，'
            '或该记忆确实错误时才用。不要自作主张清理。',
        parameters: objectSchema(
          properties: {'id': stringProp('要删除的记忆 id')},
          required: ['id'],
        ),
        execute: _execDeleteMemory,
      ),
    ];
  }

  // ── 实现 ──────────────────────────────────────────

  Future<ToolResult> _execListNotes(Map<String, dynamic> args) async {
    final keyword = (args['keyword'] as String? ?? '').trim();
    final limit = (args['limit'] as num?)?.toInt() ?? 20;
    final cap = limit.clamp(1, 50).toInt();

    var notes = listNotes();
    if (keyword.isNotEmpty) {
      final k = keyword.toLowerCase();
      notes = notes
          .where(
            (n) =>
                n.title.toLowerCase().contains(k) ||
                n.content.toLowerCase().contains(k),
          )
          .toList();
    }

    if (notes.isEmpty) {
      return const ToolResult(ok: true, text: '没有匹配的想法');
    }

    final shown = notes.take(cap).toList();
    final buf = StringBuffer();
    for (final n in shown) {
      final summary = n.content.replaceAll('\n', ' ').trim();
      final snippet = summary.length > 80
          ? '${summary.substring(0, 80)}…'
          : summary;
      buf.writeln('- id: ${n.id}');
      buf.writeln('  标题: ${n.title.isEmpty ? '（无标题）' : n.title}');
      buf.writeln('  摘要: $snippet');
    }
    if (notes.length > cap) {
      buf.writeln('（共 ${notes.length} 条，只显示前 $cap 条）');
    }

    return ToolResult(
      ok: true,
      text: buf.toString().trim(),
      detail: '列出 ${shown.length} 条想法',
    );
  }

  Future<ToolResult> _execReadNote(Map<String, dynamic> args) async {
    final id = (args['id'] as String? ?? '').trim();
    if (id.isEmpty) return ToolResult.fail('缺少 id');

    final n = readNote(id);
    if (n == null) return ToolResult.fail('找不到 id 为 $id 的想法');

    final body = StringBuffer();
    body.writeln('标题：${n.title.isEmpty ? '（无标题）' : n.title}');
    body.writeln();
    body.write(n.content);

    return ToolResult(
      ok: true,
      text: body.toString(),
      detail: '读取想法「${n.title}」',
    );
  }

  Future<ToolResult> _execSearchNotes(Map<String, dynamic> args) async {
    final keyword = (args['keyword'] as String? ?? '').trim();
    if (keyword.isEmpty) return ToolResult.fail('缺少关键词');

    final hits = searchNotes(keyword);
    if (hits.isEmpty) {
      return ToolResult(ok: true, text: '没有找到包含「$keyword」的想法');
    }

    final buf = StringBuffer();
    for (final n in hits.take(10)) {
      buf.writeln('- id: ${n.id} 标题: ${n.title}');
      // 给出命中位置的上下文，比只给标题有用
      final idx = n.content.toLowerCase().indexOf(keyword.toLowerCase());
      if (idx != -1) {
        final start = (idx - 40).clamp(0, n.content.length);
        final end = (idx + keyword.length + 60).clamp(0, n.content.length);
        final frag = n.content
            .substring(start, end)
            .replaceAll('\n', ' ')
            .trim();
        buf.writeln('  片段: …$frag…');
      }
    }

    return ToolResult(
      ok: true,
      text: buf.toString().trim(),
      detail: '搜索「$keyword」，命中 ${hits.length} 条',
    );
  }

  Future<ToolResult> _execReadPost(Map<String, dynamic> args) async {
    final path = (args['path'] as String? ?? '').trim();
    if (path.isEmpty) return ToolResult.fail('缺少 path');

    final posts = listPosts();
    if (posts.isEmpty) {
      return const ToolResult(ok: true, text: '站点里还没有文章');
    }

    // 允许只给文件名，用户/模型不一定记得完整相对路径
    final normalized = path.replaceAll('\\', '/');
    final match = posts.where((p) {
      return p.path == normalized ||
          p.path.endsWith('/$normalized') ||
          p.path == 'content/$normalized';
    }).toList();

    if (match.isEmpty) {
      final listing = posts.take(15).map((p) => '- ${p.path}').join('\n');
      return ToolResult(
        ok: false,
        text: '找不到文章 $path。现有文章：\n$listing',
        detail: '未找到 $path',
      );
    }

    final content = await readPost(match.first.path);
    if (content == null) {
      return ToolResult.fail('读取 ${match.first.path} 失败');
    }

    return ToolResult(
      ok: true,
      text: content,
      detail: '读取文章 ${match.first.path}',
    );
  }

  Future<ToolResult> _execWritePost(Map<String, dynamic> args) async {
    final path = (args['path'] as String? ?? '').trim();
    final content = args['content'] as String? ?? '';

    final deny = validatePostPath(contentDirAbs: contentDirAbs, relPath: path);
    if (deny != null) return ToolResult.fail(deny);
    if (content.trim().isEmpty) return ToolResult.fail('内容为空');

    await writePost(path, content);
    return ToolResult(
      ok: true,
      text: '已写入 $path（${content.length} 字符）',
      detail: '写入 $path',
    );
  }

  Future<ToolResult> _execFetchUrl(Map<String, dynamic> args) async {
    final url = (args['url'] as String? ?? '').trim();
    if (url.isEmpty) return ToolResult.fail('缺少 url');

    final f = fetcher;
    if (f == null) return ToolResult.fail('当前没有可用的网络抓取');

    // 缓存 24h
    final cached = _cache[url];
    if (cached != null && !cached.isStale) {
      return ToolResult(ok: true, text: cached.text, detail: '读取网页（缓存）$url');
    }

    try {
      final r = await f.fetch(url);
      final prompt = r.toPrompt();
      _cache[url] = _CachedPage(prompt, DateTime.now());
      return ToolResult(
        ok: true,
        text: prompt,
        detail: '读取网页 ${r.title.isEmpty ? url : r.title}',
      );
    } on FetchError catch (e) {
      return ToolResult.fail(e.message);
    } catch (e) {
      return ToolResult.fail('抓取失败：$e');
    }
  }

  // ── 记忆 ──────────────────────────────────────────

  Future<ToolResult> _execSaveMemory(Map<String, dynamic> args) async {
    final store = memoryStore;
    if (store == null) return ToolResult.fail('记忆库未启用');

    final content = (args['content'] as String? ?? '').trim();
    final category = (args['category'] as String? ?? '').trim();
    if (content.isEmpty) return ToolResult.fail('内容为空');

    // 判重：有相近的就提示模型去 update，而不是新增一条同义句。
    //
    // 不直接替它合并 —— 合并需要判断「新信息是否覆盖旧的」，
    // 那是模型的活。工具只负责把「已经有相近的」这个事实告诉它。
    final similar = store.findSimilar(content);
    if (similar != null) {
      return ToolResult(
        ok: false,
        text:
            '已有相近的记忆（id: ${similar.id}）：${similar.content}\n'
            '如需补充或纠正，请调用 update_memory 改写它。',
        detail: '与已有记忆重复，未写入',
      );
    }

    // 矛盾检测：已有一条「意思相反」的记忆。
    //
    // 不自动昵名合并也不静默覆盖：哪一条对，只有用户知道。
    // 把冲突摆到模型面前，让它去问用户或改写旧条目。
    final conflict = store.findConflict(content);
    if (conflict != null) {
      return ToolResult(
        ok: false,
        text:
            '发现可能矛盾的已有记忆（id: ${conflict.id}）：${conflict.content}\n'
            '这条与它意思相反。请先确认哪一个才是对的：'
            '若新信息才对，用 update_memory 改写它；'
            '若两者适用于不同情境，把语境写清楚后再保存。',
        detail: '与已有记忆矛盾，未写入',
      );
    }

    final added = await store.add(content: content, category: category);
    if (added == null) {
      return ToolResult(
        ok: false,
        text:
            '记忆库已满（${MemoryStore.maxCount} 条）。\n'
            '请先合并或删除价值最低的几条，再保存这条。',
        detail: '记忆库已满，未写入',
      );
    }

    return ToolResult(
      ok: true,
      text: '已记住（id: ${added.id}）',
      detail: '记住：$content',
    );
  }

  Future<ToolResult> _execUpdateMemory(Map<String, dynamic> args) async {
    final store = memoryStore;
    if (store == null) return ToolResult.fail('记忆库未启用');

    final id = (args['id'] as String? ?? '').trim();
    final content = (args['content'] as String? ?? '').trim();
    final category = (args['category'] as String? ?? '').trim();
    if (id.isEmpty) return ToolResult.fail('缺少 id');
    if (content.isEmpty) return ToolResult.fail('内容为空');

    final ok = await store.update(
      id,
      content: content,
      category: category.isEmpty ? null : category,
    );
    if (!ok) return ToolResult.fail('找不到 id 为 $id 的记忆');

    return ToolResult(ok: true, text: '已更新记忆 $id', detail: '更新记忆：$content');
  }

  Future<ToolResult> _execDeleteMemory(Map<String, dynamic> args) async {
    final store = memoryStore;
    if (store == null) return ToolResult.fail('记忆库未启用');

    final id = (args['id'] as String? ?? '').trim();
    if (id.isEmpty) return ToolResult.fail('缺少 id');

    final ok = await store.remove(id);
    if (!ok) return ToolResult.fail('找不到 id 为 $id 的记忆');

    return ToolResult(ok: true, text: '已删除记忆 $id', detail: '删除一条记忆');
  }
}

class _CachedPage {
  _CachedPage(this.text, this.at);

  final String text;
  final DateTime at;

  bool get isStale => DateTime.now().difference(at) > const Duration(hours: 24);
}
