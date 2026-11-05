# HugoSugar

> 在手机上写 Hugo 文章，写完一键推到 GitHub。构建交给 CI，本地一概不管。

HugoSugar 是一个专注**写作**的 Hugo 客户端。它不内置终端、不做本地构建、不管 Hugo 版本 —— 这些交给 CI。它只解决一件事：**灵感来了，手边只有手机。**

---

## 为什么做这个

用 Hugo 建站的人在手机上写作，通常要面对两种情况：

- **网页版 CMS / GitHub 网页编辑器**：能改，但写作体验很差，没有沉浸感
- **同步到本地再推**：手机上根本没有能跑 Hugo 的完整终端环境

HugoSugar 的思路是换一个前提：**既然部署交给 CI，本地就不需要构建能力。**

于是整个 App 只需要三件事：一个 Markdown 编辑器、一个 Git 推送通道、一个写文章时能搭把手的 AI。范围收得很窄，但每一块都做扎实。

---

## 功能范围

### 做

| 模块 | 说明 |
|---|---|
| **文章** | 四类列表（全部 / 草稿 / 已发布 / 回收站）、**标题·正文·标签搜索**、Front Matter 生成、查找替换、停笔 2 秒自动保存 |
| **编辑器** | 正文优先的极简界面，顶栏输入 2 秒后淡出；Markdown 语法高亮、工具栏；分类与标签候选**随输入实时过滤**；亮暗双主题，正文字体与字号可调 |
| **想法** | 灵感速记，支持分类、置顶、精选、搜索、回收站，一键转成文章 |
| **Git 同步** | 变更列表、提交信息、commit + push；**拉取（fetch + 仅快进）**；冲突与远端超前检测；推送后由平台监听仓库自动构建，无需手动触发 |
| **AI 写作助手** | 流式对话、**10 个工具**、写入前审批 Diff、可撤销；对话撤回 / 重发 / 编辑；System Prompt 可编辑；多端点与模型热切换；记忆库 |
| **想法备份** | WebDAV 上传，**客户端加密**（PBKDF2 + AES-256-GCM）；可手动或每日自动；恢复按 `updatedAt` 逐条合并 |

### 不做

