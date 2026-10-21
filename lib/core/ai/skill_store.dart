import 'dart:convert';
import 'dart:io';

/// 一个 Skill：一段可复用的固定指令。
///
/// ## 为什么只做「提示词模板」这一种
///
/// Skill 有三种可能的理解：
///   A. 提示词模板（本实现）
///   B. 工具组合包（一组工具的预设开关）
///   C. 可执行脚本
///
/// 选 A 的理由：它解决的是最高频的痛点——每次都手打一遍
/// 「帮我把这段改写成技术博客风格，先给结论再展开」。
/// 而 B 只是工具开关的批量预设（工具开关本身已经做了），
/// C 需要执行任意代码，安全边界完全不同，不该混进写作 App。
///
/// ## 为什么模板拼在 System Prompt 里，而不是塞进用户消息
///
/// 用户消息会被当成「这一轮要处理的内容」，模板塞进去模型会
/// 把它当作待分析对象；System Prompt 是「你该怎么做事」，
/// 模板属于后者。放在用户消息里还会让后续轮次以为用户又说了那句话。
class Skill {
  const Skill({
    required this.id,
    required this.name,
    required this.prompt,
    this.builtin = false,
    this.description = '',
  });

  final String id;
  final String name;

  /// 套用时追加到 System Prompt 的文本。
  final String prompt;

  /// 内置 Skill 不允许删除（可以停用）。
  ///
  /// 理由：用户删了之后想恢复只能重装 App。而内置的这几条
  /// 是「写作」这个场景的基本盘，留着不占地方。
  final bool builtin;

  /// 一句话说明，显示在列表里。
  final String description;

  Skill copyWith({String? name, String? prompt, String? description}) => Skill(
    id: id,
    name: name ?? this.name,
    prompt: prompt ?? this.prompt,
    builtin: builtin,
    description: description ?? this.description,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'prompt': prompt,
    'builtin': builtin,
    'description': description,
  };

  static Skill fromJson(Map<String, dynamic> j) => Skill(
    id: j['id'] as String? ?? '',
    name: j['name'] as String? ?? '',
    prompt: j['prompt'] as String? ?? '',
    builtin: j['builtin'] as bool? ?? false,
    description: j['description'] as String? ?? '',
  );
}

/// 内置 Skill。
///
/// 每个都写清了「做什么」和「不要做什么」——只写前者的模板
/// 经常被模型过度发挥，比如让它「精简」，结果把逻辑也删了。
const List<Skill> kBuiltinSkills = [
  Skill(
    id: 'builtin_polish',
    name: '润色',
    description: '改语言不改意思：修病句、去口水词，保留原意和结构',
    builtin: true,
    prompt:
        '用户会给你一段文字，请润色它。\n'
        '只改语言表达：修正病句、去掉重复和口水词、调整语序。\n'
        '**不要**改变原意、不要增删观点、不要调整段落结构。\n'
        '直接给出润色后的全文，不要逐句解释改了什么，'
        '除非用户另外问。',
  ),
  Skill(
    id: 'builtin_condense',
    name: '精简',
    description: '砍掉冗余但保住全部信息点，不删观点',
    builtin: true,
    prompt:
        '用户会给你一段文字，请精简它。\n'
        '目标是更短的篇幅、同样的信息量：删掉过渡句、重复表述、'
        '无信息量的修饰。\n'
        '**必须保留所有观点、数据、结论**——宁可少删，不可误删。\n'
        '如果某处删掉会损失信息，就保留。',
  ),
  Skill(
    id: 'builtin_tech_blog',
    name: '技术博客',
    description: '按「先结论后展开」的结构重写成可发布的技术文章',
    builtin: true,
    prompt:
        '把内容重写成一篇可发布的技术博客。\n'
        '结构：先一句话结论，再展开原因/过程，最后给可执行的建议。\n'
        '段落短，一段只说一件事。\n'
        '例子要具体，不要「某公司」「某个场景」这种空壳。\n'
        '不要加「总结」「综上所述」这类填充段。',
  ),
  Skill(
    id: 'builtin_review',
    name: '挑毛病',
    description: '只找问题不改写：逻辑漏洞、事实错误、表述不清',
    builtin: true,
    prompt:
        '用户会给你一段内容，请挑毛病。\n'
        '**不要重写它**，只指出问题：\n'
        '1. 逻辑漏洞（前后矛盾、因果不成立、以偏概全）\n'
        '2. 事实性错误或需要核实的地方\n'
        '3. 表述不清、有歧义的句子\n'
        '按严重程度排序，每条给出原文位置和为什么是问题。\n'
        '没有问题就说没有问题，不要为了凑数硬找。',
  ),
  Skill(
    id: 'builtin_translate',
    name: '翻译',
    description: '中英互译，保留术语和技术名词的原文',
    builtin: true,
    prompt:
        '在中文和英文之间互译（按输入语言判断方向）。\n'
        '技术术语、专有名词、代码标识符保留原文，不强行翻译。\n'
        '译文要像目标语言的原生写作，不要逐字硬译。\n'
        '只给译文，不要附注解释。',
  ),
];

