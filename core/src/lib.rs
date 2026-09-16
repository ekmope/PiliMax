//! PiliNara native core.
//!
//! 纯计算/解析逻辑，不包含网络与 TLS，便于将 `libpilinara_core.so` 交叉编译到
//! Android arm64-v8a。网络 I/O 由 Android 壳（Kotlin）负责，通过 JNI 传入字符串，
//! 核心只做「今日推荐单」算法与「animeko 源订阅/选择器/Bangumi」解析。

pub mod bili_vip;
pub mod source_subscription;
pub mod today_watch;

mod jni;