import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 思考档位（用户视角）。
///
/// ## 为什么是档位而不是「开/关」
///
/// 上一版只有「关闭 / 总是思考 / enable_thinking / reasoning_effort」，
/// 混了两件事：
///   1. 要不要思考（业务意图）
///   2. 用哪种协议表达（技术细节）
///
/// 用户在对话框里想的是「这次我要多想一点」，不该被要求理解
/// enable_thinking 和 reasoning_effort 的区别。所以拆成：
///
/// - ThinkingLevel：用户选的档位
/// - ThinkingProtocol：端点选的协议，决定档位怎么翻译成请求
enum ThinkingLevel {
  none('none', '关闭', '不进行内部推理，响应最快、成本最低'),
  low('low', '轻量', '少量 token 推理，适合快速查询、语法检查'),
  medium('medium', '平衡', '推理质量与延迟的平衡，日常任务默认'),
  high('high', '深度', '完整推理链，适合复杂问题、代码验证'),
  xhigh('xhigh', '极高', '最大算力，少数模型支持');

  const ThinkingLevel(this.id, this.label, this.description);

  final String id;
  final String label;
  final String description;

  bool get isThinking => this != none;

  static ThinkingLevel fromId(String? id) {
    for (final v in values) {
      if (v.id == id) return v;
    }
    return none;
  }

  /// 翻译成 reasoning_effort 的取值。
  ///
  /// o 系列只认 low/medium/high；xhigh 不在其列，
  /// 降级为 high 而不是报 400。
  String get effortValue => switch (this) {
    none => 'low',
    low => 'low',
    medium => 'medium',
    high => 'high',
    xhigh => 'high',
  };
}

/// 端点用哪种协议表达「思考」。
///
/// 这是技术细节，配在端点上；用户只在对话里选 ThinkingLevel。
enum ThinkingProtocol {
  /// 不发任何思考参数（GPT-4o / DeepSeek-V3 等）。
  /// 发未知字段可能 400，所以默认什么都不发。
  off('off', '不支持思考'),

  /// 模型本身总是思考（R1 官方端点）。
  /// 不发参数，只解析 reasoning_content。
  alwaysOn('always_on', '总是思考（R1 等）'),

  /// 布尔开关 enable_thinking: true/false。
  ///
  /// 没有档位概念：选 low/medium/high/xhigh 都译成 true。
  /// 这是协议本身的限制，UI 上要如实告知。
  enableThinking('enable_thinking', '开关式（enable_thinking）'),

  /// 档位制 reasoning_effort: low|medium|high。
  ///
  /// o1/o3 不返回思考内容，只影响推理强度。
  reasoningEffort('reasoning_effort', '档位式（reasoning_effort）');

  const ThinkingProtocol(this.id, this.label);

  final String id;
  final String label;

  /// 能否表达档位
  bool get supportsLevels => this == reasoningEffort;

  /// 会不会返回思考内容
  bool get returnsReasoning => this == alwaysOn || this == enableThinking;

