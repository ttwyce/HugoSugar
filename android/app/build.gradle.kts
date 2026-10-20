plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.operit_flutter_project"
    compileSdk = flutter.compileSdkVersion
    // 本项目跑在 aarch64 + proot 上，NDK 27 的 clang-18 是裸 x86-64 ELF，
    // 没有 box64 包装层，无法执行（报 "clang: not found"）。
    // NDK 28 的 clang 是 `#!/usr/bin/env bash exec box64 ...` 包装脚本，可正常调用。
    // 因此必须固定用 28.2.13676358，不要回退到 flutter.ndkVersion。
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.operit_flutter_project"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // 只出 arm64。原因有二：
        // 1. 本机是 aarch64，其他 ABI 产出来也没法跑；
        // 2. 关键是插件：git2dart_binaries 自带 CMake 子项目，若不限制 ABI，
        //    AGP 会为 x86/x86_64 也跑一遍 configureCMake，而 NDK 28 已移除
        //    x86 支持、且这些 ABI 的 sysroot 链接必然失败。
        ndk {
            abiFilters.add("arm64-v8a")
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
