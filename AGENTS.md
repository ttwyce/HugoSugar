# AGENTS.md — AI 助手操作手册（HugoSugar）

> **在动手之前先读完本文**，尤其是「十条铁律」和「禁止操作」。
> 遇到原生插件构建问题，见 [`docs/ARM64_BUILD_TROUBLESHOOTING.md`](docs/ARM64_BUILD_TROUBLESHOOTING.md)。

---

## 0. 十条铁律

### 铁律一：构建必须在 proot Ubuntu 里跑

本项目运行在 **aarch64 Android 手机 + proot Ubuntu 24.04** 环境。
所有 `flutter` / `gradle` / `java` / `cmake` / `clang` 命令**只能在 Linux 终端环境里执行**。
不要用 Android 原生 Shell（`super_admin:shell`），那里没有 flutter。

### 铁律二：环境变量只在 `/etc/profile.d/50-flutter-android.sh`

不要往 `~/.bashrc` 里加 export。要加变量就改这一个文件。

### 铁律三：不要删除 `build-tools` 目录里的任何文件

`build-tools/*/` 里的 x86 二进制在 ARM64 上永远不会被执行，**但 AGP 会做完整性校验**，
缺任何一个就报 `Installed Build Tools revision X is corrupted`，而且抛在依赖解析阶段，绕不过去。

**「不会被调用」≠「可以删除」。**

### 铁律四：NDK 必须钉死在 `28.2.13676358`

**不要用 `flutter.ndkVersion`，不要交给 AGP 自选。**

原因：NDK 27 的 `clang-18` 是**裸 x86-64 ELF**，aarch64 上无 box64 包装层，
执行时报 `clang: not found`（文件明明存在，是内核无法执行）。
NDK 28 的 clang 是 `#!/usr/bin/env bash exec box64 ...` 包装脚本，可正常调用。

**必须同时写在两个地方**（缺一不可，见铁律五）：

```kotlin
// android/app/build.gradle.kts
android { ndkVersion = "28.2.13676358" }
```

```kotlin
// android/build.gradle.kts（根）—— 这个才是真正生效的
subprojects {
    plugins.withId("com.android.library") { /* ... */ }
    plugins.withId("com.android.application") { /* ... */ }
}
```

### 铁律五：ABI 只允许 `arm64-v8a`，且必须从根项目注入

**`app` 的 `abiFilters` 不会传播到插件子项目。**

带原生代码的插件（如 `git2dart_binaries`）是独立 Gradle 子项目，有自己的
`buildscript`（甚至自带 AGP 7.3.0）。只改 `app` 完全无效。

错误做法（无效）：
```kotlin
// android/app/build.gradle.kts —— 只管 app 自己
android { defaultConfig { ndk { abiFilters.add("arm64-v8a") } } }
```

正确做法：
```kotlin
// android/build.gradle.kts（根）
subprojects {
    plugins.withId("com.android.library") {
        extensions.configure<com.android.build.gradle.LibraryExtension> {
            ndkVersion = "28.2.13676358"
            defaultConfig {
                ndk {
                    abiFilters.clear()          // 先清，避免并集
                    abiFilters.add("arm64-v8a")
                }
            }
        }
    }
    // application 同理（用 AppExtension）
}
```

不锁 ABI 的后果：CMake 会为 x86_64 / x86 也跑一遍 configure，
而 NDK 28 的 sysroot 中 x86_64 的 `crt*.o` / `-lc` / `-lm` 路径布局会让 `ld.lld`
直接找不到 → `cannot open crtbegin_dynamic.o`。

### 铁律六：`gradle.properties` 里那两行 aapt2 配置不能丢

```properties
android.aapt2FromMavenOverride=/root/Android/build-tools/36.0.0/aapt2
android.aapt2.process.daemon=false
```

**重建 `android/` 目录时会丢这两行**，丢了之后症状不是报 aapt2 错误，而是各种
奇怪的资源打包失败，极难定位。

**每次重建 `android/` 后第一件事：检查这两行在不在。**

