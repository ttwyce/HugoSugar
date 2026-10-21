import 'package:flutter/material.dart';

/// 界面语言。
enum AppLocale {
  zh('中文'),
  en('English');

  const AppLocale(this.label);

  /// 语言自称，永远用该语言本身书写 ——
  /// 让用户在「看不懂当前界面语言」时也能找到自己的母语。
  final String label;

  String get id => name;

  Locale get locale => switch (this) {
        AppLocale.zh => const Locale('zh'),
        AppLocale.en => const Locale('en'),
      };

  static AppLocale fromId(String? id) {
    for (final v in values) {
      if (v.name == id) return v;
    }
    return AppLocale.zh;
  }

  /// 跟随系统时的兜底：非中文系统一律英文。
  static AppLocale fromSystem(Locale locale) {
    return locale.languageCode.toLowerCase() == 'zh'
        ? AppLocale.zh
        : AppLocale.en;
  }
}

/// 一条文案的中英对照。
///
/// 为什么用「中文当 key」而不是 `postList.title` 这种符号 key：
/// 这个项目原有 1100 多处中文字面量，若改成符号 key，
/// 每处都要人工起名，改动量和出错面都翻倍。
/// 直接拿中文原文当 key，好处是**未翻译时自动回落成中文**，
/// 不会出现「界面上一堆 postList.title」。
///
/// 代价是改中文文案等于改 key。但文案本来就不该频繁改，
/// 而且真要改时，测试会告诉我哪个 key 没对上。
typedef L10nEntry = ({String zh, String en});