| 不做 | 原因 |
|---|---|
| 本地 Hugo 构建 / 实时预览 | 部署在 CI，本地构建没有收益 |
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
| 状态管理 | `ChangeNotifier` + controller | 页面与数据层已解耦，规模下够用，不引入额外框架 |
| 存储 | App 私有目录 | 不需要任何权限，卸载即清；`libgit2` 需要真实文件路径，SAF 只给 `content://` URI |
| 加密 | [`pointycastle`](https://pub.dev/packages/pointycastle) | 纯 Dart 的 AES-GCM 与 PBKDF2，不引入新的原生构建链 |
| WebDAV | `dart:io` 手写 | 需要控制自签证书回调，第三方库普遍不支持 |

> ⚠️ **不要用 `libgit2dart`**。它已标记 DISCONTINUED，且只支持 64 位 Linux/macOS/Windows，**不支持 Android/iOS**。
> 两者名字很像，选错了整个项目会卡死在第一步。

---

## 里程碑

| # | 内容 | 状态 |
|---|---|---|
| **M0** | 骨架 + Git 冒烟验证 | ✅ 真机通过 |
| **M1** | 站点接入（clone / 识别 `content/posts` / 站点信息卡） | ✅ 已完成 |
| M2 | 文章 + 编辑器（Front Matter、语法高亮、自动保存） | ✅ 已完成 |
| M3 | 想法（CRUD、置顶、回收站、转文章） | ✅ 已完成 |
| M4 | Git 推送（变更列表、commit、push、冲突提示） | ✅ **真机验证通过** |
| M5 | AI Agent（流式对话、10 工具、审批 Diff、撤回 / 重发 / 编辑） | ✅ 已完成 |
| M6 | 打磨（i18n、正文字体/字号、导出导入、返回键拦截） | ✅ 已完成（桌面与 iOS 未验证） |
| M7 | 想法备份（WebDAV + 端到端加密） | ✅ **真机验证通过** |
| M8 | 分发（release 签名 + CI 构建） | ✅ **真机验证通过** |

> **M0 的 git 冒烟是硬门槛**，`libgit2.so` 以 `arm64-v8a` 正确打包。
> 若日后换库或换环境，这一步要重新验证。

---

## 真机验证记录

以下四项均在 aarch64 Android 真机上实际跑通，不只是「构建成功」：

| 项目 | 验证内容 |
|---|---|
| **Git 推送** | clone → 改文章 → commit → push 到 GitHub，远端能看到提交 |
| **想法备份** | 配 WebDAV → 立即备份 → 恢复，数据完整 |
| **返回键拦截** | 非首 Tab 返回到想法；想法页一次提示、两次退出 |
| **正式签名** | release 签名 APK 安装、覆盖升级正常 |

---

## 架构与目录

```
lib/
├─ main.dart                  入口：git2dart 初始化 + 各 controller 装配
├─ app/
│  ├─ shell.dart              5 Tab 外壳（IndexedStack 保活）+ 返回键两级拦截
│  ├─ i18n/                   中英文案（中文当 key）与取词入口
│  └─ theme/                  语义色 token、ThemeData、阅读偏好
├─ core/
│  ├─ ai/                     AI 控制器、Agent 循环、工具实现、记忆库
│  ├─ backup/                 WebDAV 备份：加密、客户端、服务、配置、调度
│  ├─ note/                   想法数据模型、持久化、控制器
│  ├─ post/                   文章与 Front Matter、导入导出
│  ├─ site/                   站点配置、Git 操作、站点控制器
│  ├─ fs/                     存储抽象（以后接 SAF 只加实现类）
│  └─ settings/               App 设置与提交身份
├─ features/                  页面：post / note / ai / site / editor / settings / push
└─ shared/widgets.dart        公共组件
```

分层约定：`core/` 不依赖 `features/`，页面只通过 controller 访问数据层。

---

## 数据与安全

### 想法备份的加密链路

```
notes.json → JSON → gzip → AES-256-GCM → WebDAV PUT
```

| 环节 | 参数 | 说明 |
|---|---|---|
| KDF | PBKDF2-HMAC-SHA256 / 210,000 轮 / 32B 随机盐 | 手机上约 1–2 秒，抗离线爆破 |
| 加密 | AES-256-GCM / 12B 随机 nonce / 128-bit tag | 篡改必然解不开 |
| 容器头 | magic + 版本 + KDF 参数 + 盐 + nonce | 整体作为 **AAD** 参与认证，防降级 |

- 口令不落盘（除非用户显式勾选「记住」，存 0600 私有文件）
- 解密失败统一提示「口令错误或备份已损坏」，不区分原因，避免成为口令试探的 oracle
- 上传先写 `.tmp` 再 `MOVE` 覆盖，断网不会冲掉旧备份
- **口令丢失即备份永久不可恢复**，没有任何后门

### 签名

release 构建使用 RSA 4096 / PKCS12 密钥库，证书 DN `CN=ttwyce`，有效期至 2054 年。

- 凭据优先级：环境变量（CI）→ `android/key.properties`（本地），两者都不入库
- **缺少签名配置时 release 构建直接失败**，不静默退回 debug 签名
- CI 构建后用 `apksigner --print-certs` 校验证书 DN，确保产物由 release 证书签署

> ⚠️ 密钥库丢失后就再也发不了更新。Android 只认签名不认人：换签名的包无法覆盖安装，
> 用户必须先卸载，而卸载会清空 App 内全部本地数据。

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
# 正式包需要 android/key.properties，否则构建直接失败
flutter build apk --release --target-platform android-arm64
```

### 构建交给自己，不交给本地

推送到 `main` 后由 GitHub Actions 完成全部验证与产物构建（`.github/workflows/build-apk.yml`）：

```
flutter analyze → flutter test → 还原签名密钥库 → build apk --release → 校验证书 → 上传 artifact
```

本地只需要写代码。注意 CI 只跑单元测试，涉及真实网络（push、WebDAV）的链路仍需真机确认。

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

源码公开可见，但**未采用开源许可**，保留所有权利。
