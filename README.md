# piliAI

bilibili 客户端（原 PiliNara），目前处于从 Flutter 向 **Rust 核心 + Kotlin Android 壳** 迁移的阶段。

- 仅面向 **Android ARMv8 (arm64-v8a)**，不再构建 iOS / Linux / macOS / Windows 及其它 ABI，相关代码已删除。
- 网络、TLS、持久化由 Android 壳（Kotlin）负责；纯计算 / 解析逻辑下沉到 Rust 核心，通过 JNI 桥接。

## 架构

```
core/                      Rust 核心（纯逻辑，无网络/TLS）
  src/today_watch.rs          「今日推荐单」算法（来自 bilipai 内置插件）
  src/source_subscription/    animeko 源订阅（多源聚合 / Bangumi）数据模型与清单解析
  src/source_subscription/selector.rs  web-selector 通用源引擎（CSS 选择器抓取）
  src/jni.rs                  JNI 桥（Java_com_pilinara_core_NativeCore_*）
android/                    Kotlin Android 壳（仅 arm64-v8a）
  app/src/main/java/com/pilinara/core/NativeCore.kt  JNI 接口
  app/src/main/.../MainActivity.kt                    最小自检界面
```

核心 crate 名为 `pilinara_core`，产出 `libpilinara_core.so`（`cdylib`）供 Android 通过 JNI 加载，同时保留 `rlib` 便于单元测试。

## 功能

- **今日推荐单**：根据历史观看记录与候选视频，按模式 / 策略生成推荐单（算法在 `core/src/today_watch.rs`）。
- **animeko 源订阅**：源订阅清单解析、多源聚合、源实例选择器与搜索 / 详情 / 视频直链解析（在 `core/src/source_subscription/`）。
- **三大播放内核**：Media3（默认）/ VLC / MPV 可切换，统一 `CorePlayer` 抽象与工厂（在 `app/src/main/java/com/pilinara/player/`）。
- **大会员无限试用**：本地改写 B 站 API 会员字段，模拟无限试用状态（在 `core/src/bili_vip.rs` 与 `app/src/main/java/com/pilinara/vip/`）。

## 构建

### 本地

```bash
# Rust 核心测试
cd core
cargo test --locked

# 交叉编译 arm64-v8a（需要 NDK 与 cargo-ndk）
cargo install cargo-ndk --locked
cargo ndk -t arm64-v8a -o ../android/app/src/main/jniLibs build --release

# Android 发布 APK（需要 JDK 17 + Android SDK 36 / Build Tools 35.0.0）
cd ../android
./gradlew :app:assembleRelease --no-daemon
```

### CI

CI 定义在 [.github/workflows/android.yml](.github/workflows/android.yml)，包含：

1. `rust-core`：运行 Rust 核心单元测试。
2. `android`：交叉编译 Rust 核心为 `arm64-v8a`，再构建并上传 Android 发布 APK（`assembleRelease`）。
3. `release`：仅在打 `v*` 标签（如 `v0.1.0`）时触发，自动创建 GitHub Release 并附带 APK。