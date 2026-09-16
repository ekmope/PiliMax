plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.pilinara"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.pilinara"
        minSdk = 24
        targetSdk = 35
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

    buildTypes {
        release {
            isMinifyEnabled = false
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
    // 最小壳不依赖第三方 Android 库；Kotlin 标准库由 Kotlin 插件自动引入。
}