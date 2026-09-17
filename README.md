# piliAI / PiliNara

哔哩哔哩客户端，技术栈为 **Rust 核心 + Kotlin/Jetpack Compose Android 壳 + Media3 播放器**（无 Flutter 残留）。

- 唯一目标平台：**Android 17（compileSdk/targetSdk 37）、arm64-v8a、第五代高通骁龙 8 至尊版（Oryon / Armv9.2）**。
- 网络、TLS、持久化、UI 由 Kotlin 壳负责；解析 / 合并 / 推荐 / 嗅探等纯计算下沉到 Rust 核心，经 JNI（JSON 字符串）桥接。
- Rust 核心以 `target-cpu=oryon-1` 编译（启用 SVE2 / i8mm / bf16 / dotprod），release 开 fat-LTO + 单 codegen unit。

## 架构

```
core/                         Rust 核心（cdylib + rlib，纯逻辑无网络/TLS）
  src/today_watch.rs            「今日推荐单」打分算法（relax/learn × balanced/affinity/explore）
  src/source_subscription/      animeko 兼容源订阅：清单解析、diff、web-selector 引擎
  src/danmaku.rs                XML + seg.so protobuf 弹幕解析与时间窗合并
  src/feed_filter.rs            信息流规则过滤
  src/sniffer.rs                kazumi 子集视频地址嗅探（含 iframe/嵌套页二级嗅探）
  src/bili_vip.rs               大会员字段本地改写
  src/jni.rs                    JNI 桥（Java_com_pilinara_core_NativeCore_*）
android/                      Kotlin 壳
  app/build.gradle.kts          Gradle 任务 cargoBuildArm 自动交叉编译并打包 .so（无需 cargo-ndk）
  app/src/main/java/com/pilinara/
    api/                        B 站 web API：扫码登录/WBI 签名/热门/推荐/搜索/详情/playurl/历史/弹幕
    source/                     订阅管理、内置预设（assets/sources/presets.json）、多源聚合搜索
    player/                     Media3 ExoPlayer + MediaSession、DASH 双轨合流、弹幕层、手势、PiP
    vip/                        大会员试用改写（OkHttp 拦截器 + 开关闸门）
    ui/                         Compose Material3（首页/搜索/源/我的/设置/详情）
```

## 功能

- **首页**：热门、推荐（WBI 签名）、今日（Rust 推荐算法，结合观看历史）、观看历史；信息流支持本地规则过滤。
- **搜索**：哔哩哔哩视频搜索 + 已启用第三方源并发聚合搜索。
- **源中心**：内置 animeko 兼容订阅预设（开箱即用）、自定义订阅 URL、逐个源开关、订阅更新与失败提示。
- **播放**：Media3 硬解（HLS/DASH/fMP4 双轨合流）、后台播放（MediaSession 系统通知/耳机键）、画中画、只听模式、倍速、亮度/音量/进度手势、双击快进退、长按 2 倍速。
- **弹幕**：seg.so protobuf 分段弹幕自动加载（XML 后备），Rust 合并重复弹幕，Compose Canvas 低功耗渲染，不透明度/字号可调。
- **大会员体验**：拦截器本地改写会员状态字段并解除 playurl 试看限制，可在设置中开关。
- **播放网络**：清晰度档位、CDN 节点偏好（自动/阿里/华为/腾讯/Akamai），防盗链头按 URL 注入。

## 构建

要求：JDK 17、Android SDK Platform 37、NDK `28.0.13004108`、Rust（含 `aarch64-linux-android` target）。

```bash
# Rust 核心测试
cd core
cargo test --locked

# Android APK（Rust .so 由 Gradle 自动交叉编译进 jniLibs）
cd ../android
./gradlew :app:assembleDebug      # 或 :app:assembleRelease
```

NDK 链接器路径由构建脚本从 `local.properties` 的 `sdk.dir`（或 `ANDROID_HOME`）推导，指向
`$SDK/ndk/28.0.13004108/toolchains/llvm/prebuilt/<host>/bin/aarch64-linux-android26-clang`。

## CI

CI 定义在 [.github/workflows/android.yml](.github/workflows/android.yml)：

1. `rust-core`：运行 Rust 核心单元测试。
2. `android`：安装 SDK 37 / NDK r28，Gradle 自动完成 Rust 交叉编译并构建 release APK。
3. `release`：打 `v*` 标签时自动创建 GitHub Release 并附带 APK。
