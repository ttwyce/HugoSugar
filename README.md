# HugoSugar

> 在手机上写 Hugo 文章，写完一键推到 GitHub。构建交给 Vercel，本地一概不管。

HugoSugar 是一个专注**写作**的 Hugo 客户端。它不内置终端、不做本地构建、不管 Hugo 版本 —— 这些交给 CI。它只解决一件事：**灵感来了，手边只有手机。**

---

## 为什么做这个

用 Hugo 建站的人在手机上写作，通常要面对两种情况：

- **网页版 CMS / GitHub 网页编辑器**：能改，但写作体验很差，没有沉浸感
- **同步到本地再推**：手机上根本没有能跑 Hugo 的完整终端环境

HugoSugar 的思路是换一个前提：**既然部署交给 Vercel，本地就不需要构建能力。**

于是整个 App 只需要三件事：一个 Markdown 编辑器、一个 Git 推送通道、一个写文章时能搭把手的 AI。范围收得很窄，但每一块都做扎实。

---

## 功能范围

### 做

| 模块 | 说明 |
|---|---|
| **文章** | 四类列表（全部 / 草稿 / 已发布 / 回收站）、Front Matter 生成、查找替换、自动保存 |
| **编辑器** | 正文优先的极简界面，顶栏输入 2 秒后淡出；亮暗双主题 |
| **笔记** | 灵感速记，支持分类、置顶、搜索，可一键转成文章 |
| **Git** | 变更列表、提交信息、推送、冲突提示、Deploy Hook 触发 |
| **AI 写作助手** | 流式对话、6 个工具、写入前审批 Diff、可撤销；对话撤回 / 重发 / 编辑；System Prompt 可编辑；多端点与模型热切换 |

### 不做

| 不做 | 原因 |
|---|---|
| 本地 Hugo 构建 / 实时预览 | 部署在 Vercel，本地构建没有收益 |
| 内置终端（PTY / ANSI / Busybox） | 这是最大的工程量，且 iOS 上无解 |
| Hugo 版本管理 | 同上 |
| Shell 脚本管理 | 用不到 |
| 富文本编辑器 | 写 Hugo 就是写 Markdown |

砍掉这五块，省下约 7,000 行代码，也让 **iOS 成为一等公民**（iOS 沙盒禁止 `fork()`/`exec()`，终端和本地构建在那边彻底不可行，但 Git 可以走 `libgit2` 链接库）。

---

## 技术选型