/// Skill 的本地存储。
///
/// 内置的从代码里来，用户自建的存 `skills.json`。
/// 为什么不把内置的也存进文件：那样升级 App 时内置模板的改进
/// 就到不了老用户手上（文件里是旧副本）。
class SkillStore {
  SkillStore(this._file);

  factory SkillStore.at(Directory base) =>
      SkillStore(File('${base.path}/skills.json'));

  final File _file;

  List<Skill> _custom = const [];

  /// 用户自建的 Skill。
  List<Skill> get custom => _custom;

  /// 全部 Skill：内置在前，自建在后。
  List<Skill> get all => [...kBuiltinSkills, ..._custom];

  Skill? byId(String id) {
    for (final s in all) {
      if (s.id == id) return s;
    }
    return null;
  }

  Future<void> load() async {
    if (!await _file.exists()) {
      _custom = const [];
      return;
    }
    try {
      final raw = jsonDecode(await _file.readAsString());
      if (raw is List) {
        _custom = raw
            .whereType<Map>()
            .map((e) => Skill.fromJson(Map<String, dynamic>.from(e)))
            // 文件里若混进了 builtin 的副本，丢掉 —— 内置的以代码为准
            .where((s) => !s.builtin && s.name.trim().isNotEmpty)
            .toList();
      }
    } catch (_) {
      // 文件坏了先当空的，别让 App 打不开
      _custom = const [];
    }
  }

  Future<void> _save() async {
    await _file.parent.create(recursive: true);
    await _file.writeAsString(
      jsonEncode(_custom.map((s) => s.toJson()).toList()),
      flush: true,
    );
  }

  Future<Skill> add({
    required String name,
    required String prompt,
    String description = '',
  }) async {
    final s = Skill(
      id: 'skill_${DateTime.now().microsecondsSinceEpoch}',
      name: name.trim().isEmpty ? '未命名' : name.trim(),
      prompt: prompt.trim(),
      description: description.trim(),
    );
    _custom = [..._custom, s];
    await _save();
    return s;
  }

  Future<bool> update(
    String id, {
    String? name,
    String? prompt,
    String? description,
  }) async {
    final i = _custom.indexWhere((s) => s.id == id);
    if (i < 0) return false; // 内置的不能改
    _custom = [..._custom]
      ..[i] = _custom[i].copyWith(
        name: name,
        prompt: prompt,
        description: description,
      );
    await _save();
    return true;
  }

  Future<bool> remove(String id) async {
    final before = _custom.length;
    _custom = _custom.where((s) => s.id != id).toList();
    if (_custom.length == before) return false;
    await _save();
    return true;
  }

  /// 把启用的 Skill 拼成追加到 System Prompt 的文本。
  ///
  /// 每段前面标上名字并缩进，模型更容易把不同 Skill 的指令分开看，
  /// 不会把「翻译」的要求套到「挑毛病」上。
  String promptBlockFor(List<String> ids) {
    if (ids.isEmpty) return '';
    final picked = <Skill>[];
    for (final id in ids) {
      final s = byId(id);
      if (s != null) picked.add(s);
    }
    if (picked.isEmpty) return '';

    final buf = StringBuffer();
    buf.writeln('## 当前启用的工作模式');
    buf.writeln();
    buf.writeln(
      '用户此刻启用了以下模式。它们规定了「怎么做」，'
      '在不违反用户当场提出的要求的前提下尽量遵循：',
    );
    buf.writeln();
    for (final s in picked) {
      buf.writeln('### ${s.name}');
      buf.writeln(s.prompt.trim());
      buf.writeln();
    }
    return buf.toString().trim();
  }
}
