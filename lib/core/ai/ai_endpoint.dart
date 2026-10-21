import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 思考模式的实现协议。
///
/// ## 为什么这是个枚举而不是一个开关
///
/// 各家「让模型思考」的方式完全不同，没有统一字段：
///
/// | 服务 | 怎么开启 | 怎么返回 |
/// |---|---|---|
/// | DeepSeek-R1 及兼容实现 | **不用请求**，直接就有 | `delta.reasoning_content` |
/// | Qwen3（混合模型） | `enable_thinking: true` | `delta.reasoning_content` |
/// | OpenAI o1/o3 | `reasoning_effort: "high"` | **不返回**思考内容 |
/// | 普通模型（V3/4o） | 不支持 | — |
///
/// 所以「我想看思考过程」这件事，必须翻译成**这个端点认得的请求**，
/// 否则就会出现「UI 上开了开关但模型根本没思考」的情况 ——
/// 混合模型（如 Qwen3）默认走非思考路径，不发参数它就不思考。
enum ThinkingMode {
  /// 关闭。不发任何思考相关参数。
  none('none', '关闭'),

  /// 只解析不复请求：模型本身总是思考（如 DeepSeek-R1 官方端点），
  /// 我们不发送任何参数，只负责把 reasoning_content 显示出来。
  ///
  /// 对 R1 这类纯推理模型，发 `enable_thinking` 反而有些中转站会报
  /// 400（未知字段），所以「只看不请求」单独列出来。
  parseOnly('parse_only', '总是思考（R1 等）'),

  /// 发 `enable_thinking: true`（Qwen3、硅基流动的混合模型）。
  enableThinking('enable_thinking', '按需开启（enable_thinking）'),

  /// 发 `reasoning_effort`（OpenAI o 系列）。
  ///
  /// 注意：o1/o3 **不返回**思考内容，所以选这个只影响推理强度，
  /// 界面上不会出现思考过程。
  reasoningEffort('reasoning_effort', '推理强度（o1/o3）');

  const ThinkingMode(this.id, this.label);

  final String id;
  final String label;

  /// 是否应该显示思考区（parseOnly / enableThinking 才可能返回内容）
  bool get showsReasoning => this == parseOnly || this == enableThinking;

  static ThinkingMode fromId(String? id) {
    for (final m in values) {
      if (m.id == id) return m;
    }
    return none;
  }
}

/// 一个 OpenAI 兼容端点。
///
/// 为什么用「端点」而不是「服务商」：
/// 用户的需求是「可以接入多个端点」。OpenAI、DeepSeek、通义、Ollama、
/// 各种中转站都实现了 `/chat/completions`，唯一差别是 [baseUrl] 和模型名。
/// 把它们统一成「端点 = baseUrl + 模型 + 一份 key」，一套代码全覆盖。
class AiEndpoint {
  const AiEndpoint({
    required this.id,
    required this.name,
    required this.baseUrl,
    this.model = '',
    this.keyHint = '',
    this.thinkingMode = ThinkingMode.none,
  });

  /// 内部标识，生成后不变。key 与它绑定，改名不会丢 key。
  final String id;

  /// 显示名，用户可改
  final String name;

  /// 形如 `https://api.openai.com/v1`（不含 `/chat/completions`）
  final String baseUrl;

  /// 默认模型名。留空则必须从模型列表里选。
  final String model;

  /// 打码后的 key 片段，仅用于界面展示「已配置哪把 key」
  final String keyHint;

  /// 思考模式。见 [ThinkingMode]。
  ///
  /// 配在端点上而不是全局：同一个 App 可能同时接 DeepSeek（支持
  /// reasoning_content）和一个普通端点（不支持），协议差异跟的是
  /// 端点实现的形态，不是模型名。
  final ThinkingMode thinkingMode;

  AiEndpoint copyWith({
    String? name,
    String? baseUrl,
    String? model,
    String? keyHint,
    ThinkingMode? thinkingMode,
  }) {
    return AiEndpoint(
      id: id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
      keyHint: keyHint ?? this.keyHint,
      thinkingMode: thinkingMode ?? this.thinkingMode,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'baseUrl': baseUrl,
        'model': model,
        'keyHint': keyHint,
        'thinkingMode': thinkingMode.id,
      };

  static AiEndpoint fromJson(Map<String, dynamic> j) => AiEndpoint(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        baseUrl: j['baseUrl'] as String? ?? '',
        model: j['model'] as String? ?? '',
        keyHint: j['keyHint'] as String? ?? '',
        thinkingMode: ThinkingMode.fromId(j['thinkingMode'] as String?),
      );

  /// 拼出具体的接口地址。
  ///
  /// 用户很可能直接粘贴 `https://api.xxx.com/v1/` 或
  /// `https://api.xxx.com/v1/chat/completions`，这里统一收拾干净，
  /// 不要求他们理解路径层级。
  Uri uri(String path) {
    var base = baseUrl.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    // 用户把完整 chat/completions 地址填进来的情况
    for (final suffix in ['/chat/completions', '/models']) {
      if (base.endsWith(suffix)) {
        base = base.substring(0, base.length - suffix.length);
      }
    }
    return Uri.parse('$base/$path');
  }
}

/// 端点集合 + 当前选中项。
class AiConfig {
  const AiConfig({this.endpoints = const [], this.activeId = ''});

