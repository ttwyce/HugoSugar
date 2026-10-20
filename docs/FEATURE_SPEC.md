# HugoSugar — 产品与技术方案（封版 v4）

> **状态**：需求已封版，可进入开发。
> **沿革**：v1 全量摸底 → v2 范围收窄 → v3 补联网与存储 → v4 定案。
> **一句话**：把「重建整个博客工作站」收窄为「Markdown 写作 App + Git 推送 + 写作 AI」。

---

## 一、产品定义

> **HugoSugar —— 在手机上写 Hugo 文章，写完一键推到 GitHub。构建交给 Vercel，本地一概不管。**
>
> 笔记用来抓灵感，AI Agent 帮你把灵感变成文章。

### 1.1 目标用户

自己用 Hugo 建站、部署在 Vercel/Netlify 的写作者，主要痛点是「灵感来了手边只有手机」。

### 1.2 核心场景

| 场景 | 流程 |
|---|---|
| 抓灵感 | 想到一句话 → 记进笔记 → 丢那里 |
| 写文章 | 打开笔记 → 转成文章 → 编辑 → 预览 → 保存 |
| 发布 | 提交 → push → （可选）触发 Vercel 部署 → 线上生效 |
| 让 AI 帮忙 | 给 AI 一个网址读文档 → 让 AI 结合我的笔记写初稿 → 我看着 Diff 确认 |

### 1.3 明确不做

- ❌ 本地 Hugo 构建 / 本地 server 预览
- ❌ Hugo 二进制版本管理
- ❌ 内置终端
- ❌ Shell 脚本管理
- ❌ 富文本 / WYSIWYG 编辑器

---

## 二、技术路线

| 项 | 决议 | 理由 |
|---|---|---|
| 项目名 | **HugoSugar** | — |
| 包名（pubspec） | `hugosugar` | 应用 ID 建议 `com.ttwyce.hugosugar` |
| 框架 | **纯 Flutter** | 终端已砍，不再需要原生插件 |
| 状态管理 | Riverpod | 便于分层与测试 |
| 目标平台 | Android（首发）→ iOS → Desktop | 三端共用一套代码，几乎零分支 |
| 原生代码量 | **约 80 行 Kotlin**（仅 SAF 目录选择，M6 才做） | 其余全 Dart |

### 2.1 为什么 iOS 是一等公民

原方案的 iOS 障碍只有一个：终端需要 `fork/exec`（iOS 禁止）。终端砍掉后，写作、Git、AI、笔记全部是纯 Dart 能做的事，iOS 与 Android 无差别。

---

## 三、功能范围

### 3.1 砍掉的（相对原始 HugoDesk，约 7,000 行）

| 模块 | 原行数 | 处置 |
|---|---|---|
| 终端模拟器（PTY / ANSI / 选区 / 附加键） | ~5,000 | 全砍 |
| Busybox + env.tar.xz + libexec.so | 二进制 | 全砍 |
| Hugo 版本管理（多版本 / 软链 / deb / xz） | ~700 | 全砍 |
| 本地构建 + 实时 server 预览 | ~500 | 全砍 → 换 Vercel Deploy Hook |
| Shell 脚本管理 + `cmdExer` | ~400 | 全砍 |
| `Safety` 命令风险分级 | 半 | 缩为 PathGuard（约 30 行） |
| AI 工具 `run_command` / `site_info` / `delete_path` | — | 全砍 |

### 3.2 保留并重做

| 模块 | 内容 | 优先级 |
|---|---|---|
| **文章管理** | 列表（文章/单页/草稿）、Front Matter 生成、新建、草稿发布切换 | P0 |
| **Markdown 编辑器** | 语法高亮、查找替换、自动保存、字数统计 | P0 |
| **笔记（灵感）** | CRUD、分类、置顶、回收站、搜索、转文章 | P0 |
| **Git 推送** | PAT 登录、clone / pull / commit / push、变更列表 | P0 |
| **AI 写作 Agent** | 流式对话、6 个工具、审批、Diff、撤销 | P1 |
| 预览 | Markdown 本地渲染（非 Hugo 渲染，不解析 shortcode） | P1 |
| 主题配色 | 7 套 + Material You 动态取色 | P2 |
| Vercel Deploy Hook | push 后可选触发部署 | P2 |
| SAF 目录导出/导入 | 文件对用户可见 | P2（M6） |