/// 全量文案表。
///
/// 组织方式：按功能分区，分区内按字母/逻辑顺序。
/// 只放「界面静态文案」；动态拼接的句子用带占位符的模板。
const Map<String, L10nEntry> kStrings = {
  // ── 通用 ──────────────────────────────────────────────
  '取消': (zh: '取消', en: 'Cancel'),
  '保存': (zh: '保存', en: 'Save'),
  '确定': (zh: '确定', en: 'OK'),
  '删除': (zh: '删除', en: 'Delete'),
  '知道了': (zh: '知道了', en: 'Got it'),
  '完成': (zh: '完成', en: 'Done'),
  '部分完成': (zh: '部分完成', en: 'Partially done'),
  '设置': (zh: '设置', en: 'Settings'),
  '关闭': (zh: '关闭', en: 'Close'),
  '重试': (zh: '重试', en: 'Retry'),
  '复制': (zh: '复制', en: 'Copy'),
  '编辑': (zh: '编辑', en: 'Edit'),
  '新建': (zh: '新建', en: 'New'),
  '刷新': (zh: '刷新', en: 'Refresh'),
  '筛选': (zh: '筛选', en: 'Filter'),
  '搜索': (zh: '搜索', en: 'Search'),
  '全部': (zh: '全部', en: 'All'),

  // ── 底部导航 ──────────────────────────────────────────
  '文章': (zh: '文章', en: 'Posts'),
  '想法': (zh: '想法', en: 'Notes'),
  '对话': (zh: '对话', en: 'Chat'),
  '站点': (zh: '站点', en: 'Site'),

  // ── 外观设置 ──────────────────────────────────────────
  '外观': (zh: '外观', en: 'Appearance'),
  '强调色': (zh: '强调色', en: 'Accent color'),
  '正文字体': (zh: '正文字体', en: 'Body font'),
  '正文字号': (zh: '正文字号', en: 'Body size'),
  '系统黑体': (zh: '系统黑体', en: 'System sans'),
  '界面语言': (zh: '界面语言', en: 'Language'),
  '跟随系统': (zh: '跟随系统', en: 'Follow system'),

  // ── 导入导出 ──────────────────────────────────────────
  '导入导出': (zh: '导入导出', en: 'Import / Export'),
  '导出全部文章': (zh: '导出全部文章', en: 'Export all posts'),
  '打包成 zip 并分享': (zh: '打包成 zip 并分享', en: 'Bundle as zip and share'),
  '导入文章': (zh: '导入文章', en: 'Import posts'),
  '从 zip 或 .md 导入': (zh: '从 zip 或 .md 导入', en: 'From zip or .md'),
  '遇到同名文件时：': (zh: '遇到同名文件时：', en: 'When a file already exists:'),
  '跳过已存在的': (zh: '跳过已存在的', en: 'Skip existing'),
  '保留仓库里的版本（推荐）':
      (zh: '保留仓库里的版本（推荐）', en: 'Keep the repo version (recommended)'),
  '存为新文件': (zh: '存为新文件', en: 'Save as new file'),
  '自动加 -2、-3 后缀': (zh: '自动加 -2、-3 后缀', en: 'Append -2, -3 automatically'),
  '覆盖已存在的': (zh: '覆盖已存在的', en: 'Overwrite existing'),
  '仓库里的同名文件会被替换':
      (zh: '仓库里的同名文件会被替换', en: 'Same-name files in repo will be replaced'),

  // ── 文章列表 ──────────────────────────────────────────
  '新建文章': (zh: '新建文章', en: 'New post'),
  '还没有文章': (zh: '还没有文章', en: 'No posts yet'),
  '推送到 GitHub': (zh: '推送到 GitHub', en: 'Push to GitHub'),
  '回收站': (zh: '回收站', en: 'Trash'),
  '草稿': (zh: '草稿', en: 'Drafts'),
  '已发布': (zh: '已发布', en: 'Published'),

  // ── 设置页 ────────────────────────────────────────────
  '写作': (zh: '写作', en: 'Writing'),
  '日期格式': (zh: '日期格式', en: 'Date format'),
  '文件名规则': (zh: '文件名规则', en: 'File naming'),
  '作者信息': (zh: '作者信息', en: 'Author'),
  'GitHub 访问令牌': (zh: 'GitHub 访问令牌', en: 'GitHub token'),
  '记忆库': (zh: '记忆库', en: 'Memory'),
  '上下文压缩': (zh: '上下文压缩', en: 'Context compression'),
  '单轮 token 上限': (zh: '单轮 token 上限', en: 'Token limit per turn'),
  '工具开关': (zh: '工具开关', en: 'Tools'),
  'Skill / 工作模式': (zh: 'Skill / 工作模式', en: 'Skills'),
  '关于': (zh: '关于', en: 'About'),
  '版本': (zh: '版本', en: 'Version'),
  '检查更新': (zh: '检查更新', en: 'Check for updates'),
  '使用默认模板': (zh: '使用默认模板', en: 'Using default template'),
  '全部工具可用': (zh: '全部工具可用', en: 'All tools enabled'),
  '超过阈值后，较早的消息会被折叠成摘要，最近几条原样保留。':
      (zh: '超过阈值后，较早的消息会被折叠成摘要，最近几条原样保留。',
          en: 'Past the threshold, older messages are folded into a summary; '
              'the most recent ones are kept as-is.'),
  '触发阈值（条）': (zh: '触发阈值（条）', en: 'Threshold (messages)'),
  '保留最近（条）': (zh: '保留最近（条）', en: 'Keep recent (messages)'),
  '下限 4 / 上限 200。保留数必须小于阈值。':
      (zh: '下限 4 / 上限 200。保留数必须小于阈值。',
          en: 'Range 4–200. Keep count must be less than the threshold.'),
  '一次回答里累计超过这个数就中止，防止长对话烧掉大量额度。':
      (zh: '一次回答里累计超过这个数就中止，防止长对话烧掉大量额度。',
          en: 'Abort once a single reply exceeds this, '
              'so long chats do not burn through quota.'),
  '超过': (zh: '超过', en: 'Over'),

  // ── Skill 页 ──────────────────────────────────────────
  '内置': (zh: '内置', en: 'Built-in'),
  '新建 Skill': (zh: '新建 Skill', en: 'New skill'),
  '编辑 Skill': (zh: '编辑 Skill', en: 'Edit skill'),
  '删除这个 Skill？': (zh: '删除这个 Skill？', en: 'Delete this skill?'),
  '名称': (zh: '名称', en: 'Name'),
  '一句话说明（可选）': (zh: '一句话说明（可选）', en: 'One-line note (optional)'),
  '指令内容': (zh: '指令内容', en: 'Instructions'),
  '名称和指令内容不能为空':
      (zh: '名称和指令内容不能为空', en: 'Name and instructions are required'),

  // ── 工具说明 ──────────────────────────────────────────
  '列出想法': (zh: '列出想法', en: 'List notes'),
  '读取想法': (zh: '读取想法', en: 'Read note'),
  '搜索想法': (zh: '搜索想法', en: 'Search notes'),
  '读取文章': (zh: '读取文章', en: 'Read post'),
  '写入文章': (zh: '写入文章', en: 'Write post'),
  '抓取网页': (zh: '抓取网页', en: 'Fetch URL'),
  '记录记忆': (zh: '记录记忆', en: 'Save memory'),
  '改记忆': (zh: '改记忆', en: 'Update memory'),
  '删记忆': (zh: '删记忆', en: 'Delete memory'),
  '会动数据': (zh: '会动数据', en: 'Writes data'),
  '读取你的想法列表，可筛选':
      (zh: '读取你的想法列表，可筛选', en: 'Read your note list, filterable'),
  '读某一条想法的完整内容':
      (zh: '读某一条想法的完整内容', en: 'Read one note in full'),
  '在所有想法里全文搜索':
      (zh: '在所有想法里全文搜索', en: 'Full-text search across notes'),
  '读站点里已有文章的全文':
      (zh: '读站点里已有文章的全文', en: 'Read a full post from the site'),
  '往站点写文件（需你确认 Diff）':
      (zh: '往站点写文件（需你确认 Diff）', en: 'Write a file (you approve the diff)'),
  '联网读取指定网址的正文':
      (zh: '联网读取指定网址的正文', en: 'Fetch the body text of a URL'),
  '把你告诉它的事记进记忆库':
      (zh: '把你告诉它的事记进记忆库', en: 'Remember facts you tell it'),
  '改写或合并已记住的内容':
      (zh: '改写或合并已记住的内容', en: 'Rewrite or merge stored facts'),
  '删除一条记忆': (zh: '删除一条记忆', en: 'Delete one memory'),
  '关掉后模型完全看不到这个工具，不会调用也不会浪费一轮请求':
      (zh: '关掉后模型完全看不到这个工具，不会调用也不会浪费一轮请求',
          en: 'When off, the model cannot see this tool at all — '
              'no call, no wasted round'),

  // ── 导入导出结果 ──────────────────────────────────────
  '失败': (zh: '失败', en: 'Failed'),
  '跳过': (zh: '跳过', en: 'Skipped'),
  '已存在，已跳过': (zh: '已存在，已跳过', en: 'Already exists, skipped'),
  '站点尚未就绪': (zh: '站点尚未就绪', en: 'Site is not ready'),
  '没有可导出的文章': (zh: '没有可导出的文章', en: 'No posts to export'),
  '所有文章都读取失败': (zh: '所有文章都读取失败', en: 'Failed to read all posts'),
  '读取文件失败': (zh: '读取文件失败', en: 'Failed to read the file'),
  '文件不是 UTF-8 文本': (zh: '文件不是 UTF-8 文本', en: 'File is not UTF-8 text'),
  '文件里没有找到 .md 文章':
      (zh: '文件里没有找到 .md 文章', en: 'No .md posts found in the file'),
  '没有变化': (zh: '没有变化', en: 'No changes'),
};

/// 取文案。
///
/// 找不到 key 时**原样返回 key**，而不是返回 `??key??` 之类：
/// 因为我们用中文原文当 key，原样返回就等于优雅回落到中文，
/// 界面不会因为漏翻而出现占位符。
String tr(String key, AppLocale locale) {
  final e = kStrings[key];
  if (e == null) return key;
  return locale == AppLocale.en ? e.en : e.zh;
}