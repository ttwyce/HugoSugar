# ARM64 / proot 下 Flutter 原生插件构建问题手册

> **适用场景**：在 aarch64 Android + proot Ubuntu 环境构建 Flutter 项目，
> 尤其是**引入了带原生代码（C/C++/FFI）的插件**时。
>
> **本文价值**：记录 2026-10 M0 阶段的真实踩坑，但重点不在「这次答案」，
> 而在「**下次换个插件、换个版本号，怎么自己找到答案**」。
> Flutter 插件生态一直在变，具体版本号会过期，排查路径不会。

---

## 0. 一句话总结

> **任何带原生代码的第三方 Flutter 插件，都会让 AGP 自选 NDK 版本和 ABI 集合。
> 在 ARM64 上这两件事都必须被「全局钉死」，否则必然失败。**

这是 M0 阶段最贵的教训。看起来像是「某个插件不支持」，实际是**构建系统没有被告知约束**。

---

## 1. 四层坑的完整链路

按**出现顺序**，不是按严重程度。每一层失败都会掩盖下一层，所以必须逐层解开。

```
第 1 层：选错库
    libgit2dart（已废弃，且不支持 Android/iOS）
        ↓ 换库
第 2 层：NDK 版本错
    AGP 自选 NDK 27 → clang-18 是裸 x86-64 ELF → `clang: not found`
        ↓ 钉死 NDK 28
第 3 层：ABI 集合错
    CMake 连 x86_64 一起构建 → ld.lld 找不到 crtbegin_dynamic.o
        ↓ 钉死 arm64-v8a
第 4 层：配置作用域错
    app 的 abiFilters 不传播到插件子项目
        ↓ 提到根 build.gradle.kts
```

---

## 2. 逐层详解

### 2.1 第 1 层：选库时先查平台支持

**踩坑记录**

原方案用的是 `libgit2dart`。pub.dev 页面明确写着：

```
libgit2dart 1.2.2
Published 3 years ago
DISCONTINUED
SUPPORTED PLATFORMS: 64-bit Linux, MacOS, Windows
```

**没有 Android，没有 iOS。** 如果照着写代码，会在第一次 `clone()` 时崩掉，而且崩在原生层，报错信息完全不可读。

正确选择是 `git2dart`（45 天前发布，明确支持 Android arm64-v8a / x86_64、iOS via CocoaPods）。

**通用规则：引入任何 New Package 之前，先看 pub.dev 页面顶部的三个标记**

| 标记 | 怎么看 | 危险信号 |
|---|---|---|
| **DISCONTINUED** | 标题旁的红色标签 | 绝对不能用于新项目 |
| **PLATFORMS** | SDK / FLUTTER / PLATFORMS 三个图标行 | 没有 `ANDROID` 就是不能用 |
| **Published** | 发布时间 | 超过 2 年未更新，Android 侧大概率已跟不上 AGP |

**另外必须翻 README 找「Mobile Initialization」章节。** `git2dart` 要求：

```dart
await PlatformSpecific.initialize();  // 必须在 runApp 之前
```

漏了这句，Android 上加载不到 `.so`，报错同样不可读。

---

### 2.2 第 2 层：NDK 必须钉死，不能交给 AGP 自选

**症状**

```
/bin/sh: 1: .../ndk/27.0.12077973/toolchains/llvm/prebuilt/linux-x86_64/bin/clang: not found
```

注意：**`not found` 不代表文件不存在。**

**诊断（关键一步，很多人在这里走错）**

```bash
# 先确认文件在不在
ls -la /root/Android/ndk/27.0.12077973/toolchains/llvm/prebuilt/linux-x86_64/bin/clang
# → 是个软链，指向 clang-18，文件确实存在

# 再看它到底是什么架构
file /root/Android/ndk/27.0.12077973/toolchains/llvm/prebuilt/linux-x86_64/bin/clang-18
# → ELF 64-bit LSB pie executable, x86-64  ← 根本没法在 aarch64 上执行
```

**`not found` 的真实含义是「内核无法执行这个二进制」**，可能是：
- 架构不匹配（本例）
- 动态链接器缺失（`ELFs interpreter /lib64/ld-linux-x86-64.so.2` 不存在）

对比 NDK 28：