---

## 四、核心设计决议

### 决议 1：单站点，但接口按多站点设计

**现状**：只有单站点。**约束**：任何一层都不得假设「世界上只有一个站点」。

原则：**单站点是「当前只有一个」的特例，不是架构假设。**

```dart
class Site {
  final String id;          // 稳定 uuid，不是路径
  final String name;
  final String localPath;   // 本地仓库根目录
  final String? remoteUrl;  // origin
  final String contentDir;  // 相对路径，默认 "content/posts"
  final String? deployHook; // Vercel Deploy Hook URL
  final DateTime lastOpened;
}

abstract interface class SiteRepository {
  Future<List<Site>> all();
  Future<Site?> byId(String id);
  Future<void> upsert(Site site);
  Future<void> remove(String id);
}

abstract interface class ActiveSiteStore {
  Stream<Site?> watch();     // null = 尚未打开任何站点
  Future<void> select(String id);
  Future<void> clear();
}
```

**三条必须守住的纪律**（决定将来加多站点是改 UI 还是改全仓）：

1. **禁止 `SiteManager.instance` 之类全局静态单例**。当前站点只能来自 `ActiveSiteStore`。
2. **所有业务方法显式传 `siteId`**。禁止「省略参数就取当前站点」的隐式约定——这种便利写法正是把单站点假设焊进每个签名的方式。
3. **UI 不把 `Site` 缓存成成员字段**，一律 `watch()`，切站点自动刷新。

> 单站点实现：`SqliteSiteRepository` + `SingleActiveSiteStore`。
> 将来加多站点：只需补 UI（站点列表页、切换器），**业务层零改动**。

### 决议 2：笔记是 AI 的一等数据源

笔记不只是 App 里一个页面，必须同时是 AI 的数据源。

```dart
class Note {
  final String id;
  String title;
  String content;          // Markdown
  String? categoryId;
  bool pinned;             // ★ 置顶 = 自动进 System Prompt
  DateTime createdAt, updatedAt;
  DateTime? deletedAt;     // 非空 = 回收站
  String? convertedPostId; // 转成文章后记录，防重复转换
}
```

**双通道供给 AI**：

**通道 A —— 置顶笔记自动注入 System Prompt**（关键设计）

把 `#写作偏好` `#风格指南` `#常用术语` 这类笔记置顶，AI 每次对话自动带着这些背景，不用反复解释。

```dart
String buildSystemPrompt(String basePrompt, List<Note> pinnedNotes) {
  final buf = StringBuffer(basePrompt);
  final active = pinnedNotes.where((n) => n.deletedAt == null).toList();
  if (active.isEmpty) return buf.toString();

  buf.writeln('\n## 作者的写作偏好与背景（来自置顶笔记）\n');
  var budget = 4000; // 总字符预算，防止撑爆上下文
  for (final n in active) {
    if (budget <= 0) break;
    final body = n.content.length > budget
        ? '${n.content.substring(0, budget)}\n…（已截断）'
        : n.content;
    buf.writeln('### ${n.title}\n$body\n');
    budget -= body.length;
  }
  return buf.toString();
}
```

**通道 B —— 3 个检索工具**（见决议 3），模型需要具体细节时主动去查。

**「灵感 → 文章」转换流**：

```
笔记页 → 点「转为文章」
  → 表单：标题（取笔记标题）/ 分类 / 标签 / description / slug
  → 写入 content/posts/<slug>.md（Front Matter + 笔记正文）
  → note.convertedPostId = 新路径
  → 跳进编辑器
```

### 决议 3：AI Agent 工具集（6 个，全平台可用）

| 工具 | 需审批 | 说明 |
|---|---|---|
| `list_notes` | ✗ | 列笔记（可按分类 / 关键词过滤），返回 id + 标题 + 摘要 |
| `read_note` | ✗ | 读某条笔记全文 |
| `search_notes` | ✗ | 关键词全文搜索笔记 |
| `read_post` | ✗ | 读站点内已有文章（学 Front Matter 格式与文风） |
| `write_post` | ✅ | 写 / 覆盖文章，落盘前展示 Diff 并等用户确认 |
| `fetch_url` | ✗ | 抓取网页正文，用于读文档 / 参考资料 |

