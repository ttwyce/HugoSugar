import 'dart:convert';

/// 工具执行结果。
class ToolResult {
  const ToolResult({
    required this.ok,
    this.text = '',
    this.detail = '',
  });

  final bool ok;

  /// 回灌给模型的内容（会被计入 token，要紧凑）
  final String text;

  /// 给用户看的详情（可展开，可以更长）
  final String detail;

  Map<String, dynamic> toJson() => {'ok': ok, 'text': text, 'detail': detail};

  static ToolResult fail(String msg) => ToolResult(ok: false, text: msg, detail: msg);
}

/// 一个可供模型调用的工具。
///
/// [requiresApproval] 为 true 时，Agent 循环必须暂停，
/// 让用户看清将发生什么再执行。本项目里只有 `write_post` 是 true。
class AiTool {
  const AiTool({
    required this.name,
    required this.description,
    required this.parameters,
    required this.execute,
    this.requiresApproval = false,
  });

  final String name;
  final String description;

  /// JSON Schema 的 parameters 部分
  final Map<String, dynamic> parameters;

  final bool requiresApproval;

  final Future<ToolResult> Function(Map<String, dynamic> args) execute;

  /// 转成 OpenAI tools 数组里的一项
  Map<String, dynamic> toApiJson() => {
        'type': 'function',
        'function': {
          'name': name,
          'description': description,
          'parameters': parameters,
        },
      };
}

/// 便捷构造 JSON Schema
Map<String, dynamic> objectSchema({
  required Map<String, dynamic> properties,
  List<String> required = const [],
}) {
  return {
    'type': 'object',
    'properties': properties,
    'required': required,
  };
}

Map<String, dynamic> stringProp(String desc, {List<String>? enumValues}) {
  return {
    'type': 'string',
    'description': desc,
    'enum': ?enumValues,
  };
}

Map<String, dynamic> intProp(String desc) =>
    {'type': 'integer', 'description': desc};

/// 把任意对象转成紧凑、可截断的观察文本，用于回灌给模型。
String previewForTool(Object? v, {int max = 400}) {
  final s = v is String ? v : jsonEncode(v);
  if (s.length <= max) return s;
  return '${s.substring(0, max)}…（已截断，原长 ${s.length}）';
}