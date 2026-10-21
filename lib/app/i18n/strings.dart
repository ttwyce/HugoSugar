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
  '保留仓库里的版本（推荐）': (
    zh: '保留仓库里的版本（推荐）',
    en: 'Keep the repo version (recommended)',
  ),
  '存为新文件': (zh: '存为新文件', en: 'Save as new file'),
  '自动加 -2、-3 后缀': (zh: '自动加 -2、-3 后缀', en: 'Append -2, -3 automatically'),
  '覆盖已存在的': (zh: '覆盖已存在的', en: 'Overwrite existing'),
  '仓库里的同名文件会被替换': (
    zh: '仓库里的同名文件会被替换',
    en: 'Same-name files in repo will be replaced',
  ),

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
  '超过阈值后，较早的消息会被折叠成摘要，最近几条原样保留。': (
    zh: '超过阈值后，较早的消息会被折叠成摘要，最近几条原样保留。',
    en:
        'Past the threshold, older messages are folded into a summary; '
        'the most recent ones are kept as-is.',
  ),
  '触发阈值（条）': (zh: '触发阈值（条）', en: 'Threshold (messages)'),
  '保留最近（条）': (zh: '保留最近（条）', en: 'Keep recent (messages)'),
  '下限 4 / 上限 200。保留数必须小于阈值。': (
    zh: '下限 4 / 上限 200。保留数必须小于阈值。',
    en: 'Range 4–200. Keep count must be less than the threshold.',
  ),
  '一次回答里累计超过这个数就中止，防止长对话烧掉大量额度。': (
    zh: '一次回答里累计超过这个数就中止，防止长对话烧掉大量额度。',
    en:
        'Abort once a single reply exceeds this, '
        'so long chats do not burn through quota.',
  ),
  '超过': (zh: '超过', en: 'Over'),

  // ── Skill 页 ──────────────────────────────────────────
  '内置': (zh: '内置', en: 'Built-in'),
  '新建 Skill': (zh: '新建 Skill', en: 'New skill'),
  '编辑 Skill': (zh: '编辑 Skill', en: 'Edit skill'),
  '删除这个 Skill？': (zh: '删除这个 Skill？', en: 'Delete this skill?'),
  '名称': (zh: '名称', en: 'Name'),
  '一句话说明（可选）': (zh: '一句话说明（可选）', en: 'One-line note (optional)'),
  '指令内容': (zh: '指令内容', en: 'Instructions'),
  '名称和指令内容不能为空': (zh: '名称和指令内容不能为空', en: 'Name and instructions are required'),

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
  '读取你的想法列表，可筛选': (zh: '读取你的想法列表，可筛选', en: 'Read your note list, filterable'),
  '读某一条想法的完整内容': (zh: '读某一条想法的完整内容', en: 'Read one note in full'),
  '在所有想法里全文搜索': (zh: '在所有想法里全文搜索', en: 'Full-text search across notes'),
  '读站点里已有文章的全文': (zh: '读站点里已有文章的全文', en: 'Read a full post from the site'),
  '往站点写文件（需你确认 Diff）': (
    zh: '往站点写文件（需你确认 Diff）',
    en: 'Write a file (you approve the diff)',
  ),
  '联网读取指定网址的正文': (zh: '联网读取指定网址的正文', en: 'Fetch the body text of a URL'),
  '把你告诉它的事记进记忆库': (zh: '把你告诉它的事记进记忆库', en: 'Remember facts you tell it'),
  '改写或合并已记住的内容': (zh: '改写或合并已记住的内容', en: 'Rewrite or merge stored facts'),
  '删除一条记忆': (zh: '删除一条记忆', en: 'Delete one memory'),
  '关掉后模型完全看不到这个工具，不会调用也不会浪费一轮请求': (
    zh: '关掉后模型完全看不到这个工具，不会调用也不会浪费一轮请求',
    en:
        'When off, the model cannot see this tool at all — '
        'no call, no wasted round',
  ),

  // ── 导入导出结果 ──────────────────────────────────────
  '失败': (zh: '失败', en: 'Failed'),
  '跳过': (zh: '跳过', en: 'Skipped'),
  '已存在，已跳过': (zh: '已存在，已跳过', en: 'Already exists, skipped'),
  '站点尚未就绪': (zh: '站点尚未就绪', en: 'Site is not ready'),
  '没有可导出的文章': (zh: '没有可导出的文章', en: 'No posts to export'),
  '所有文章都读取失败': (zh: '所有文章都读取失败', en: 'Failed to read all posts'),
  '读取文件失败': (zh: '读取文件失败', en: 'Failed to read the file'),
  '文件不是 UTF-8 文本': (zh: '文件不是 UTF-8 文本', en: 'File is not UTF-8 text'),
  '文件里没有找到 .md 文章': (
    zh: '文件里没有找到 .md 文章',
    en: 'No .md posts found in the file',
  ),
  '没有变化': (zh: '没有变化', en: 'No changes'),

  // ── 自动补齐（页面文案）──
  '标题': (zh: '标题', en: 'Title'),
  '模型': (zh: '模型', en: 'Model'),
  '添加': (zh: '添加', en: 'Add'),
  '打开': (zh: '打开', en: 'Open'),
  '返回': (zh: '返回', en: 'Back'),
  '更多': (zh: '更多', en: 'More'),
  '清除': (zh: '清除', en: 'Clear'),
  '清空': (zh: '清空', en: 'Clear all'),
  '恢复': (zh: '恢复', en: 'Restore'),
  '重命名': (zh: '重命名', en: 'Rename'),
  '继续': (zh: '继续', en: 'Continue'),
  '状态': (zh: '状态', en: 'Status'),
  '变更': (zh: '变更', en: 'Changes'),
  '冲突': (zh: '冲突', en: 'Conflict'),
  '分支': (zh: '分支', en: 'Branch'),
  '仓库': (zh: '仓库', en: 'Repository'),
  '必填': (zh: '必填', en: 'Required'),
  '无': (zh: '无', en: 'None'),
  '好': (zh: '好', en: 'OK'),
  '不要': (zh: '不要', en: 'No'),
  '撤销': (zh: '撤销', en: 'Undo'),
  '重做': (zh: '重做', en: 'Redo'),
  '预览': (zh: '预览', en: 'Preview'),
  '引用': (zh: '引用', en: 'Quote'),
  '链接': (zh: '链接', en: 'Link'),
  '替换': (zh: '替换', en: 'Replace'),
  '查找': (zh: '查找', en: 'Find'),
  '替换为': (zh: '替换为', en: 'Replace with'),
  '表': (zh: '表', en: 'Table'),
  '分隔线': (zh: '分隔线', en: 'Divider'),
  '表格': (zh: '表格', en: 'Table'),
  '粗体': (zh: '粗体', en: 'Bold'),
  '斜体': (zh: '斜体', en: 'Italic'),
  '删除线': (zh: '删除线', en: 'Strikethrough'),
  '行内代码': (zh: '行内代码', en: 'Inline code'),
  '无序列表': (zh: '无序列表', en: 'Bullet list'),
  '有序列表': (zh: '有序列表', en: 'Numbered list'),
  '链接文字': (zh: '链接文字', en: 'Link text'),
  '提示块': (zh: '提示块', en: 'Callout'),
  '新建文件名': (zh: '新建文件名', en: 'New file name'),
  '系统默认': (zh: '系统默认', en: 'System default'),
  '等宽': (zh: '等宽', en: 'Monospace'),
  '衬线（宋体类）': (zh: '衬线（宋体类）', en: 'Serif'),
  '无衬线（黑体类）': (zh: '无衬线（黑体类）', en: 'Sans-serif'),
  '亮色': (zh: '亮色', en: 'Light'),
  '暗色': (zh: '暗色', en: 'Dark'),
  '未保存': (zh: '未保存', en: 'Unsaved'),
  '已保存': (zh: '已保存', en: 'Saved'),
  '保存中…': (zh: '保存中…', en: 'Saving…'),
  '已同步': (zh: '已同步', en: 'Synced'),
  '本地变更': (zh: '本地变更', en: 'Local changes'),
  '更…': (zh: '更…', en: 'More…'),
  '当前': (zh: '当前', en: 'Current'),
  '端点': (zh: '端点', en: 'Endpoint'),
  '端点管理': (zh: '端点管理', en: 'Endpoints'),
  '编辑端点': (zh: '编辑端点', en: 'Edit endpoint'),
  '删除端点': (zh: '删除端点', en: 'Delete endpoint'),
  '添加端点': (zh: '添加端点', en: 'Add endpoint'),
  'API 配置': (zh: 'API 配置', en: 'API configuration'),
  '未配置端点': (zh: '未配置端点', en: 'No endpoint configured'),
  '未配置，点击添加端点': (
    zh: '未配置，点击添加端点',
    en: 'Not configured — tap to add an endpoint',
  ),
  '未选模型': (zh: '未选模型', en: 'No model selected'),
  '未选择模型': (zh: '未选择模型', en: 'No model selected'),
  '未填 Key': (zh: '未填 Key', en: 'No key'),
  '未接入': (zh: '未接入', en: 'Not connected'),
  '未设置': (zh: '未设置', en: 'Not set'),
  '未知错误': (zh: '未知错误', en: 'Unknown error'),
  '权限不足': (zh: '权限不足', en: 'Insufficient permission'),
  '网络错误': (zh: '网络错误', en: 'Network error'),
  '请求失败': (zh: '请求失败', en: 'Request failed'),
  '接入失败': (zh: '接入失败', en: 'Failed to connect'),
  '创建失败': (zh: '创建失败', en: 'Failed to create'),
  '保存失败': (zh: '保存失败', en: 'Failed to save'),
  '推送失败': (zh: '推送失败', en: 'Push failed'),
  '推送成功': (zh: '推送成功', en: 'Pushed successfully'),
  '恢复失败': (zh: '恢复失败', en: 'Failed to restore'),
  '撤回失败': (zh: '撤回失败', en: 'Failed to retract'),
  '撤销失败': (zh: '撤销失败', en: 'Failed to undo'),
  '转换失败': (zh: '转换失败', en: 'Conversion failed'),
  '令牌无效': (zh: '令牌无效', en: 'Invalid token'),
  '仓库不存在': (zh: '仓库不存在', en: 'Repository not found'),
  '空仓库': (zh: '空仓库', en: 'Empty repository'),
  '获取中': (zh: '获取中', en: 'Fetching…'),
  '连接中…': (zh: '连接中…', en: 'Connecting…'),
  '校验中…': (zh: '校验中…', en: 'Validating…'),
  '读取中…': (zh: '读取中…', en: 'Reading…'),
  '已删除': (zh: '已删除', en: 'Deleted'),
  '已归档': (zh: '已归档', en: 'Archived'),
  '已恢复': (zh: '已恢复', en: 'Restored'),
  '已压缩': (zh: '已压缩', en: 'Compressed'),
  '已连接': (zh: '已连接', en: 'Connected'),
  '已转文章': (zh: '已转文章', en: 'Converted to post'),
  '刚刚': (zh: '刚刚', en: 'Just now'),
  '彻底删除': (zh: '彻底删除', en: 'Delete permanently'),
  '永久删除': (zh: '永久删除', en: 'Delete permanently'),
  '移到回收站': (zh: '移到回收站', en: 'Move to trash'),
  '发布': (zh: '发布', en: 'Publish'),
  '发布日期': (zh: '发布日期', en: 'Publish date'),
  '分类': (zh: '分类', en: 'Category'),
  '标签': (zh: '标签', en: 'Tags'),
  '置顶': (zh: '置顶', en: 'Pin'),
  '取消置顶': (zh: '取消置顶', en: 'Unpin'),
  '精选': (zh: '精选', en: 'Featured'),
  '取消精选': (zh: '取消精选', en: 'Unfeature'),
  '归档': (zh: '归档', en: 'Archive'),
  '文章标题': (zh: '文章标题', en: 'Post title'),
  '文章信息': (zh: '文章信息', en: 'Post info'),
  '简介（description）': (zh: '简介（description）', en: 'Description'),
  '简介（可选）': (zh: '简介（可选）', en: 'Summary (optional)'),
  '简介（可选，会写进 description）': (
    zh: '简介（可选，会写进 description）',
    en: 'Summary (optional, written to description)',
  ),
  '笔记标题': (zh: '笔记标题', en: 'Note title'),
  '未被标题': (zh: '未被标题', en: 'Untitled'),
  '无标题': (zh: '无标题', en: 'Untitled'),
  '未命名': (zh: '未命名', en: 'Untitled'),
  '新建想法': (zh: '新建想法', en: 'New note'),
  '新建分类': (zh: '新建分类', en: 'New category'),
  '新建分组': (zh: '新建分组', en: 'New group'),
  '编辑记忆': (zh: '编辑记忆', en: 'Edit memory'),
  '删除这条记忆？': (zh: '删除这条记忆？', en: 'Delete this memory?'),
  '清空全部记忆？': (zh: '清空全部记忆？', en: 'Clear all memory?'),
  '记忆': (zh: '记忆', en: 'Memory'),
  '关于用户的事实': (zh: '关于用户的事实', en: 'Facts about the user'),
  '压缩阈值': (zh: '压缩阈值', en: 'Compression threshold'),
  '保留最近': (zh: '保留最近', en: 'Keep recent'),
  '上下文': (zh: '上下文', en: 'Context'),
  '当前消息': (zh: '当前消息', en: 'Current messages'),
  '上次请求': (zh: '上次请求', en: 'Last request'),
  '上次估算 token': (zh: '上次估算 token', en: 'Last estimated tokens'),
  '写入想法': (zh: '写入想法', en: 'Write note'),
  '把所有事实…': (zh: '把所有事实…', en: 'Store all facts…'),
  '把资料/灵感新建为一条想法': (
    zh: '把资料/灵感新建为一条想法',
    en: 'Save material/inspiration as a note',
  ),
  '尚未加载': (zh: '尚未加载', en: 'Not loaded yet'),
  '访问令牌': (zh: '访问令牌', en: 'Token'),
  '提交作者': (zh: '提交作者', en: 'Commit author'),
  '作者名': (zh: '作者名', en: 'Author name'),
  '作者邮箱': (zh: '作者邮箱', en: 'Author email'),
  '提交说明': (zh: '提交说明', en: 'Commit message'),
  '提交并推送': (zh: '提交并推送', en: 'Commit and push'),
  '当前站点': (zh: '当前站点', en: 'Current site'),
  '站点管理': (zh: '站点管理', en: 'Site management'),
  '接入 Git 仓库': (zh: '接入 Git 仓库', en: 'Connect a Git repository'),
  '接入 GitHub': (zh: '接入 GitHub', en: 'Connect GitHub'),
  '解绑站点': (zh: '解绑站点', en: 'Disconnect site'),
  '解绑': (zh: '解绑', en: 'Disconnect'),
  '重新接入': (zh: '重新接入', en: 'Reconnect'),
  '重新克隆': (zh: '重新克隆', en: 'Re-clone'),
  '换个仓库重试': (zh: '换个仓库重试', en: 'Try another repo'),
  '读取我的仓库': (zh: '读取我的仓库', en: 'Load my repositories'),
  '选择仓库': (zh: '选择仓库', en: 'Select repository'),
  '搜索仓库': (zh: '搜索仓库', en: 'Search repositories'),
  '获取列表': (zh: '获取列表', en: 'Load list'),
  '正在保存想法…': (zh: '正在保存想法…', en: 'Saving note…'),
  '正在列出想法…': (zh: '正在列出想法…', en: 'Listing notes…'),
  '正在搜索想法…': (zh: '正在搜索想法…', en: 'Searching notes…'),
  '正在读取想法…': (zh: '正在读取想法…', en: 'Reading note…'),
  '正在读取文章…': (zh: '正在读取文章…', en: 'Reading post…'),
  '正在抓取网页…': (zh: '正在抓取网页…', en: 'Fetching page…'),
  '准备写入文章…': (zh: '准备写入文章…', en: 'Preparing to write…'),
  '正在思考…': (zh: '正在思考…', en: 'Thinking…'),
  '正在生成中，稍后再切换': (zh: '正在生成中，稍后再切换', en: 'Generating — switch later'),
  '正在获取模型列表…': (zh: '正在获取模型列表…', en: 'Loading models…'),
  '正在读取仓库…': (zh: '正在读取仓库…', en: 'Reading repository…'),
  '正在克隆': (zh: '正在克隆', en: 'Cloning'),
  '正在克隆仓库': (zh: '正在克隆仓库', en: 'Cloning repository'),
  '正在接入': (zh: '正在接入', en: 'Connecting'),
  '思考档位': (zh: '思考档位', en: 'Thinking level'),
  '思考过程': (zh: '思考过程', en: 'Reasoning'),
  '新对话': (zh: '新对话', en: 'New chat'),
  '历史对话': (zh: '历史对话', en: 'History'),
  '对话分组': (zh: '对话分组', en: 'Chat groups'),
  '重命名分组': (zh: '重命名分组', en: 'Rename group'),
  '移动到分组': (zh: '移动到分组', en: 'Move to group'),
  '管理分组': (zh: '管理分组', en: 'Manage groups'),
  '删除分组': (zh: '删除分组', en: 'Delete group'),
  '未分组': (zh: '未分组', en: 'Ungrouped'),
  '还没有分组': (zh: '还没有分组', en: 'No groups yet'),
  '撤回对话': (zh: '撤回对话', en: 'Retract chat'),
  '撤回这条': (zh: '撤回这条', en: 'Retract this'),
  '撤回这条及之后': (zh: '撤回这条及之后', en: 'Retract this and after'),
  '编辑后重发': (zh: '编辑后重发', en: 'Edit and resend'),
  '原样重发': (zh: '原样重发', en: 'Resend as-is'),
  '重发': (zh: '重发', en: 'Resend'),
  '重新发送': (zh: '重新发送', en: 'Resend'),
  '再生成一次': (zh: '再生成一次', en: 'Regenerate'),
  '再生成一篇': (zh: '再生成一篇', en: 'Generate another'),
  '删除这条': (zh: '删除这条', en: 'Delete this'),
  '删除文章': (zh: '删除文章', en: 'Delete post'),
  '删除分类': (zh: '删除分类', en: 'Delete category'),
  '彻底删除这个对话？': (zh: '彻底删除这个对话？', en: 'Delete this chat permanently?'),
  '永久删除？': (zh: '永久删除？', en: 'Delete permanently?'),
  '删除这篇文章？': (zh: '删除这篇文章？', en: 'Delete this post?'),
  '清空回收站': (zh: '清空回收站', en: 'Empty trash'),
  '清空回收站？': (zh: '清空回收站？', en: 'Empty trash?'),
  '已永久删除': (zh: '已永久删除', en: 'Permanently deleted'),
  '回收站是空的': (zh: '回收站是空的', en: 'Trash is empty'),
  '还没有想法': (zh: '还没有想法', en: 'No notes yet'),
  '还没有历史对话': (zh: '还没有历史对话', en: 'No chat history yet'),
  '还没有记忆': (zh: '还没有记忆', en: 'No memory yet'),
  '还没有接入站点': (zh: '还没有接入站点', en: 'No site connected yet'),
  '还没有配置 AI 端点': (zh: '还没有配置 AI 端点', en: 'No AI endpoint configured yet'),
  '开始一次对话': (zh: '开始一次对话', en: 'Start a chat'),
  '先配置一个 AI 端点': (zh: '先配置一个 AI 端点', en: 'Set up an AI endpoint first'),
  '去配置': (zh: '去配置', en: 'Set up'),
  '说点什么…': (zh: '说点什么…', en: 'Say something…'),
  '随手写点什么…': (zh: '随手写点什么…', en: 'Jot something down…'),
  '正文…': (zh: '正文…', en: 'Body…'),
  '搜索记忆…': (zh: '搜索记忆…', en: 'Search memory…'),
  '全部（可在「想法」页的 AI 菜单里指定分组）': (
    zh: '全部（可在「想法」页的 AI 菜单里指定分组）',
    en: 'All (pick groups from the AI menu on the Notes page)',
  ),
  '在想法页设置': (zh: '在想法页设置', en: 'Set on Notes page'),
  '允许 AI 读取想法': (zh: '允许 AI 读取想法', en: 'Let AI read notes'),
  '允许读取的分组': (zh: '允许读取的分组', en: 'Groups to read'),
  '当前使用：': (zh: '当前使用：', en: 'In use: '),
  '思考档位：': (zh: '思考档位：', en: 'Thinking level: '),
  '格式：': (zh: '格式：', en: 'Format: '),
  '文件：': (zh: '文件：', en: 'File: '),
  '删除于 ': (zh: '删除于 ', en: 'Deleted '),
  '分类：': (zh: '分类：', en: 'Category: '),
  '标签：': (zh: '标签：', en: 'Tags: '),
  '文章 · ': (zh: '文章 · ', en: 'Posts · '),
  '过滤结果 · ': (zh: '过滤结果 · ', en: 'Filtered · '),
  '筛选结果 · ': (zh: '筛选结果 · ', en: 'Filtered · '),
  '回收站 · ': (zh: '回收站 · ', en: 'Trash · '),
  '回收站（': (zh: '回收站（', en: 'Trash ('),
  '记忆库（': (zh: '记忆库（', en: 'Memory ('),
  '已保存：': (zh: '已保存：', en: 'Saved: '),
  '约 ': (zh: '约 ', en: '~'),
  '全部 ': (zh: '全部 ', en: 'All '),
  '活跃 ': (zh: '活跃 ', en: 'Active '),
  '草稿 ': (zh: '草稿 ', en: 'Drafts '),
  '已发布 ': (zh: '已发布 ', en: 'Published '),
  '已归档 ': (zh: '已归档 ', en: 'Archived '),
  '已删除 ': (zh: '已删除 ', en: 'Deleted '),
  '已折叠 ': (zh: '已折叠 ', en: 'Folded '),
  '已替换 ': (zh: '已替换 ', en: 'Replaced '),
  '已记住 ': (zh: '已记住 ', en: 'Remembered '),
  '已永久删除 ': (zh: '已永久删除 ', en: 'Permanently deleted '),
  '落后远端 ': (zh: '落后远端 ', en: 'Behind remote by '),
  '行新增 · ': (zh: '行新增 · ', en: ' lines added · '),
  ' 行删除': (zh: ' 行删除', en: ' lines removed'),
  ' 天前': (zh: ' 天前', en: ' days ago'),
  ' 小时前': (zh: ' 小时前', en: ' hours ago'),
  ' 分钟前': (zh: ' 分钟前', en: ' minutes ago'),
  ' 字': (zh: ' 字', en: ' chars'),
  ' 篇': (zh: ' 篇', en: ' posts'),
  ' 个对话': (zh: ' 个对话', en: ' chats'),
  ' 条': (zh: ' 条', en: ' items'),
  ' 个文件': (zh: ' 个文件', en: ' files'),
  ' 个仓库': (zh: ' 个仓库', en: ' repos'),
  ' 入 / ': (zh: ' 入 / ', en: ' in / '),
  ' 出 token': (zh: ' 出 token', en: ' out tokens'),
  'AI 将不再记得你的偏好。此操作不可撤销。': (
    zh: 'AI 将不再记得你的偏好。此操作不可撤销。',
    en: 'AI will forget your preferences. This cannot be undone.',
  ),
  'AI 端点': (zh: 'AI 端点', en: 'AI endpoints'),
  'AI 读取范围': (zh: 'AI 读取范围', en: 'AI reading scope'),
  'ghp_... 或 github_pat_...': (
    zh: 'ghp_... 或 github_pat_...',
    en: 'ghp_... or github_pat_...',
  ),
  '不分类': (zh: '不分类', en: 'Uncategorized'),
  '中止': (zh: '中止', en: 'Stop'),
  '会删除本地已克隆的仓库副本，远端仓库不受影响。': (
    zh: '会删除本地已克隆的仓库副本，远端仓库不受影响。',
    en: 'Deletes the locally cloned copy; the remote repository is unaffected.',
  ),
  '例如 gpt-4o-mini': (zh: '例如 gpt-4o-mini', en: 'e.g. gpt-4o-mini'),
  '例如：写作辅助': (zh: '例如：写作辅助', en: 'e.g. Writing assistant'),
  '例如：改成口语化': (zh: '例如：改成口语化', en: 'e.g. Make it more colloquial'),
  '保存失败，请查看底部状态': (
    zh: '保存失败，请查看底部状态',
    en: 'Save failed — check the status at the bottom',
  ),
  '保存并重发': (zh: '保存并重发', en: 'Save and resend'),
  '写入': (zh: '写入', en: 'Write'),
  '写给模型看的要求，越具体越好。\n': (
    zh: '写给模型看的要求，越具体越好。\n',
    en: 'Requirements the model will read — the more specific, the better.\n',
  ),
  '创建': (zh: '创建', en: 'Create'),
  '创建并开始写': (zh: '创建并开始写', en: 'Create and start writing'),
  '删除本地副本，远端不受影响': (
    zh: '删除本地副本，远端不受影响',
    en: 'Delete the local copy; remote unaffected',
  ),
  '只从对话里移除，不改动任何文件。': (
    zh: '只从对话里移除，不改动任何文件。',
    en: 'Remove from the chat only; no files are touched.',
  ),
  '只删对话': (zh: '只删对话', en: 'Chat only'),
  '回车添加，可用逗号分隔': (zh: '回车添加，可用逗号分隔', en: 'Press Enter to add; commas allowed'),
  '已经转换过': (zh: '已经转换过', en: 'Already converted'),
  '恢复自动': (zh: '恢复自动', en: 'Restore automatic'),
  '恢复默认': (zh: '恢复默认', en: 'Restore default'),
  '想法不会被删除，只是解除归属': (
    zh: '想法不会被删除，只是解除归属',
    en: 'Notes are not deleted, just unassigned',
  ),
  '打开编辑': (zh: '打开编辑', en: 'Open editor'),
  '换令牌': (zh: '换令牌', en: 'Change token'),
  '接口地址': (zh: '接口地址', en: 'Endpoint URL'),
  '搜索想法标题和正文': (zh: '搜索想法标题和正文', en: 'Search note titles and bodies'),
  '撤销这次写入': (zh: '撤销这次写入', en: 'Undo this write'),
  '收起键盘': (zh: '收起键盘', en: 'Hide keyboard'),
  '文章信息已保存': (zh: '文章信息已保存', en: 'Post info saved'),
  '文章信息（分类/标签/日期）': (
    zh: '文章信息（分类/标签/日期）',
    en: 'Post info (category/tags/date)',
  ),
  '文章已删除': (zh: '文章已删除', en: 'Post deleted'),
  '无法重新生成：没有可重答的提问': (
    zh: '无法重新生成：没有可重答的提问',
    en: 'Cannot regenerate: no question to re-answer',
  ),
  '查找替换': (zh: '查找替换', en: 'Find & replace'),
  '生成文章': (zh: '生成文章', en: 'Generate post'),
  '用新地址覆盖本地副本': (zh: '用新地址覆盖本地副本', en: 'Overwrite local copy with the new URL'),
  '留空则用正文开头做摘要': (
    zh: '留空则用正文开头做摘要',
    en: 'Leave empty to use the start of the body as summary',
  ),
  '移动到分类': (zh: '移动到分类', en: 'Move to category'),
  '精选的想法会优先提供给 AI': (
    zh: '精选的想法会优先提供给 AI',
    en: 'Featured notes are offered to the AI first',
  ),
  '编辑（地址 / Key / 模型）': (
    zh: '编辑（地址 / Key / 模型）',
    en: 'Edit (URL / Key / Model)',
  ),
  '请先填写 GitHub 访问令牌': (
    zh: '请先填写 GitHub 访问令牌',
    en: 'Please enter a GitHub token first',
  ),
  '请先接入站点，再转换为文章': (
    zh: '请先接入站点，再转换为文章',
    en: 'Connect a site before converting to a post',
  ),
  '请填写标题': (zh: '请填写标题', en: 'Please enter a title'),
  '转为文章': (zh: '转为文章', en: 'Convert to post'),
  '这次改了什么': (zh: '这次改了什么', en: 'What changed this time'),
  '这篇文章还没有加载完成，稍后再试': (
    zh: '这篇文章还没有加载完成，稍后再试',
    en: 'This post is still loading — try again later',
  ),
  '重新读取变更': (zh: '重新读取变更', en: 'Reload changes'),

  // ── 自动补齐（页面文案）──
  'AI 读取想法的范围': (zh: 'AI 读取想法的范围', en: 'AI note reading scope'),
  '不删除对话，只把它们移回未分组': (
    zh: '不删除对话，只把它们移回未分组',
    en: 'Keep the chats, just move them back to Ungrouped',
  ),
  '不动文件，只从对话里移除': (
    zh: '不动文件，只从对话里移除',
    en: 'Leave files untouched; remove from the chat only',
  ),
  '保存为草稿': (zh: '保存为草稿', en: 'Save as draft'),
  '保存后会撤回这条及之后的对话，并回滚相关文件，再按新内容提问。': (
    zh: '保存后会撤回这条及之后的对话，并回滚相关文件，再按新内容提问。',
    en: 'Saving retracts this and later messages, rolls back related files, then asks again with the new content.',
  ),
  '保留这条回答，重新问一遍（不回滚文件）': (
    zh: '保留这条回答，重新问一遍（不回滚文件）',
    en: 'Keep this answer and ask again (files are not rolled back)',
  ),
  '允许读取想法': (zh: '允许读取想法', en: 'Allow reading notes'),
  '关闭时 AI 看不到任何想法，除非你在对话里指定': (
    zh: '关闭时 AI 看不到任何想法，除非你在对话里指定',
    en: 'When off, the AI sees no notes unless you specify them in the chat',
  ),
  '兼容 OpenAI 协议的地址都可以，\n可以配多个随时切换。': (
    zh: '兼容 OpenAI 协议的地址都可以，\n可以配多个随时切换。',
    en: 'Any OpenAI-compatible URL works;\nyou can add several and switch anytime.',
  ),
  '切换': (zh: '切换', en: 'Switch'),
  '切换端点与模型': (zh: '切换端点与模型', en: 'Switch endpoint and model'),
  '原始错误信息': (zh: '原始错误信息', en: 'Raw error message'),
  '只改强调色，错误红和警告黄保持不变——它们的颜色本身就是语义。': (
    zh: '只改强调色，错误红和警告黄保持不变——它们的颜色本身就是语义。',
    en: 'Only the accent changes; error red and warning yellow stay — their colors carry meaning.',
  ),
  '思考深度在对话页选，这里不用管': (
    zh: '思考深度在对话页选，这里不用管',
    en: 'Pick thinking depth in the chat page; ignore it here',
  ),
  '想法是私人内容，默认不读。打开后才允许读取。': (
    zh: '想法是私人内容，默认不读。打开后才允许读取。',
    en: 'Notes are private and not read by default. Enable to allow reading.',
  ),
  '把这条回复写过的文件恢复原样，对话保留': (
    zh: '把这条回复写过的文件恢复原样，对话保留',
    en: 'Restore the files this reply wrote, keeping the chat',
  ),
  '接入 Hugo 站点仓库后，就能在这里管理文章并推送到 GitHub。': (
    zh: '接入 Hugo 站点仓库后，就能在这里管理文章并推送到 GitHub。',
    en: 'Connect a Hugo site repo to manage posts here and push to GitHub.',
  ),
  '推送后由 GitHub 监听仓库自动部署，App 不直接触发构建。': (
    zh: '推送后由 GitHub 监听仓库自动部署，App 不直接触发构建。',
    en: 'After pushing, GitHub watches the repo and deploys automatically; the app does not trigger builds.',
  ),
  '提示：如果是偶发失败，直接重试通常就能成功。': (
    zh: '提示：如果是偶发失败，直接重试通常就能成功。',
    en: 'Tip: for a transient failure, retrying usually works.',
  ),
  '撤回这条及之后，再问一次': (
    zh: '撤回这条及之后，再问一次',
    en: 'Retract this and after, then ask again',
  ),
  '改完会撤回这条及之后的对话，并回滚相关文件': (
    zh: '改完会撤回这条及之后的对话，并回滚相关文件',
    en: 'After editing, this and later messages are retracted and related files rolled back',
  ),
  '整个 App 只需要填这一次。站点接入和推送都会自动复用。': (
    zh: '整个 App 只需要填这一次。站点接入和推送都会自动复用。',
    en: 'Fill this once for the whole app. Site connection and push reuse it automatically.',
  ),
  '没有未提交的改动。': (zh: '没有未提交的改动。', en: 'No uncommitted changes.'),
  '点选模型（已过滤掉 embedding/tts 等不能对话的）': (
    zh: '点选模型（已过滤掉 embedding/tts 等不能对话的）',
    en: 'Pick a model (embedding/tts and other non-chat models are filtered out)',
  ),
  '笔记正文会成为文章正文。分类和标签与笔记分类无关。': (
    zh: '笔记正文会成为文章正文。分类和标签与笔记分类无关。',
    en: 'The note body becomes the post body. Categories and tags are unrelated to note categories.',
  ),
  '草稿不会出现在站点上，可在编辑器里随时转为发布': (
    zh: '草稿不会出现在站点上，可在编辑器里随时转为发布',
    en: 'Drafts never appear on the site; switch to published anytime in the editor',
  ),
  '还没有分组。可以在想法页新建分组后再回来限定范围。': (
    zh: '还没有分组。可以在想法页新建分组后再回来限定范围。',
    en: 'No groups yet. Create groups on the Notes page, then come back to narrow the scope.',
  ),
  '还没有分组，点右上角文件夹图标新建': (
    zh: '还没有分组，点右上角文件夹图标新建',
    en: 'No groups yet — tap the folder icon at the top right to create one',
  ),
  '重命名分类': (zh: '重命名分类', en: 'Rename category'),
  '限定分组（不选 = 全部）': (zh: '限定分组（不选 = 全部）', en: 'Limit groups (none = all)'),
  '首次克隆可能要几十秒，请保持网络畅通。': (
    zh: '首次克隆可能要几十秒，请保持网络畅通。',
    en: 'The first clone may take a while — keep the network connected.',
  ),

  // ── 自动补齐（页面文案）──
  'Hugo 构建时不会输出这篇': (
    zh: 'Hugo 构建时不会输出这篇',
    en: 'Hugo will not output this post when building',
  ),
  '[图片]': (zh: '[图片]', en: '[Image]'),
  '不读取任何想法': (zh: '不读取任何想法', en: 'Read no notes'),
  '不限': (zh: '不限', en: 'Unlimited'),
  '从列表选': (zh: '从列表选', en: 'Choose from list'),
  '修改文章': (zh: '修改文章', en: 'Edit post'),
  '先填接口地址': (zh: '先填接口地址', en: 'Enter the endpoint URL first'),
  '关闭时 AI 看不到任何想法（在对话里指定分组或想法除外）': (
    zh: '关闭时 AI 看不到任何想法（在对话里指定分组或想法除外）',
    en: 'When off, the AI sees no notes (except groups or notes named in the chat)',
  ),
  '写给模型看的要求，越具体越好。\n建议同时写清「不要做什么」。': (
    zh: '写给模型看的要求，越具体越好。\n建议同时写清「不要做什么」。',
    en: 'Requirements the model will read — the more specific, the better.\nAlso spell out what NOT to do.',
  ),
  '分类名称': (zh: '分类名称', en: 'Category name'),
  '删掉这条提问及其后的全部对话': (
    zh: '删掉这条提问及其后的全部对话',
    en: 'Delete this question and all messages after it',
  ),
  '发布这篇': (zh: '发布这篇', en: 'Publish this'),
  '只删掉这条回复': (zh: '只删掉这条回复', en: 'Delete only this reply'),
  '回收站是空的\n删掉的文章会先放到这里': (
    zh: '回收站是空的\n删掉的文章会先放到这里',
    en: 'Trash is empty\nDeleted posts land here first',
  ),
  '填到 /v1 就行，不用写 /chat/completions': (
    zh: '填到 /v1 就行，不用写 /chat/completions',
    en: 'Just up to /v1 — no need for /chat/completions',
  ),
  '存在应用私有目录，权限 0600': (
    zh: '存在应用私有目录，权限 0600',
    en: 'Stored in the app\'s private dir, mode 0600',
  ),
  '对话和文件一起回滚': (zh: '对话和文件一起回滚', en: 'Roll back chat and files together'),
  '将只删除这条回复，上面的提问会保留。': (
    zh: '将只删除这条回复，上面的提问会保留。',
    en: 'Only this reply is deleted; the question above is kept.',
  ),
  '尚未发送，想法读取范围未生效': (
    zh: '尚未发送，想法读取范围未生效',
    en: 'Not sent yet — note reading scope not applied',
  ),
  '已发布，构建时会输出': (zh: '已发布，构建时会输出', en: 'Published — output at build time'),
  '已撤回对话': (zh: '已撤回对话', en: 'Chat retracted'),
  '已改为草稿': (zh: '已改为草稿', en: 'Changed to draft'),
  '已清除令牌': (zh: '已清除令牌', en: 'Token cleared'),
  '已移到回收站': (zh: '已移到回收站', en: 'Moved to trash'),
  '手动输入': (zh: '手动输入', en: 'Enter manually'),
  '执行记录': (zh: '执行记录', en: 'Run log'),
  '接口地址要以 http:// 或 https:// 开头': (
    zh: '接口地址要以 http:// 或 https:// 开头',
    en: 'Endpoint URL must start with http:// or https://',
  ),
  '撤回': (zh: '撤回', en: 'Retract'),
  '改为草稿': (zh: '改为草稿', en: 'Change to draft'),
  '文章数': (zh: '文章数', en: 'Post count'),
  '文章目录': (zh: '文章目录', en: 'Table of contents'),
  '未设置（保存时自动填今天）': (
    zh: '未设置（保存时自动填今天）',
    en: 'Not set (fills today\'s date on save)',
  ),
  '没有匹配的仓库': (zh: '没有匹配的仓库', en: 'No matching repositories'),
  '没有匹配的想法': (zh: '没有匹配的想法', en: 'No matching notes'),
  '没有已归档的对话': (zh: '没有已归档的对话', en: 'No archived chats'),
  '没有符合条件的文章': (zh: '没有符合条件的文章', en: 'No posts match the filter'),
  '添加分类，回车确认': (zh: '添加分类，回车确认', en: 'Add a category, press Enter'),
  '添加分类，回车确认（可逗号分隔）': (
    zh: '添加分类，回车确认（可逗号分隔）',
    en: 'Add a category, Enter to confirm (commas allowed)',
  ),
  '添加标签，回车确认': (zh: '添加标签，回车确认', en: 'Add a tag, press Enter'),
  '添加标签，回车确认（可逗号分隔）': (
    zh: '添加标签，回车确认（可逗号分隔）',
    en: 'Add a tag, Enter to confirm (commas allowed)',
  ),
  '留空则不修改': (zh: '留空则不修改', en: 'Leave empty to keep unchanged'),
  '留空则使用已保存的令牌': (zh: '留空则使用已保存的令牌', en: 'Leave empty to use the saved token'),
  '看全文': (zh: '看全文', en: 'View full text'),
  '看差异': (zh: '看差异', en: 'View diff'),
  '自动（跟随 GitHub 账号）': (
    zh: '自动（跟随 GitHub 账号）',
    en: 'Automatic (follow GitHub account)',
  ),
  '请先到「站点」页接入 Git 仓库': (
    zh: '请先到「站点」页接入 Git 仓库',
    en: 'Connect a Git repo on the Site page first',
  ),
  '请先填写访问令牌': (zh: '请先填写访问令牌', en: 'Please enter a token first'),
  '请填写作者名': (zh: '请填写作者名', en: 'Please enter an author name'),
  '请填写作者邮箱': (zh: '请填写作者邮箱', en: 'Please enter an author email'),
  '请填写接口地址': (zh: '请填写接口地址', en: 'Please enter the endpoint URL'),
  '请输入令牌': (zh: '请输入令牌', en: 'Please enter a token'),
  '读取全部想法（在想法页指定分组可缩小范围）': (
    zh: '读取全部想法（在想法页指定分组可缩小范围）',
    en: 'Read all notes (pick groups on the Notes page to narrow scope)',
  ),
  '还没有想法\n随手记一句，之后可以一键转成文章': (
    zh: '还没有想法\n随手记一句，之后可以一键转成文章',
    en: 'No notes yet\nJot one down — convert it to a post anytime',
  ),
  '还没有精选想法\n精选的想法会优先提供给 AI': (
    zh: '还没有精选想法\n精选的想法会优先提供给 AI',
    en: 'No featured notes yet\nFeatured notes are offered to the AI first',
  ),
  '还没有记忆，AI 会在对话中自动学习': (
    zh: '还没有记忆，AI 会在对话中自动学习',
    en: 'No memory yet — the AI learns as you chat',
  ),
  '这个令牌看不到任何仓库': (
    zh: '这个令牌看不到任何仓库',
    en: 'This token cannot see any repositories',
  ),
  '这个端点没有返回任何模型，可以直接手填模型名': (
    zh: '这个端点没有返回任何模型，可以直接手填模型名',
    en: 'This endpoint returned no models — enter a model name manually',
  ),
  '这个端点没有返回模型列表，直接手填模型名': (
    zh: '这个端点没有返回模型列表，直接手填模型名',
    en: 'This endpoint returned no model list — enter a model name manually',
  ),
  '这条回复': (zh: '这条回复', en: 'This reply'),
  '这条提问': (zh: '这条提问', en: 'This question'),
  '这篇稿件还没有文件路径，无法保存': (
    zh: '这篇稿件还没有文件路径，无法保存',
    en: 'This draft has no file path and cannot be saved',
  ),
  '选择发布日期': (zh: '选择发布日期', en: 'Choose publish date'),
  '邮箱格式不对': (zh: '邮箱格式不对', en: 'Invalid email format'),
  '随便起，比如「DeepSeek」「备用」': (
    zh: '随便起，比如「DeepSeek」「备用」',
    en: 'Any name, e.g. "DeepSeek", "Backup"',
  ),
  '需要 repo 权限才能看到私有仓库': (
    zh: '需要 repo 权限才能看到私有仓库',
    en: 'Needs repo scope to see private repositories',
  ),
  '需要 repo 权限（读写仓库内容）': (
    zh: '需要 repo 权限（读写仓库内容）',
    en: 'Needs repo scope (read/write repo contents)',
  ),
  '（估算）': (zh: '（估算）', en: ' (estimated)'),
  '（如 20240501-hello-world.md）': (
    zh: '（如 20240501-hello-world.md）',
    en: '(e.g. 20240501-hello-world.md)',
  ),
  '（如 hello-world.md）': (zh: '（如 hello-world.md）', en: '(e.g. hello-world.md)'),
  '（如 post-20240501-080309.md）': (
    zh: '（如 post-20240501-080309.md）',
    en: '(e.g. post-20240501-080309.md)',
  ),
  '（文件过大，不逐行比对）': (
    zh: '（文件过大，不逐行比对）',
    en: '(file too large — no line-by-line diff)',
  ),
  '（还没有可选的模型）': (zh: '（还没有可选的模型）', en: '(no selectable models yet)'),

  // ── 自动补齐（页面文案）──
  'GitHub 靠邮箱把提交关联到你的账号。邮箱不对的话，提交会显示成陌生名字，贡献格子也不会亮。': (
    zh: 'GitHub 靠邮箱把提交关联到你的账号。邮箱不对的话，提交会显示成陌生名字，贡献格子也不会亮。',
    en: 'GitHub links commits to your account by email. With a wrong email, commits show an unfamiliar name and the contribution graph stays dark.',
  ),
  '令牌只用于本机发起 Git 请求，保存在应用私有目录，不上传任何服务器。\n': (
    zh: '令牌只用于本机发起 Git 请求，保存在应用私有目录，不上传任何服务器。\n',
    en: 'The token is only used for Git requests from this device, stored in the app\'s private dir, never uploaded.\n',
  ),
  '冲突未解决前无法提交。请在电脑上处理冲突，或重新克隆一份干净的仓库。': (
    zh: '冲突未解决前无法提交。请在电脑上处理冲突，或重新克隆一份干净的仓库。',
    en: 'Cannot commit until conflicts are resolved. Resolve them on a computer, or re-clone a clean copy.',
  ),
  '启用后会追加到 System Prompt，规定这一轮「怎么做」。可以同时开多个，也能随时关掉。': (
    zh: '启用后会追加到 System Prompt，规定这一轮「怎么做」。可以同时开多个，也能随时关掉。',
    en: 'When enabled, it is appended to the System Prompt to define "how" for this round. Enable several at once and turn them off anytime.',
  ),
  '填一个兼容 OpenAI 协议的地址就能用。\nOpenAI、DeepSeek、各家中转站、本地 Ollama 都支持。': (
    zh: '填一个兼容 OpenAI 协议的地址就能用。\nOpenAI、DeepSeek、各家中转站、本地 Ollama 都支持。',
    en: 'Any OpenAI-compatible URL works.\nOpenAI, DeepSeek, proxies, and local Ollama are all supported.',
  ),
  '已推送到 GitHub。如果你的站点由 Vercel 等平台托管，平台会监听仓库自动开始构建，无需手动触发。': (
    zh: '已推送到 GitHub。如果你的站点由 Vercel 等平台托管，平台会监听仓库自动开始构建，无需手动触发。',
    en: 'Pushed to GitHub. If your site is hosted on Vercel or similar, the platform watches the repo and builds automatically — no manual trigger.',
  ),
  '这些文章还没有分类或标签。在文章 Front Matter 里加 categories / tags 后即可在这里筛选。': (
    zh: '这些文章还没有分类或标签。在文章 Front Matter 里加 categories / tags 后即可在这里筛选。',
    en: 'These posts have no categories or tags yet. Add categories / tags in the Front Matter to filter here.',
  ),
  '远端有本地没有的改动。直接推送会被拒绝，请先到「站点」页重新克隆同步。': (
    zh: '远端有本地没有的改动。直接推送会被拒绝，请先到「站点」页重新克隆同步。',
    en: 'The remote has changes you don\'t have locally. Pushing directly will be rejected — re-clone to sync on the Site page first.',
  ),

  // ── 自动补齐（页面文案）──
  '已设置 {}': (zh: '已设置 {}', en: 'Set: {}'),
  '{} · 邮箱自动推断': (zh: '{} · 邮箱自动推断', en: '{} · email auto-inferred'),
  '{} · {}': (zh: '{} · {}', en: '{} · {}'),
  '名称自动': (zh: '名称自动', en: 'Name auto'),
  '已记住 {} 条（可查看、修改、删除）': (
    zh: '已记住 {} 条（可查看、修改、删除）',
    en: 'Remembered {} items (view, edit, delete)',
  ),
  '已关掉 {} 个（模型看不到它们）': (
    zh: '已关掉 {} 个（模型看不到它们）',
    en: '{} turned off (model cannot see them)',
  ),
  '{} 个可用，当前未启用': (zh: '{} 个可用，当前未启用', en: '{} available, none enabled'),
  '当前启用 {} 个 / 共 {} 个': (zh: '当前启用 {} 个 / 共 {} 个', en: '{} enabled / {} total'),
  '已选 {} 个': (zh: '已选 {} 个', en: '{} selected'),
  '已自定义（{} 字）': (zh: '已自定义（{} 字）', en: 'Customized ({} chars)'),
  '超过 {} 条开始折叠，保留最近 {} 条': (
    zh: '超过 {} 条开始折叠，保留最近 {} 条',
    en: 'Fold after {} messages, keep the latest {}',
  ),
  '{}（超过即中止本轮）': (zh: '{}（超过即中止本轮）', en: '{} (abort the round when exceeded)'),
  '决定 AI 的角色、文章规范与行为边界。「恢复默认」会丢弃你的修改。': (
    zh: '决定 AI 的角色、文章规范与行为边界。「恢复默认」会丢弃你的修改。',
    en: 'Defines the AI\'s role, writing rules, and boundaries. "Restore default" discards your changes.',
  ),
  '写入 Front Matter 的 date 字段。Hugo 三种都能解析，但如果主题或时间线功能要求严格 ISO8601，选带时区那种。': (
    zh: '写入 Front Matter 的 date 字段。Hugo 三种都能解析，但如果主题或时间线功能要求严格 ISO8601，选带时区那种。',
    en: 'Written to the Front Matter date field. Hugo parses all three; if your theme or timeline needs strict ISO8601, pick the timezone variant.',
  ),
  '只影响以后新建的文章，已存在的文件不会改名。同名时自动加 -2、-3 后缀，绝不覆盖。': (
    zh: '只影响以后新建的文章，已存在的文件不会改名。同名时自动加 -2、-3 后缀，绝不覆盖。',
    en: 'Only affects posts created later; existing files are not renamed. Same names get -2, -3 suffixes — never overwritten.',
  ),
  '超过阈值后，较早的消息会被折叠成摘要，最近几条原样保留。\n下限 4 / 上限 200。保留数必须小于阈值。': (
    zh: '超过阈值后，较早的消息会被折叠成摘要，最近几条原样保留。\n下限 4 / 上限 200。保留数必须小于阈值。',
    en: 'Past the threshold, older messages are folded into a summary; the most recent are kept as-is.\nRange 4–200. Keep count must be less than the threshold.',
  ),
  '开启后 AI 可以读到你的想法': (
    zh: '开启后 AI 可以读到你的想法',
    en: 'When on, the AI can read your notes',
  ),

  // ── 自动补齐（页面文案）──
  '[图片: {}]': (zh: '[图片: {}]', en: '[Image: {}]'),
  '{} / {} 条': (zh: '{} / {} 条', en: '{} / {}'),
  '{} · 未选模型': (zh: '{} · 未选模型', en: '{} · no model selected'),
  '{} 个仓库': (zh: '{} 个仓库', en: '{} repos'),
  '{} 个对话': (zh: '{} 个对话', en: '{} chats'),
  '{} 个文件存在合并冲突': (zh: '{} 个文件存在合并冲突', en: '{} files have merge conflicts'),
  '{} 分钟前': (zh: '{} 分钟前', en: '{} min ago'),
  '{} 天前': (zh: '{} 天前', en: '{} days ago'),
  '{} 字': (zh: '{} 字', en: '{} chars'),
  '{} 小时前': (zh: '{} 小时前', en: '{} hr ago'),
  '{} 已归档，无法推送': (zh: '{} 已归档，无法推送', en: '{} is archived and cannot be pushed'),
  '{} 是空仓库，先给它加一个提交再接入': (
    zh: '{} 是空仓库，先给它加一个提交再接入',
    en: '{} is empty — add a commit before connecting',
  ),
  '{} 条': (zh: '{} 条', en: '{} items'),
  '{} 条 · {}': (zh: '{} 条 · {}', en: '{} items · {}'),
  '{} 篇': (zh: '{} 篇', en: '{} posts'),
  '{}\n\n此操作不可恢复。': (zh: '{}\n\n此操作不可恢复。', en: '{}\n\nThis cannot be undone.'),
  '{}\n\n要打开那篇文章，还是再生成一篇？': (
    zh: '{}\n\n要打开那篇文章，还是再生成一篇？',
    en: '{}\n\nOpen that post, or generate another?',
  ),
  '{}\n{}': (zh: '{}\n{}', en: '{}\n{}'),
  '{}（生成中，暂不可切换）': (
    zh: '{}（生成中，暂不可切换）',
    en: '{} (generating — cannot switch yet)',
  ),
  '· {} 字': (zh: '· {} 字', en: '· {} chars'),
  '「{}」将被删除。': (zh: '「{}」将被删除。', en: '"{}" will be deleted.'),
  '修改失败：{}': (zh: '修改失败：{}', en: 'Failed to update: {}'),
  '全部 {}': (zh: '全部 {}', en: 'All {}'),
  '共 {} 个文件': (zh: '共 {} 个文件', en: '{} files in total'),
  '分类：{}': (zh: '分类：{}', en: 'Category: {}'),
  '删除「{}」？它的 API Key 也会一起删掉。': (
    zh: '删除「{}」？它的 API Key 也会一起删掉。',
    en: 'Delete "{}"? Its API key will be removed too.',
  ),
  '删除于 {}': (zh: '删除于 {}', en: 'Deleted {}'),
  '删除失败：{}': (zh: '删除失败：{}', en: 'Failed to delete: {}'),
  '参数：{}\n\n{}': (zh: '参数：{}\n\n{}', en: 'Args: {}\n\n{}'),
  '回收站 · {}': (zh: '回收站 · {}', en: 'Trash · {}'),
  '回收站（{}）': (zh: '回收站（{}）', en: 'Trash ({})'),
  '导入失败：{}': (zh: '导入失败：{}', en: 'Import failed: {}'),
  '导出失败：{}': (zh: '导出失败：{}', en: 'Export failed: {}'),
  '将写入 {} 字符': (zh: '将写入 {} 字符', en: 'Will write {} characters'),
  '将删除这条提问及其之后的 {} 条消息。': (
    zh: '将删除这条提问及其之后的 {} 条消息。',
    en: 'This deletes the question and the {} messages after it.',
  ),
  '将永久删除 {} 条笔记，无法恢复。': (
    zh: '将永久删除 {} 条笔记，无法恢复。',
    en: 'Permanently delete {} notes — this cannot be undone.',
  ),
  '将永久删除 {} 篇文章，无法恢复。': (
    zh: '将永久删除 {} 篇文章，无法恢复。',
    en: 'Permanently delete {} posts — this cannot be undone.',
  ),
  '已保存：{}': (zh: '已保存：{}', en: 'Saved: {}'),
  '已保存：{}（点下方输入框可替换）': (
    zh: '已保存：{}（点下方输入框可替换）',
    en: 'Saved: {} (tap the field below to replace)',
  ),
  '已删除 {} 条': (zh: '已删除 {} 条', en: 'Deleted {} items'),
  '已发布 {}': (zh: '已发布 {}', en: 'Published {}'),
  '已归档 {}': (zh: '已归档 {}', en: 'Archived {}'),
  '已折叠 {} 条': (zh: '已折叠 {} 条', en: 'Folded {} items'),
  '已折叠 {} 条消息': (zh: '已折叠 {} 条消息', en: 'Folded {} messages'),
  '已撤回对话，并恢复 {} 个文件': (
    zh: '已撤回对话，并恢复 {} 个文件',
    en: 'Chat retracted and {} files restored',
  ),
  '已替换 {} 处': (zh: '已替换 {} 处', en: 'Replaced {} occurrences'),
  '已永久删除 {} 篇': (zh: '已永久删除 {} 篇', en: 'Permanently deleted {} posts'),
  '已验证为 {}，已保存': (zh: '已验证为 {}，已保存', en: 'Verified as {} and saved'),
  '思考档位：{}，点击切换': (
    zh: '思考档位：{}，点击切换',
    en: 'Thinking level: {} — tap to switch',
  ),
  '恢复失败：{}': (zh: '恢复失败：{}', en: 'Failed to restore: {}'),
  '提交 {}': (zh: '提交 {}', en: 'Commit {}'),
  '撤销写入（{} 个文件）': (zh: '撤销写入（{} 个文件）', en: 'Undo write ({} files)'),
  '文件：{}': (zh: '文件：{}', en: 'File: {}'),
  '文章 · {}': (zh: '文章 · {}', en: 'Posts · {}'),
  '无法读取文件：{}': (zh: '无法读取文件：{}', en: 'Cannot read file: {}'),
  '标签：{}': (zh: '标签：{}', en: 'Tags: {}'),
  '格式：{}': (zh: '格式：{}', en: 'Format: {}'),
  '正在执行 {}…': (zh: '正在执行 {}…', en: 'Running {}…'),
  '活跃 {}': (zh: '活跃 {}', en: 'Active {}'),
  '筛选结果 · {}': (zh: '筛选结果 · {}', en: 'Filtered · {}'),
  '约 {}': (zh: '约 {}', en: '~ {}'),
  '草稿 {}': (zh: '草稿 {}', en: 'Drafts {}'),
  '落后远端 {} 个提交': (zh: '落后远端 {} 个提交', en: 'Behind remote by {} commits'),
  '记忆库（{}）': (zh: '记忆库（{}）', en: 'Memory ({})'),
  '还有 {} 篇，在「文章」页查看全部': (
    zh: '还有 {} 篇，在「文章」页查看全部',
    en: '{} more — see all on the Posts page',
  ),
  '这段对话写过 {} 个文件：': (zh: '这段对话写过 {} 个文件：', en: 'This chat wrote {} files:'),

  // ── 编辑器预览 ──
  '正文还是空的': (zh: '正文还是空的', en: 'The body is empty'),
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