### 铁律七：`gradle-wrapper.properties` 用 `-bin` 不用 `-all`

本机 `~/.gradle/wrapper/dists/gradle-8.14-all/` 里只有 `.zip.part`（下载中断残留），
用 `-all` 会触发重新下载 → `SocketTimeoutException`。
`-bin` 有完整缓存（有 `.ok` 标记）。`-all` 多的只是源码和文档，构建不需要。

检查：
```bash
ls ~/.gradle/wrapper/dists/gradle-8.14-bin/*/   # 有 gradle-8.14/ 目录 = 完整
```

### 铁律八：构建命令必须带 `--target-platform android-arm64`

```bash
flutter build apk --debug --target-platform android-arm64
```

不带会尝试多架构，在 ARM64 proot 下更慢且毫无意义。

### 铁律九：看日志不看退出码

```bash
grep -E 'Built |FAILURE|RC=|corrupted|CMake Error|ld\.lld: error|rror:' build.log
```

**唯一可信的成功标志**：
```
✓ Built build/app/outputs/flutter-apk/app-debug.apk
```

`exitCode: 0` 可能只是外层包装成功。`tail` 会漏掉中间的错误。
**构建一律重定向到 `build.log`，然后用 grep 查。**

### 铁律十：验证产物，不只看「构建成功」

```bash
# 1. so 是否打包
unzip -l build/app/outputs/flutter-apk/app-debug.apk 'lib/*'

# 2. so 架构是否正确
unzip -p build/app/outputs/flutter-apk/app-debug.apk \
  lib/arm64-v8a/libgit2.so > /tmp/x.so && file /tmp/x.so
# 必须是 ELF 64-bit LSB shared object, ARM aarch64
```

---

## 1. 环境实况

| 组件 | 路径 | 版本 |
|---|---|---|
| Flutter | `/root/flutter` | 3.47.7 stable |
| Dart | （随 Flutter） | 3.13.5 |
| Android SDK | `/root/Android` | — |
| Build Tools | `/root/Android/build-tools/` | 35.0.0、36.0.0 |
| **NDK（必须用这个）** | `/root/Android/ndk/28.2.13676358` | **28.2.13676358** |
| NDK（不可用） | `/root/Android/ndk/27.0.12077973` | clang 是裸 x86-64，跑不了 |
| CMake | `/root/Android/cmake/3.22.1` | 3.22.1 |
| JDK | `/usr/lib/jvm/java-17-openjdk-arm64` | 17.0.20.1 |
| Gradle | `/root/gradle/gradle-8.14` | 8.14 |

**架构前提**：CPU 是 **aarch64**。同时存在 box64 用于转译 x86-64 二进制。

**判断任意工具能否运行**：
```bash
file <path>                       # aarch64 → 可以直接跑
                                  # x86-64  → 看下一步
cat <path> 2>/dev/null | head -1  # 有 #!/usr/bin/env bash + box64 → 能跑
```

---

## 2. 标准工作流

```bash
cd /data/user/0/com.ai.assistance.operit/files/workspace/61ee0d9e-f250-4aca-8bdf-931b4b92693b

# 1. 拉依赖
bash -lc 'flutter pub get'

# 2. 静态检查 / 测试
bash -lc 'flutter analyze'
bash -lc 'flutter test'

# 3. 构建（务必重定向到日志）
rm -f build.log
nohup bash -lc 'flutter build apk --debug --target-platform android-arm64' > build.log 2>&1 &

# 4. 等 2-3 分钟后检查（不要只看 tail）
grep -E 'Built |FAILURE|rror:' build.log
```

**增量构建约 50-70 秒；首次全量约 2-3 分钟。**

---

## 3. 常见报错对照表