| 方面 | 选择 | 理由 |
|---|---|---|
| 框架 | Flutter | 一套代码覆盖 Android / iOS / Desktop |
| Git | [`git2dart`](https://pub.dev/packages/git2dart) ^0.5.6 | 纯 FFI 绑定 libgit2，不需要进程，iOS 可用 |
| 状态管理 | 暂用 `ChangeNotifier` | 当前只有一个页面消费站点状态，等 M2 需要时再升级 |
| 存储 | App 私有目录 | 不需要任何权限，卸载即清；`libgit2` 和 SQLite 都需要真实文件路径，SAF 只给 `content://` URI |

> ⚠️ **不要用 `libgit2dart`**。它已标记 DISCONTINUED，且只支持 64 位 Linux/macOS/Windows，**不支持 Android/iOS**。
> 两者名字很像，选错了整个项目会卡死在第一步。

---

## 里程碑

| # | 内容 | 状态 |
|---|---|---|
| **M0** | 骨架 + Git 冒烟验证 | ✅ 已跑通 |
| **M1** | 站点接入（clone / 识别 `content/posts` / 站点信息卡） | ✅ 已完成 |
| M2 | 文章 + 编辑器（Front Matter、语法高亮、自动保存） | ✅ 已完成 |
| M3 | 笔记 / 想法（CRUD、置顶、回收站、转文章） | ✅ 已完成 |
| M4 | Git 推送（变更列表、commit、push、Deploy Hook） | ✅ 已完成（待真机验证） |
| M5 | AI Agent（流式对话、6 工具、审批 Diff、撤回 / 重发 / 编辑） | ✅ 已完成 |
| M6 | 打磨（i18n、SAF 导出导入、桌面适配、iOS 打通） | 待开始 |

---

## 当前进度

**M0 已验证**：真机上完整跑通 `clone → 改写 → commit → push`，`libgit2.so` 以 `arm64-v8a` 正确打包。

**M1 已完成**：

- `SiteStorage` 抽象 + `AppPrivateStorage` 实现（已按多站点预留接口）
- `GitService`：clone / status / URL 校验
- `SiteController`：`empty` / `cloning` / `ready` / `failed` 四态
- 站点页四态 UI + 接入表单（仓库地址 + PAT）
- clone 后自动识别文章目录（`content/posts` 等 6 个候选路径）
- 文章列表接真实数据，移除 M0 调试页

---

## 目录结构

```
lib/
├─ main.dart                  入口：git2dart 初始化 + 主题态
├─ app/
│  ├─ shell.dart              5 Tab 外壳（IndexedStack 保活）
│  └─ theme/
│     ├─ app_colors.dart      11 个语义色 token，亮暗两套
│     └─ app_theme.dart       ThemeData + 排版规范
├─ core/
│  ├─ fs/site_storage.dart    存储抽象（以后接 SAF 只加实现类）
│  └─ site/
│     ├─ site_config.dart     站点配置模型
│     ├─ git_service.dart     Git 操作封装
│     └─ site_controller.dart 站点状态
├─ features/
│  ├─ post/                   文章列表
│  ├─ note/                   笔记
│  ├─ ai/                     AI 对话
│  ├─ site/                   站点接入与管理
│  ├─ editor/                 Markdown 编辑器
│  └─ settings/               设置
└─ shared/widgets.dart        公共组件
```

---

## 开发

### 环境要求

本项目主要在 **aarch64 Android + proot Ubuntu 24.04** 环境下开发，构建链有若干硬性约束。如果你在普通 x86 电脑上开发，可以忽略下面标注「ARM64 专用」的部分。

| 组件 | 版本 |
|---|---|
| Flutter | 3.47.7 stable |
| Dart | 3.13.5 |
| JDK | 17 |
| Gradle | 8.14 |
| NDK | **28.2.13676358**（ARM64 专用，见下） |

### 常用命令

```bash
flutter pub get
flutter analyze
flutter test

# 构建（ARM64 必须带 --target-platform）
flutter build apk --debug --target-platform android-arm64
```

### ⚠️ ARM64 / proot 构建约束

这些是踩过坑之后固定下来的，**不要随意改动**：

1. **NDK 必须钉死 `28.2.13676358`**
   NDK 27 的 `clang-18` 是裸 x86-64 ELF，aarch64 上无法执行（报 `clang: not found`，但文件确实存在）。NDK 28 的 clang 是 box64 包装脚本，可以正常调用。

2. **ABI 只能是 `arm64-v8a`，且必须从根 `android/build.gradle.kts` 注入**
   `app` 层的 `abiFilters` **不会传播到插件子项目**。`git2dart_binaries` 是独立 Gradle 子项目，必须在根项目用 `subprojects { }` 统一配置。

3. **`android/gradle.properties` 里那两行 aapt2 配置不能丢**
   ```properties
   android.aapt2FromMavenOverride=/root/Android/build-tools/36.0.0/aapt2
   android.aapt2.process.daemon=false
   ```
   重建 `android/` 目录时会丢这两行，丢了之后的症状不是 aapt2 报错，而是各种奇怪的资源打包失败，极难定位。

4. **构建命令必须带 `--target-platform android-arm64`**

更详细的排错方法见 [`docs/ARM64_BUILD_TROUBLESHOOTING.md`](docs/ARM64_BUILD_TROUBLESHOOTING.md)，AI 助手请先读 [`AGENTS.md`](AGENTS.md)。

---

## 文档

| 文件 | 内容 |
|---|---|
| [`docs/FEATURE_SPEC.md`](docs/FEATURE_SPEC.md) | 产品与技术方案（封版 v4） |
| [`docs/DESIGN_SPEC.md`](docs/DESIGN_SPEC.md) | UI 设计规范 |
| [`docs/ARM64_BUILD_TROUBLESHOOTING.md`](docs/ARM64_BUILD_TROUBLESHOOTING.md) | ARM64 原生插件构建排错手册 |
| [`AGENTS.md`](AGENTS.md) | AI 助手操作手册（十条铁律） |

---

## 许可

私人项目，未开源。
