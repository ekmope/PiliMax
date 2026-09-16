plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.pilinara"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.pilinara"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "0.1.0"

        // 仅在 ARMv8（arm64-v8a）架构上运行。
        ndk {
            abiFilters += listOf("arm64-v8a")
        }
    }

    sourceSets {
        // 预编译的 Rust 核心（libpilinara_core.so）由 CI 通过 `cargo ndk` 生成后放入此处。
        getByName("main") {
            jniLibs.srcDirs("src/main/jniLibs")
        }
    }

    packaging {
        jniLibs {
            // MPV 与 VLC 两者都自带 libc++_shared.so，任取其一即可避免合并冲突。
            pickFirsts += "**/libc++_shared.so"
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            // 演示发布的 0.1 版本使用 debug 签名，保证 APK 可直接安装。
            signingConfig = signingConfigs.getByName("debug")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    // 播放内核：Media3（默认）。
    implementation("androidx.media3:media3-exoplayer:1.11.0")

    // 播放内核：VLC（org.videolan.android，自拉取内核）。
    implementation("org.videolan.android:libvlc-all:3.7.0")

    // 播放内核：MPV（dev.jdtech.mpv，自拉取内核）。
    implementation("dev.jdtech.mpv:libmpv:1.0.0")
}