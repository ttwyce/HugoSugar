allprojects {
    repositories {
        maven("https://maven.aliyun.com/repository/google")
        maven("https://maven.aliyun.com/repository/central")
        maven("https://maven.aliyun.com/repository/public")
        maven("https://repo.huaweicloud.com/repository/maven/")
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// ── 统一所有子项目的 NDK 版本与 ABI（ARM64 / proot 必需）────────
// 背景：git2dart_binaries 自带 CMake 子项目（只为打包 jniLibs 里的 libgit2.so，
// 本身不编译任何代码），且带自己的 AGP 7.3.0 buildscript，不声明 ndkVersion
// 和 abiFilters 时 AGP 会自行决定：
//   1. NDK 挑到 27.0.12077973 —— 其 clang-18 是裸 x86-64 ELF，aarch64 上
//      无 box64 包装层，报 `clang: not found`；
//   2. ABI 会连 x86_64 / x86 一起构建 —— 而 NDK 28 的 sysroot 里 x86_64 的
//      crt*.o 与 -lc/-lm 路径布局会让 ld.lld 直接找不到而链接失败。
// 所以必须逐个钉死：ndkVersion = 28，ABI 只留 arm64-v8a。
val pinnedNdkVersion = "28.2.13676358"

subprojects {
    // 放在 afterEvaluate 之前用 plugin callback，确保 DSL 已创建
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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
