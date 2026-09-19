import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
}

// 内核插件下载地址需要指向本仓库 Release 资产：
// CI 上读 GITHUB_REPOSITORY，本地从 git remote 解析。
val repoSlug: String = run {
    System.getenv("GITHUB_REPOSITORY")?.takeIf { it.isNotBlank() }?.let { return@run it }
    val remote = runCatching {
        ProcessBuilder("git", "remote", "get-url", "origin")
            .directory(rootDir)
            .redirectErrorStream(false)
            .start()
            .also { it.waitFor() }
            .inputStream.bufferedReader().readText().trim()
    }.getOrDefault("")
    Regex("[:/]([^/]+/[^/]+?)(?:\\.git)?$").find(remote)?.groupValues?.get(1)
        ?: "qwerzxcva/PiliNara"
}
val coreDownloadBase = "https://github.com/$repoSlug/releases/latest/download"

android {
    namespace = "com.pilinara"
    // Android 17（本应用唯一目标平台）。
    compileSdk = 37

    // 与本机/CI 安装的 NDK 对齐（r28，含 Armv9 与最新 LLVM 调度支持）。
    ndkVersion = "28.0.13004108"

    defaultConfig {
        applicationId = "com.pilinara"
        minSdk = 26
        targetSdk = 37
        versionCode = 15
        versionName = "0.4.9"

        // 仅在 ARMv8（arm64-v8a）架构上运行：面向第五代骁龙 8 至尊版（Oryon / Armv9.2）。
        ndk {
            abiFilters += listOf("arm64-v8a")
        }

        buildConfigField("String", "CORE_URL_VLC", "\"$coreDownloadBase/vlc-core.apk\"")
        buildConfigField("String", "CORE_URL_MPV", "\"$coreDownloadBase/mpv-core.apk\"")
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    buildTypes {
        release {
            // R8 full mode 混淆对本项目的破坏面远大于收益：项目同时依赖 JNI(Rust so)、
            // kotlinx.serialization 反射、DexClassLoader 动态加载播放器插件，全是混淆
            // 最容易破坏的机制，release 版已长期出现「打开闪退 / 反序列化崩溃」。
            // 主包本就不大，关闭混淆换取稳定运行；性能与功耗由 native 硬解路径决定，
            // 与是否混淆无关。
            isMinifyEnabled = false
            isShrinkResources = false
            // 预览版沿用 debug 签名，保证 APK 可直接安装。
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    packaging {
        resources {
            excludes += setOf(
                "META-INF/AL2.0",
                "META-INF/LGPL2.1",
                "META-INF/DEPENDENCIES",
                "kotlin-tooling-metadata.json",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2026.09.00")
    implementation(composeBom)
    debugImplementation(composeBom)

    // AndroidX 基础
    implementation("androidx.core:core-splashscreen:1.2.0")
    implementation("androidx.activity:activity-compose:1.13.0")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.11.0")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.11.0")
    implementation("androidx.navigation:navigation-compose:2.10.1")
    implementation("androidx.datastore:datastore-preferences:1.2.1")

    // Jetpack Compose（Material3 / Material3 Expressive 随 BOM 提供）
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    debugImplementation("androidx.compose.ui:ui-tooling")

    // 播放内核：Media3（ExoPlayer）—— 骁龙平台硬解/低功耗最优解，含 DASH/HLS 与后台 MediaSession。
    implementation("androidx.media3:media3-common:1.11.1")
    implementation("androidx.media3:media3-ui:1.11.1")
    implementation("androidx.media3:media3-exoplayer:1.11.1")
    implementation("androidx.media3:media3-exoplayer-dash:1.11.1")
    implementation("androidx.media3:media3-exoplayer-hls:1.11.1")
    implementation("androidx.media3:media3-datasource-okhttp:1.11.1")
    implementation("androidx.media3:media3-session:1.11.1")

    // 外部播放器内核插件契约（实现以独立 APK 按需下载，见 PlayerCoreManager）。
    implementation(project(":plugin-api"))

    // 二维码（登录）
    implementation("com.google.zxing:core:3.5.3")

    // 网络 / 图片 / 序列化 / 协程
    implementation("com.squareup.okhttp3:okhttp:5.5.0")
    implementation("io.coil-kt.coil3:coil-compose:3.6.2")
    implementation("io.coil-kt.coil3:coil-network-okhttp:3.6.2")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.11.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.11.0")
}

// ---------------------------------------------------------------------------
// Rust 核心交叉编译：cargo 产出 libpilinara_core.so → jniLibs/arm64-v8a。
// 不依赖 cargo-ndk/额外插件；链接器直接指向 NDK r28 的 clang（API 26）。
// ---------------------------------------------------------------------------
val rustDir = layout.projectDirectory.file("../../core/Cargo.toml").asFile.parentFile
val rustJniLibsDir = layout.projectDirectory.dir("src/main/jniLibs/arm64-v8a").asFile
// AGP 9 的扩展不再暴露 sdkDirectory；从 local.properties / 环境变量解析 SDK 根目录。
val sdkDir = run {
    val props = Properties()
    val f = rootProject.file("local.properties")
    if (f.exists()) f.inputStream().use { props.load(it) }
    val raw = props.getProperty("sdk.dir")
        ?: System.getenv("ANDROID_HOME")
        ?: System.getenv("ANDROID_SDK_ROOT")
        ?: error("找不到 Android SDK（local.properties / ANDROID_HOME 均未设置）")
    File(raw)
}
val rustNdkDir = File(sdkDir, "ndk/${android.ndkVersion}")
val rustLinker = File(
    rustNdkDir,
    "toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android26-clang",
).absolutePath

var rustProfile = "debug"

val cargoBuildArm = tasks.register<Exec>("cargoBuildArm") {
    group = "build"
    workingDir = rustDir
    commandLine(
        "cargo", "build",
        "--target", "aarch64-linux-android",
        "--target-dir", File(rustDir, "target").absolutePath,
    )
    environment("CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER", rustLinker)
    environment("CC_aarch64_linux_android", rustLinker)
    inputs.dir(File(rustDir, "src"))
    inputs.file(File(rustDir, "Cargo.toml"))
    outputs.upToDateWhen { false }
    doFirst {
        val isRelease = gradle.taskGraph.allTasks.any {
            it.name.startsWith("assemble") && it.name.contains("Release", ignoreCase = true)
        }
        rustProfile = if (isRelease) "release" else "debug"
        if (isRelease) args("--release")
    }
}

val copyRustSo = tasks.register<Copy>("copyRustSo") {
    dependsOn(cargoBuildArm)
    from(provider {
        File(rustDir, "target/aarch64-linux-android/$rustProfile/libpilinara_core.so")
    })
    into(rustJniLibsDir)
}

tasks.named("preBuild") { dependsOn(copyRustSo) }