```bash
cat /root/Android/ndk/28.2.13676358/toolchains/llvm/prebuilt/linux-x86_64/bin/clang-19
# → #!/usr/bin/env bash
# → exec box64 "/root/.../bin/.clang-19.real" "$@"
```

**NDK 28 的 clang 是个 bash 包装脚本，靠 box64 转译 x86-64 二进制**，所以能跑。

**通用规则**

```bash
# 判断任意工具能否在本机运行，两步：
file <path>                        # 看架构：aarch64 或 x86-64
cat <path> 2>/dev/null | head -1   # 看是不是脚本包装（#!/usr/bin/env ...）
```

如果是 x86-64 且**不是**脚本包装 → 需要 box64，大概率跑不了。

**验证工具链可用（不要跳过）**

```bash
NDK=/root/Android/ndk/28.2.13676358/toolchains/llvm/prebuilt/linux-x86_64
printf 'int main(){return 0;}\n' > /tmp/t.c
$NDK/bin/clang --target=aarch64-none-linux-android21 \
  --sysroot=$NDK/sysroot -o /tmp/t /tmp/t.c
file /tmp/t
# 必须看到 ARM aarch64 才算真正可用
```

> 这一步是**分水岭**。工具链自身能跑 ≠ CMake 调用它时能跑。
> 但只要工具链自身不行，后面所有 CMake 报错都是噪音。

---

### 2.3 第 3 层：ABI 集合必须钉死到 arm64-v8a

**症状**

```
ld.lld: error: cannot open crtbegin_dynamic.o: No such file or directory
ld.lld: error: unable to find library -lm
ld.lld: error: unable to find library -lc
.clang-19: error: linker command failed with exit code 1
```

**注意：这次 clang 能跑了（说明第 2 层已解决），失败在「链接」阶段。**

**诊断**

```bash
# 1. 看 CMake 到底在为哪个 ABI 构建
grep -o 'ANDROID_ABI=[a-z0-9_-]*' build.log | sort -u
# → ANDROID_ABI=x86_64     ← 问题在这里

# 2. 看 .cxx 下生成了哪几个 ABI 目录
ls /root/.pub-cache/hosted/pub.flutter-io.cn/<plugin>/android/.cxx/Debug/*/
# → arm64-v8a  armeabi-v7a  x86  x86_64    ← 四个都建了

# 3. 看真正的链接命令行（最精确）
cat .cxx/Debug/*/x86_64/CMakeFiles/CMakeError.log | grep -A5 'ld.lld'
```

第 3 步会看到类似：

```
"/root/.../bin/ld.lld" --sysroot=/root/.../sysroot ... \
  -L/root/.../sysroot/usr/lib \      ← 注意：没有 x86_64-linux-android/21 子目录
  -o cmTC_92157 crtbegin_dynamic.o ...
```

**根因**：NDK 28 的 sysroot 布局是 `usr/lib/x86_64-linux-android/21/`，而 link 命令只搜 `usr/lib`，所以找不到 `crt*.o` 和 `-lc/-lm`。

> 换句话说：**NDK 28 + CMake 3.22.1 对 x86_64 的组合本身就不完整**。
> 我们并不需要 x86_64，所以正确做法不是去修它，而是**根本别让它构建**。

**通用规则**

在本机构建，**永远只要 `arm64-v8a`**：

- 出别的 ABI 也跑不了（本机是 aarch64）
- 会让构建时间翻倍甚至更多
- 会命中各种 sysroot 路径怪问题

---

### 2.4 第 4 层：配置作用域 —— app 的设置不会传染给插件

**症状**

在 `android/app/build.gradle.kts` 里设了 `ndkVersion` 和 `abiFilters`，构建日志显示**完全没生效**。

**根因**

`git2dart_binaries` 这类插件是**独立的 Gradle 子项目**（`:git2dart_binaries`），甚至自带自己的 `buildscript { classpath 'com.android.tools.build:gradle:7.3.0' }`。

```
:app                    ← 你改的是这个
:git2dart_binaries      ← CMake 实际跑在这个里面，你没改到
```

`app` 的 `android { }` 块对该子项目**零影响**。

**通用规则：插件子项目的 NDK/ABI 必须从根项目统一注入**