  /// 旧版本存的是 thinkingMode 的 id（none/parse_only/
  /// enable_thinking/reasoning_effort），这里做一次映射，
  /// 避免升级后端点配置被清成 off。
  /// 按模型名推断该用哪种协议。
  ///
  /// 为什么要推断而不是让用户选：「要不要思考」是业务意图，
  /// 「用哪个字段名」是实现细节。把后者摆到用户面前，等于要求
  /// 他背下各家 API 的差异，而那些差异对他没有任何用处。
  ///
  /// 推断不准也不会出现硬伤：发错了参数会被 [_isUnsupportedParam] 识别，
  /// 然后自动降级重发一次，用户只是多等一个回合。
  static ThinkingProtocol infer(String model) {
    final m = model.toLowerCase();

    // 档位式：OpenAI o 系列（o1/o3/o4-mini）、gpt-5 推理模式、
    // 以及各家对齐 reasoning_effort 的实现。
    // 这类模型通常不返回思考内容，只影响推理强度。
    // 注意顺序：R1 的判断必须在 'reasoner' 之前。
    // 'deepseek-reasoner' 是 R1 的官方别名，它不需要请求参数、
    // 并且会返回 reasoning_content；如果先被 'reasoner' 命中，
    // 就会被误判成「不返回思考内容的 o 系列」，思考过程直接看不见。
    if (m.contains('r1') || m.contains('deepseek-reason')) return alwaysOn;

    if (RegExp(r'(^|[/_-])o[1345](-|$|mini)').hasMatch(m) ||
        m.contains('gpt-5') ||
        m.contains('reasoner')) {
      return reasoningEffort;
    }

    // 开关式：Qwen3 混合模型用 enable_thinking。
    // 不发它就默认不思考，这是最容易被误以为「模型不行」的情况。
    if (m.contains('qwen3') ||
        m.contains('qwq') ||
        m.contains('thinking') ||
        m.contains('glm-4.5') ||
        m.contains('glm-4.6')) {
      return enableThinking;
    }

    // 总是思考：R1 系列及各家对齐实现（deepseek-r1、distill、
    // siliconflow 的 R1、vllm 部署）。不需要请求参数，直接有。
    // 默认：发一个通用的 enable_thinking。
    //
    // 为什么选它而不是 off：用户在对话里选了「深度」，
    // 结果 App 什么都不发，那就是假的。多数兄弟实现
    // （硅基流动、中转站、vLLM、Ollama）都认 enable_thinking，
    // 不认的会报错，那时候自动降级到 off（见 [_isUnsupportedParam]）。
    return enableThinking;
  }

  static ThinkingProtocol fromId(String? id) {
    final legacy = switch (id) {
      'parse_only' => alwaysOn, // 旧名
      _ => null,
    };
    if (legacy != null) return legacy;
    for (final v in values) {
      if (v.id == id) return v;
    }
    return off;
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
    this.thinkingProtocol = ThinkingProtocol.off,
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

  /// 实际要用的协议。
  ///
  /// 为什么不让用户配：这一层是「把想多深」翻译成「哪个字段名」，
  /// 属于实现细节。用户在对话里选了档位，App 自己判断该怎么发。
  ///
  /// 优先级：
  /// 1. 用户显式配过（非 off）—— 尊重旧配置，不抢人家的选择
  /// 2. 按模型名推断—— 默认行为，让新建端点开箱就能思考
  ThinkingProtocol get effectiveProtocol =>
      thinkingProtocol != ThinkingProtocol.off
      ? thinkingProtocol
      : ThinkingProtocol.infer(model);

  /// 思考协议。见 [ThinkingProtocol]。
  ///
  /// 配在端点上而不是全局：同一个 App 可能同时接 DeepSeek（支持
  /// reasoning_content）和一个普通端点（不支持），协议差异跟的是
  /// 端点实现的形态，不是模型名。
  ///
  /// 用户**不会**直接改这个字段 —— 他改的是对话里的档位
  /// （[ThinkingLevel]），这里只负责把档位翻译成请求参数。
  final ThinkingProtocol thinkingProtocol;

  AiEndpoint copyWith({
    String? name,
    String? baseUrl,
    String? model,
    String? keyHint,
    ThinkingProtocol? thinkingProtocol,
  }) {
    return AiEndpoint(
      id: id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
      keyHint: keyHint ?? this.keyHint,
      thinkingProtocol: thinkingProtocol ?? this.thinkingProtocol,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'baseUrl': baseUrl,
    'model': model,
    'keyHint': keyHint,
    'thinkingProtocol': thinkingProtocol.id,
  };

  static AiEndpoint fromJson(Map<String, dynamic> j) => AiEndpoint(
    id: j['id'] as String? ?? '',
    name: j['name'] as String? ?? '',
    baseUrl: j['baseUrl'] as String? ?? '',
    model: j['model'] as String? ?? '',
    keyHint: j['keyHint'] as String? ?? '',
    // 兼容旧字段名 thinkingMode，按 id 映射到新协议
    thinkingProtocol: ThinkingProtocol.fromId(
      (j['thinkingProtocol'] ?? j['thinkingMode']) as String?,
    ),
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
    return AiConfig(endpoints: list, activeId: j['activeId'] as String? ?? '');
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