  final List<AiEndpoint> endpoints;
  final String activeId;

  AiEndpoint? get active {
    for (final e in endpoints) {
      if (e.id == activeId) return e;
    }
    // 选中的被删掉了：回落到第一个，避免界面空着什么都选不了
    return endpoints.isEmpty ? null : endpoints.first;
  }

  bool get isEmpty => endpoints.isEmpty;

  AiConfig copyWith({List<AiEndpoint>? endpoints, String? activeId}) {
    return AiConfig(
      endpoints: endpoints ?? this.endpoints,
      activeId: activeId ?? this.activeId,
    );
  }

  Map<String, dynamic> toJson() => {
        'endpoints': endpoints.map((e) => e.toJson()).toList(),
        'activeId': activeId,
      };

  static AiConfig fromJson(Map<String, dynamic> j) {
    final raw = j['endpoints'];
    final list = <AiEndpoint>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          final ep = AiEndpoint.fromJson(Map<String, dynamic>.from(e));
          // 丢弃没有 baseUrl 的坏数据，避免后续每次请求都失败
          if (ep.baseUrl.trim().isNotEmpty) list.add(ep);
        }
      }
    }
    return AiConfig(
      endpoints: list,
      activeId: j['activeId'] as String? ?? '',
    );
  }
}

/// 端点配置的持久化。
///
/// 放 `<appSupport>/ai/config.json`。**不含任何 key** ——
/// key 单独存，见 [AiKeyStore]。
class AiEndpointStore {
  AiEndpointStore(this._file);

  final File _file;

  static Future<AiEndpointStore> open() async {
    final dir = await getApplicationSupportDirectory();
    final ai = Directory('${dir.path}/ai');
    return AiEndpointStore(File('${ai.path}/config.json'));
  }

  Future<AiConfig> load() async {
    try {
      if (!await _file.exists()) return const AiConfig();
      final s = await _file.readAsString();
      if (s.trim().isEmpty) return const AiConfig();
      final j = jsonDecode(s);
      if (j is! Map) return const AiConfig();
      return AiConfig.fromJson(Map<String, dynamic>.from(j));
    } catch (_) {
      // 文件损坏就当作没配置，不让用户卡在启动崩溃上
      return const AiConfig();
    }
  }

  Future<void> save(AiConfig cfg) async {
    await _file.parent.create(recursive: true);
    await _file.writeAsString(jsonEncode(cfg.toJson()), flush: true);
  }
}

/// API key 的本地存储，**每个端点一把**。
///
/// 为什么不复用 TokenStore：
/// - GitHub 令牌是「接入站点时填一次」，AI key 是「换端点就要改」
/// - 共用一个文件时，清空一个会误伤另一个
///
/// 权限模型与 TokenStore 完全一致（应用私有目录 + 0600）。
/// 没用 flutter_secure_storage 的原因见 token_store.dart 的注释：
/// 它是原生插件，会在 ARM64 proot 环境里重新引入构建风险。
class AiKeyStore {
  AiKeyStore(this._dir);

  final Directory _dir;

  static Future<AiKeyStore> open() async {
    final dir = await getApplicationSupportDirectory();
    return AiKeyStore(Directory('${dir.path}/ai/keys'));
  }

  File _fileFor(String endpointId) => File('${_dir.path}/$endpointId');

  Future<String?> read(String endpointId) async {
    try {
      final f = _fileFor(endpointId);
      if (!await f.exists()) return null;
      final s = (await f.readAsString()).trim();
      return s.isEmpty ? null : s;
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String endpointId, String key) async {
    final k = key.trim();
    if (k.isEmpty) return;
    try {
      await _dir.create(recursive: true);
      final f = _fileFor(endpointId);
      // 先建文件 → 收紧权限 → 再写内容。
      // 顺序反了会有一小段时间是默认权限，同用户的其他进程可读。
      if (!await f.exists()) {
        await f.create(recursive: false);
      }
      try {
        await Process.run('chmod', ['600', f.path]);
      } catch (_) {
        // Dart 没有 chmod API，只能走系统命令；失败不阻断
      }
      await f.writeAsString(k, flush: true);
    } catch (_) {
      // 写失败不致命，用户下次重新输入
    }
  }

  Future<void> delete(String endpointId) async {
    try {
      final f = _fileFor(endpointId);
      if (await f.exists()) await f.delete();
    } catch (_) {
      // 忽略
    }
  }

  /// 打码成可展示的短串：`sk-ab••••••xyz9`
  static String mask(String key) {
    final k = key.trim();
    if (k.length <= 10) return '••••••';
    return '${k.substring(0, 5)}••••${k.substring(k.length - 4)}';
  }
}