```kotlin
// android/build.gradle.kts（根，不是 app）
val pinnedNdkVersion = "28.2.13676358"

subprojects {
    plugins.withId("com.android.library") {
        extensions.configure<com.android.build.gradle.LibraryExtension> {
            ndkVersion = pinnedNdkVersion
            defaultConfig {
                ndk {
                    abiFilters.clear()
                    abiFilters.add("arm64-v8a")
                }
            }
        }
    }
    plugins.withId("com.android.application") {
        extensions.configure<com.android.build.gradle.AppExtension> {
            ndkVersion = pinnedNdkVersion
            defaultConfig {
                ndk {
                    abiFilters.clear()
                    abiFilters.add("arm64-v8a")
                }
            }
        }
    }
}
```

**为什么用 `plugins.withId(...)` 而不是直接 `android { }`**

因为根项目 buildscript 执行时，子项目的 `com.android.library` 插件**可能还没 apply**，
此时 `extensions.configure<LibraryExtension>` 会抛「扩展不存在」。
`plugins.withId` 是**回调式的**：插件一被 apply 就立即执行配置，时机刚好。

**为什么 `abiFilters.clear()` 要先 clear**

插件可能自己声明了 `abiFilters`（少见但存在），直接 `add` 会变成并集。
先 `clear()` 保证结果唯一可预测。

---

## 3. 五条通用方法论

这部分比上面任何具体配置都重要。

### 3.1 先分清「编译期」还是「链接期」

| 阶段 | 典型报错 | 说明 |
|---|---|---|
| 编译期 | `clang: not found`、`not able to compile a simple test program` | 工具链**根本无法执行** |
| 链接期 | `cannot open crtbegin_dynamic.o`、`unable to find library -lc` | 工具链能跑，但**找不到库** |

两者根因完全不同，**绝不能用同一种方式修**。编译期错 → 查工具链架构；链接期错 → 查 sysroot / ABI / 参数。

### 3.2 一定要看 CMake 的**实际参数**，不看你的配置

Gradle 配置写了什么不重要，**CMake 收到什么才重要**。

```bash
grep -o '\-DANDROID_ABI=[a-z0-9_-]*' build.log | sort -u
grep -o 'ndk/[0-9.]*' build.log | sort -u
```

这两个命令能立刻回答：
- NDK 用的是哪个版本（验证第 2 层）
- ABI 是哪个（验证第 3 层）

**改完配置立刻跑这两条**，比读代码快十倍。

### 3.3 手动跑一遍工具链，隔离变量

不要一上来就怀疑 CMake。先手动跑：

```bash
$NDK/bin/clang --target=aarch64-none-linux-android21 \
  --sysroot=$NDK/sysroot -c test.c -o test.o    # 只编译
$NDK/bin/clang --target=aarch64-none-linux-android21 \
  --sysroot=$NDK/sysroot test.c -o test          # 编译+链接
```

- **手动成功，CMake 失败** → 问题在 CMake 参数或 ABI，不在工具链
- **手动也失败** → 工具链或 sysroot 本身有问题

本例中手动全程成功，直接把怀疑范围缩小到「ABI 选错了」。

### 3.4 用 `file` 检查每一个产物

```bash
file /tmp/lg.so
# ELF 64-bit LSB shared object, ARM aarch64   ← 这才是对的
```

构建「成功」不等于产物可用。**必须验证 .so 的真实架构**：

```bash
# 从 APK 里抽出来看
unzip -p build/app/outputs/flutter-apk/app-debug.apk \
  lib/arm64-v8a/libgit2.so > /tmp/lg.so && file /tmp/lg.so
```

### 3.5 改构建配置前先备份

```bash
cp -a android/build.gradle.kts android/build.gradle.kts.bak
cp -a android/app/build.gradle.kts android/app/build.gradle.kts.bak
```

`gradle.properties` 尤其要备，它是**唯一能让 AGP 在 ARM64 上工作**的文件。

---

## 4. 快速排查决策树

遇到原生插件构建失败，按此顺序走：

