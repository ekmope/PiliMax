// VLC 播放器内核插件：独立 APK，宿主运行时按需下载并通过 DexClassLoader 加载。
// 产物（plugin-vlc-release.apk）会在 CI 中重命名为 vlc-core.apk 发布到 Release 资产。
plugins {
    id("com.android.application")
}

android {
    namespace = "com.pilinara.plugin.vlc"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.pilinara.plugin.vlc"
        minSdk = 26
        targetSdk = 37
        versionCode = 1
        versionName = "3.6.5"
        ndk {
            // 与宿主一致：仅支持 arm64-v8a（第五代骁龙 8 至尊版）。
            abiFilters += listOf("arm64-v8a")
        }
    }

    // 插件无 UI、无资源，保持 debug 签名便于产物即装即测（实际不会被 PackageManager 安装）。
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
    // 仅编译期引用宿主契约；运行时由宿主 ClassLoader 提供。
    compileOnly(project(":plugin-api"))
    // libVLC 官方 AAR（含 arm64 原生库，约 40MB so 体积）。
    implementation("org.videolan.android:libvlc-all:3.6.5")
}
