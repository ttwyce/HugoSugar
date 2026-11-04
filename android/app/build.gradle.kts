import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ── Release 签名配置 ──
// 凭据来源优先级：环境变量（CI 注入） > android/key.properties（本地）。
// 两者都不存在时，release 构建会直接失败，而不是静默退回 debug 签名——
// 用 debug 签出的包装了之后，换成正式签名无法覆盖升级，必须先卸载，
// 而卸载会清掉全部本地数据。这种错误宁可让构建报错。
val signingProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

fun signingValue(envKey: String, propKey: String): String? =
    System.getenv(envKey)?.takeIf { it.isNotBlank() }
        ?: signingProps.getProperty(propKey)?.takeIf { it.isNotBlank() }

val releaseStorePath = signingValue("HUGO_STORE_FILE", "storeFile")
val releaseStorePassword = signingValue("HUGO_STORE_PASSWORD", "storePassword")
val releaseKeyAlias = signingValue("HUGO_KEY_ALIAS", "keyAlias")
val releaseKeyPassword = signingValue("HUGO_KEY_PASSWORD", "keyPassword")

val hasReleaseSigning = listOf(
    releaseStorePath, releaseStorePassword, releaseKeyAlias, releaseKeyPassword
).all { it != null } && file(releaseStorePath!!).exists()

android {
    namespace = "com.ttwyce.hugosugar"
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
        // 应用 ID：手机上的唯一标识。改了就等于换了个 App，
        // 已装的旧版本不会被覆盖，需要先卸载。
        applicationId = "com.ttwyce.hugosugar"
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

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(releaseStorePath!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
                // 显式指定，避免 AGP 因扩展名猜测失败（.jks / .keystore 都按 PKCS12 读）。
                storeType = "PKCS12"
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

flutter {
    source = "../.."
}

// 只在真的要出 release 包时才拦。放在配置阶段直接 throw 会连 `flutter run`
// 的 debug 构建一起打断，所以挂到 taskGraph 上——此时已知道本次要跑哪些任务。
gradle.taskGraph.whenReady {
    val buildingRelease = it.allTasks.any { t ->
        t.name == "assembleRelease" || t.name == "bundleRelease" ||
            t.name.startsWith("packageRelease") || t.name == "installRelease"
    }
    if (buildingRelease && !hasReleaseSigning) {
        throw GradleException(
            """
            |
            |缺少 release 签名配置，已中止构建。
            |
            |本地构建：在 android/key.properties 中填写 storeFile / storePassword /
            |          keyAlias / keyPassword 四项。
            |CI 构建：配置仓库 Secrets —— ANDROID_KEYSTORE_BASE64、ANDROID_STORE_PASSWORD、
            |          ANDROID_KEY_ALIAS、ANDROID_KEY_PASSWORD。
            |
            |不要用 debug 签名产出正式包：日后换成正式签名无法覆盖升级，
            |必须先卸载，而卸载会清掉 App 的全部本地数据。
            |""".trimMargin()
        )
    }
}