```
① 失败在哪个 gradle task？
   :<plugin>:configureCMakeDebug[abi]     → 进入 ②
   其它（compileDebugJava / package）     → 不是本文范围

② CMake 报错是「编译期」还是「链接期」？
   not able to compile / clang: not found → ③
   crt*.o / -lc / -lm 找不到              → ④

③ 查工具链架构
   file <ndk>/.../bin/clang-XX
   x86-64 且无脚本包装 → 换 NDK 版本
   有 #!/usr/bin/env bash + box64 → 正常

④ 查实际 ABI
   grep -o 'ANDROID_ABI=[a-z0-9_-]*' build.log | sort -u
   不是 arm64-v8a → 去根 build.gradle.kts 给 subprojects 加 abiFilters

⑤ 改完 ✓
   grep -o 'ndk/[0-9.]*' build.log | sort -u        确认 NDK
   grep -o 'ANDROID_ABI=[a-z0-9_-]*' build.log | sort -u   确认 ABI
   grep '✓ Built' build.log                          确认成功
   unzip -l app-debug.apk 'lib/*'                    确认 so 存在
   file 抽出的 so                                     确认架构
```

---

## 5. 环境相关的固定结论（本机专用，可直接抄）

| 项 | 值 | 备注 |
|---|---|---|
| NDK | `28.2.13676358` | 必须，27 的 clang 跑不了 |
| ABI | 仅 `arm64-v8a` | 其它 ABI 无意义 |
| aapt2 | `/root/Android/build-tools/36.0.0/aapt2` | 通过 `android.aapt2FromMavenOverride` 指定 |
| aapt2 daemon | `false` | proot 下不可用 |
| Gradle wrapper | `gradle-8.14-bin.zip` | **不要用 `-all`**，本机 `-all` 是下载中断的半截文件 |
| 构建命令 | `flutter build apk --debug --target-platform android-arm64` | 必须带 target-platform |

### 5.1 关于 `gradle-wrapper.properties` 的坑

Flutter 模板默认写 `gradle-8.14-all.zip`。本机 `~/.gradle/wrapper/dists/` 里的状态是：

```
gradle-8.14-bin/     ← 完整，有 .ok 标记
gradle-8.14-all/     ← 只有 .zip.part 和 .lck，是下载中断的残留
```

所以用 `-all` 会触发重新下载，而网络不通 → `SocketTimeoutException`。

**检查方法**：

```bash
ls ~/.gradle/wrapper/dists/gradle-8.14-bin/*/     # 看到 gradle-8.14/ 目录 = 完整
ls ~/.gradle/wrapper/dists/gradle-8.14-all/*/     # 只有 .part = 不完整
```

`-all` 相比 `-bin` 只多了源码和文档（IDE 用），**构建完全不需要**。直接用 `-bin`。

---

## 6. 检查清单：引入新原生插件时

- [ ] pub.dev 上确认有 `ANDROID` 平台图标
- [ ] 确认没标 DISCONTINUED
- [ ] 确认最近 1 年有更新
- [ ] README 里找 Mobile Initialization 章节，按要求在 `runApp` 前初始化
- [ ] 看插件有没有自带 `android/build.gradle`，有的话检查它是否声明了 `ndkVersion` / `abiFilters`
- [ ] 构建后跑 `grep -o 'ndk/[0-9.]*'` 和 `grep -o 'ANDROID_ABI=...'` 双重确认
- [ ] 从 APK 抽出 .so，用 `file` 确认是 `ARM aarch64`
- [ ] 首次运行到真机，确认原生库能加载（不只是编译通过）

---

## 7. 附：本次涉及的文件改动

| 文件 | 改动 | 原因 |
|---|---|---|
| `android/build.gradle.kts` | 新增 subprojects 统一块 | 第 4 层：作用域 |
| `android/app/build.gradle.kts` | `ndkVersion` 固定 + 注释 | 第 2 层：NDK |
| `android/gradle.properties` | 补回 aapt2 两行 | **原文件已丢失，必须补** |
| `android/gradle/wrapper/gradle-wrapper.properties` | `-all` → `-bin` | 本地缓存只有 bin 是完整的 |
| `pubspec.yaml` | `libgit2dart` → `git2dart: ^0.5.6` | 第 1 层：选库 |
| `lib/main.dart` | 加 `await PlatformSpecific.initialize()` | 移动端必需 |

> ⚠️ **`gradle.properties` 的 aapt2 配置在重建项目时会丢**。
> 丢了之后的症状不是报 aapt2 错误，而是各种奇怪的资源打包失败。
> **每次重建 `android/` 目录后，第一件事就是检查这两行在不在。**