**刻意不提供**：
- **delete 类工具** —— 写文章不需要删东西，少一个高危面。
- **搜索类工具**（如 `web_search`）—— 用户给网址即可，不需要模型自行搜索。

#### 3.1 `fetch_url` 的边界（联网工具必须有护栏）

定位：**是「读」不是「爬」，更不是「执行」。**

| 约束 | 取值 | 理由 |
|---|---|---|
| 方法 | 仅 `GET` | 不允许 POST，杜绝「顺手发个请求」的副作用 |
| 协议 | 仅 `https` | 明文 HTTP 不出网 |
| 单次大小 | ≤ 512 KB，超出截断 | 防止大文件拖爆上下文 |
| 超时 | 15s | — |
| 重定向 | ≤ 3 跳，**每跳都重新校验私网** | 防 SSRF |
| 私网黑名单 | `127/8`、`10/8`、`172.16/12`、`192.168/16`、`169.254/16`、`::1`、`fc00::/7` | 否则模型可拿它探用户局域网 |
| 返回 | **纯文本**，不是原始 HTML | 省 token（原始 HTML 要多烧 5~10 倍） |
| 缓存 | 同 URL 24h 复用 | 避免多轮对话反复抓同一页 |

> **不做域名白名单**（已定案）。理由：用户的主要用法就是「临时给一个网址」，每次都弹窗批准会打断写作流。私网黑名单已足以防住 SSRF 这类真正的安全问题。

**HTML → 文本的实现要点**（用 `package:html`）：

1. 优先取 `article` → `main` → `body`（逐级降级）
2. 移除 `script` `style` `nav` `footer` `aside` `form`
3. `h1~h6` 前加 `#`×n，`li` 前加 `-`，保留结构
4. 空白压缩：连续空行折叠为一个

**Prompt 里的硬约束**（必须写进默认 System Prompt）：
> `fetch_url` 仅在用户明确给出网址、或需要查证具体文档时使用。不要主动联网搜索，不要连续抓取同一网站的多个页面。

#### 3.2 PathGuard（替代原 `Safety` 整套体系）

```dart
/// 返回 null 表示通过，否则返回拒绝原因
String? validatePostPath(Site site, String relPath) {
  final p = pkg.normalize(relPath);
  if (p.startsWith('..') || pkg.isAbsolute(p)) return '路径越界';
  if (!p.endsWith('.md')) return '只允许 .md 文件';
  final abs = pkg.join(site.contentDirAbs, p);
  if (!pkg.isWithin(site.contentDirAbs, abs)) return '路径越界';
  return null;
}
```

#### 3.3 Agent 循环

```
用户消息 (+ System Prompt 含置顶笔记)
   → 调 LLM（stream）
   → 若返回 tool_calls：
        ├─ 只读工具：直接执行，结果回灌，继续循环
        └─ write_post：暂停 → 弹 Diff 审批 → 用户确认才落盘 → 回灌 → 继续
   → 无 tool_call → 结束，渲染消息
```

**必须有的保护**：

| 保护 | 值 |
|---|---|
| 单轮最大工具调用次数 | 8 |
| 单轮最大 token | 由配置决定，超出提示 |
| 工具执行超时 | 只读 15s；`write_post` 等待用户无超时 |
| 撤销 | 每次 `write_post` 前备份原文件，支持一键回滚 |

### 决议 4：存储 —— 默认 App 私有目录

**定案**：`AppPrivateStorage`（`path_provider`），零权限，四端通。

**为什么不存 SD 卡**（这是被技术逼出来的，不是偷懒）：

| 事实 | 后果 |
|---|---|
| `libgit2` 要求**真实文件路径** | SAF 只给 `content://` URI，无法 `git clone/push` |
| SQLite（drift）要求真实路径 | `content://` 开不了库 |

而 **git push 是本 App 的主干功能**，不能为了文件可见性牺牲它。

