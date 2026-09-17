//! PiliNara native core.
//!
//! 纯计算/解析逻辑，不包含网络与 TLS，便于将 `libpilinara_core.so` 交叉编译到
//! Android arm64-v8a。网络 I/O 由 Android 壳（Kotlin）负责，通过 JNI 传入字符串，
//! 核心负责：今日推荐单算法、animeko 源订阅解析、弹幕解析合并、信息流过滤、
//! 视频地址嗅探与大会员试用字段改写。

pub mod bili_vip;
pub mod danmaku;
pub mod feed_filter;
pub mod sniffer;
pub mod source_subscription;
pub mod today_watch;

mod jni;