| 报错 | 根因 | 处理 |
|---|---|---|
| `Installed Build Tools revision X is corrupted` | build-tools 目录缺文件 | 铁律三 |
| `flutter: command not found` | 非交互 shell | 用 `bash -lc` |
| `.../bin/clang: not found`（文件存在） | NDK 27 的 clang 是裸 x86-64 | 铁律四 |
| `cannot open crtbegin_dynamic.o` / `unable to find library -lc` | ABI 跑到 x86_64 了 | 铁律五 |
| `configureCMakeDebug[x86_64] FAILED` | 同上传 | 铁律五 |
| `SocketTimeoutException` 下载 gradle | wrapper 用了 `-all` | 铁律七 |
| `applies the Kotlin Gradle Plugin... build failures in future` | Flutter 迁移提示 | 非致命，忽略 |
| `Woah! You appear to be trying to run flutter as root.` | root 运行 | 正常提示，忽略 |

---

## 4. 禁止操作清单

| ❌ 不要做 | 原因 |
|---|---|
| 删除 `build-tools/*/` 内任何文件 | AGP 完整性校验失败 |
| 删除 `/root/Android/ndk/*/toolchains/llvm/prebuilt/linux-x86_64/` | NDK 主机工具链正常组成 |
| 用 NDK 27 | 铁律四 |
| 只改 `app/build.gradle.kts` 的 abiFilters 就以为生效 | 铁律五：不传播 |
| 修改/删除 `gradle.properties` 的 aapt2 两行 | 铁律六 |
| 用 `-all` 版 gradle wrapper | 铁律七 |
| 往 `.bashrc` 里堆 export | 铁律二 |
| 用 `super_admin:shell` 跑 Flutter 命令 | 铁律一 |
| 加 `set -e` / `set -o errexit` | 终端会话会卡死退出 |
| 引入 pub.dev 上标 **DISCONTINUED** 的包 | 大概率不支持 Android |
| 引入**没有 `ANDROID` 平台图标**的包 | 直接不可用 |
| 只看 `tail` 或 `exitCode` 判断构建成功 | 铁律九 |

---

## 5. 关键文件索引

| 文件 | 作用 |
|---|---|
| `/etc/profile.d/50-flutter-android.sh` | 环境变量唯一真相源 |
| `/usr/local/bin/flutter` | 软链（无环境依赖兜底） |
| `android/gradle.properties` | **aapt2 覆盖 + daemon 关闭，丢了就完蛋** |
| `android/build.gradle.kts` | **NDK + ABI 全局钉死（铁律四/五）** |
| `android/app/build.gradle.kts` | ndkVersion 固定 + abiFilters |
| `docs/ARM64_BUILD_TROUBLESHOOTING.md` | **原生插件构建问题完整手册** |
| `docs/FEATURE_SPEC.md` | 功能与需求方案（v4，依赖清单已校正） |
| `docs/DESIGN_SPEC.md` | UI 设计规范 |

> ⚠️ **依赖名易混，务必看清：是 `git2dart`，不是 `libgit2dart`。**
> `libgit2dart` 已 DISCONTINUED，且只支持 64 位 Linux/macOS/Windows，
> **Android/iOS 完全不可用**，选错会卡死在 M0 第一步。
> 当前实际使用 `git2dart: ^0.5.6`，以 `pubspec.yaml` 为准。

---

## 6. 排错方法论（核心）

**先跑通，再优雅。** 遇到问题时按此顺序：

1. **先复现** —— 拿到完整报错原文，不要凭症状猜
2. **看日志不看退出码** —— `grep -E 'Built |FAILURE|rror:'`
3. **隔离变量** —— 手动跑工具链，区分是工具链问题还是 CMake 参数问题
4. **验证实际值** —— `grep -o 'ndk/[0-9.]*'`、`grep -o 'ANDROID_ABI=...'`
   查 CMake **实际收到**的参数，而不是你写了什么
5. **小步改** —— 一次只改一个变量，改完立刻重跑
6. **留后路** —— 改配置前先 `cp -a` 备份

### 判断「编译期」还是「链接期」

| 阶段 | 典型报错 | 查什么 |
|---|---|---|
| 编译期 | `clang: not found`、`not able to compile` | **工具链架构**（`file` 命令） |
| 链接期 | `cannot open crt*.o`、`unable to find library -lc` | **sysroot / ABI** |

两者根因完全不同，**不能用同一种方式修**。