**M6 的增强方案（可选）**：加「导出为 zip 到 SAF 目录」/「从 SAF 导入」，一次性拷贝，**不做实时镜像**——避免双向同步与冲突这种无底洞。

> 唯一需要的原生代码（M6）：约 80 行 Kotlin，实现 `ACTION_OPEN_DOCUMENT_TREE` + `takePersistableUriPermission`。只做目录选择，不执行任何进程，不破坏「纯 Flutter」前提。

**目录布局**：

```
<App私有目录>/
├─ hugosugar.db          # drift 数据库（站点、笔记元数据）
└─ sites/
   └─ <siteId>/          # 一个 Hugo 仓库
      ├─ .git/
      └─ content/posts/*.md
```

**抽象层纪律**：业务层只能用 `SiteStorage` 接口，**不许直接 `File()` 或 `path_provider`**。漏一个出来，将来接 SAF 就崩。

```dart
abstract interface class SiteStorage {
  Future<List<StorageEntry>> list(String relPath);
  Future<String> readText(String relPath);
  Future<void> writeText(String relPath, String content);
  Future<bool> exists(String relPath);
}
```

### 决议 5：内置默认 System Prompt（用户可编辑）

**定案**：内置一份基线 Prompt，设置页可查看、修改、一键恢复默认。
**存法**：默认值硬编码在 `default_prompt.dart`；用户改动后存 drift 表 `settings`；`当前值 = 用户覆盖 ?? 默认值`。

```dart
const kDefaultSystemPrompt = '''
你是一名中文技术博客写作助手，服务对象是一位使用 Hugo 建站、部署在 Vercel 的独立开发者。

## 你的职责
1. 帮助作者把零散灵感写成结构清晰的文章草稿。
2. 保持作者的既有文风与 Front Matter 格式。

## 文章规范
- 输出 Markdown，不使用 Hugo shortcode（除非作者明确要求）。
- Front Matter 使用 YAML，基础字段：title / date / draft / tags / categories / description。
- 代码块必须标注语言。
- 中文与英文、数字之间留一个空格。

## 工具使用规则
- 写文章前，先用 read_post 读 1~2 篇已有文章，学习格式与文风。
- 需要作者背景或偏好时，先用 search_notes / list_notes / read_note 查笔记。
- fetch_url 仅在用户明确给出网址、或需要查证具体文档时使用。
  不要主动联网搜索，不要连续抓取同一网站的多个页面。
- 修改已有文章时必须用 write_post，并在写入前说明改了什么。

## 行为边界
- 不编造作者未提供的经历、数据、引用。
- 不确定的技术细节要明确说「需要确认」，不要假装知道。
- 不输出与写作任务无关的内容。
''';
```

---

## 五、目录结构

```
lib/
├─ app/
│  ├─ app.dart
│  ├─ router/            # go_router，5 个 Tab
│  ├─ theme/             # 7 套配色 + Material You
│  └─ di/                # Riverpod providers 汇总
├─ core/
│  ├─ result/            # Result<T> / Failure
│  ├─ db/                # drift database + DAO
│  ├─ fs/                # ★ SiteStorage 抽象 + AppPrivateStorage
│  ├─ secure/            # flutter_secure_storage 包装（PAT / API Key）
│  └─ l10n/
├─ features/
│  ├─ site/              # ★ SiteRepository / ActiveSiteStore / PathGuard
│  ├─ post/              # 列表 + FrontMatter 解析/生成
│  ├─ note/              # CRUD / 分类 / 回收站 / 转文章
│  ├─ editor/            # Markdown 编辑器 + 查找替换
│  ├─ preview/           # md 本地渲染
│  ├─ git/               # libgit2dart 封装 + PAT 认证 + Deploy Hook
│  ├─ ai/
│  │  ├─ engine/         # 流式对话 + tool 循环 + 取消
│  │  ├─ tools/          # 6 个工具实现 + PathGuard
│  │  ├─ fetch/          # fetch_url + SSRF 拦截 + HTML→文本 + 缓存
│  │  ├─ profile/        # 多 API 配置（baseUrl / model / key）
│  │  └─ prompt/         # default_prompt.dart + SystemPrompt 构建
│  └─ settings/
└─ shared/               # 通用 Widget / 扩展
```

