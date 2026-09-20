// MPV 播放器内核插件：独立 APK，宿主运行时按需下载并通过 DexClassLoader 加载。
// 产物（plugin-mpv-release.apk）会在 CI 中重命名为 mpv-core.apk 发布到 Release 资产。
plugins {
    id("com.android.application")
}

android {
    namespace = "com.pilinara.plugin.mpv"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.pilinara.plugin.mpv"
        minSdk = 26
        targetSdk = 37
        versionCode = 1
        versionName = "1.0.0"
        ndk {
            // 与宿主一致：仅支持 arm64-v8a（第五代骁龙 8 至尊版）。
            abiFilters += listOf("arm64-v8a")
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    compileOnly(project(":plugin-api"))
    // libmpv Android 绑定（AAR 含 jni/arm64-v8a/libmpv.so + ffmpeg 全套）。
    implementation("dev.jdtech.mpv:libmpv:1.0.0")
}