### 5.1 依赖清单

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_riverpod: ^2.5.1
  go_router: ^14.2.0
  drift: ^2.18.0
  sqlite3_flutter_libs: ^0.5.20
  path_provider: ^2.1.3
  path: ^1.9.0
  flutter_secure_storage: ^9.2.2
  libgit2dart: ^0.7.1          # ★ 唯一需冒烟验证的
  flutter_code_editor: ^0.3.2
  flutter_highlight: ^0.7.0
  flutter_markdown: ^0.7.2
  http: ^1.2.1
  uuid: ^4.4.0
  yaml: ^3.1.2                 # Front Matter 解析
  html: ^0.15.4                # fetch_url 的 HTML→文本
  intl: ^0.19.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^6.0.0
  drift_dev: ^2.18.0
  build_runner: ^2.4.11
```

---

## 六、里程碑

| # | 内容 | 验收标准 |
|---|---|---|
| **M0** | 骨架 + **git 冒烟** | 空壳可跑；**Android 跑通 clone → 改写 → push 到测试仓库** |
| **M1** | 站点接入 | clone 仓库、识别 `content/posts`、站点信息卡、`SiteStorage` 抽象落地 |
| **M2** | 文章 + 编辑器 | 四类列表、Front Matter 生成、语法高亮、查找替换、自动保存 |
| **M3** | 笔记 | CRUD、分类、置顶、回收站、搜索、**转文章** |
| **M4** | Git 推送 | 变更列表、commit message、push、冲突提示、Deploy Hook |
| **M5** | AI Agent | 流式对话、6 工具、审批 Diff、撤销、置顶笔记注入、`fetch_url` |
| **M6** | 打磨 | 主题、i18n、SAF 导出导入、桌面适配、iOS 打通 |

> **M0 的 git 冒烟是硬门槛。** 跑不通就停下重新选型，不要往下堆 UI。
> 备用方案：GitHub Contents API（纯 HTTP），代价是失去 clone 整仓与历史查看。

---

## 七、风险清单

| 风险 | 影响 | 应对 |
|---|---|---|
| `libgit2dart` 在 Android/iOS 链接失败 | 阻断 M4 | M0 先验证；备选 Contents API |
| 大仓库 clone 慢 / 超时 | 体验差 | 只 clone `content/` 相关分支？否——改用 shallow clone `--depth 1` |
| PAT 泄露 | 严重 | 存 `flutter_secure_storage`，不落日志，支持一键清除 |
| `fetch_url` 被抓去访问内网 | 安全 | 私网黑名单 + 每跳重校验 |
| 编辑器大文件卡顿 | 体验 | 超过 200KB 提示「文件较大」，关闭实时高亮 |
| AI 生成内容不合预期 | 体验 | 必须有 Diff 审批 + 撤销；置顶笔记提供风格约束 |

---

## 八、已定案清单（便于回查）

| 问题 | 结论 |
|---|---|
| 项目名 | **HugoSugar** |
| 是否要终端 | 不要；AI 也不需要（工具集无 run_command） |
| 是否本地构建 | 不要；构建交给 Vercel |
| 框架路线 | 纯 Flutter |
| 多站点 | 单站点，接口按多站点预留 |
| 笔记 | 保留，且作为 AI 数据源（置顶注入 + 3 工具） |
| 联网工具 | 要 `fetch_url`，设 SSRF / 大小 / 超时护栏 |
| 域名白名单 | 不做 |
| 存储位置 | App 私有目录（因 git 需要真实路径）；SAF 导出作 M6 增强 |
| 默认 System Prompt | 内置，用户可随时修改并可恢复默认 |

---

## 九、下一步

**M0 具体交付**：

1. 5 Tab 空壳（文章 / 笔记 / AI / 站点 / 设置），能跑起来
2. `core/fs/SiteStorage` 接口 + `AppPrivateStorage` 实现
3. **一个「Git 冒烟测试」调试页**：输入仓库 URL + PAT → 点按钮 → 依次执行 `clone → 改一个文件 → commit → push` → 页面显示每步日志
4. 跑通后删除该页面，进入 M1

> 先跑通，再优雅。
