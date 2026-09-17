//! JNI 桥接：Android 壳（Kotlin）通过字符串（JSON）调用核心逻辑。
//!
//! 约定：核心只接收/返回 JSON 字符串，网络与持久化留在 Android 端。所有导出函数的
//! Java 侧定义在 `com.pilinara.core.NativeCore`。

use std::collections::HashMap;

use jni::objects::{JClass, JString};
use jni::sys::jstring;
use jni::JNIEnv;

use crate::bili_vip::{apply_vip_trial, VipTrialConfig};
use crate::source_subscription::selector::SelectorEngine;
use crate::source_subscription::{apply_manifest, SourceInstance, SubscriptionManifest};
use crate::today_watch::{build_today_watch_plan, TodayWatchMode, TodayWatchStrategy};

fn get_string(env: &mut JNIEnv, s: &JString) -> Result<String, String> {
    let js = env.get_string(s).map_err(|e| e.to_string())?;
    Ok(js.into())
}

fn to_jstring(env: &mut JNIEnv, s: impl AsRef<str>) -> jstring {
    match env.new_string(s.as_ref()) {
        Ok(js) => js.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}

fn throw(env: &mut JNIEnv, msg: impl AsRef<str>) -> jstring {
    let _ = env.throw_new("java/lang/RuntimeException", msg.as_ref());
    std::ptr::null_mut()
}

fn deserialize<T: serde::de::DeserializeOwned>(env: &mut JNIEnv, s: &JString) -> Result<T, jstring> {
    let raw = match get_string(env, s) {
        Ok(raw) => raw,
        Err(e) => return Err(throw(env, e)),
    };
    match serde_json::from_str::<T>(&raw) {
        Ok(v) => Ok(v),
        Err(e) => Err(throw(env, format!("invalid json: {}", e))),
    }
}

fn serialize<T: serde::Serialize>(env: &mut JNIEnv, v: &T) -> jstring {
    match serde_json::to_string(v) {
        Ok(s) => to_jstring(env, s),
        Err(e) => throw(env, format!("serialize: {}", e)),
    }
}

fn parse_str_enum<T: serde::de::DeserializeOwned>(env: &mut JNIEnv, s: &JString) -> Result<T, jstring> {
    let tag = match get_string(env, s) {
        Ok(tag) => tag,
        Err(e) => return Err(throw(env, e)),
    };
    match serde_json::from_str::<T>(&format!("\"{}\"", tag)) {
        Ok(v) => Ok(v),
        Err(e) => Err(throw(env, format!("invalid enum '{}': {}", tag, e))),
    }
}

fn now_epoch_sec() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

/// 生成「今日推荐单」。输入历史/候选 JSON，输出 plan JSON。
#[no_mangle]
pub extern "system" fn Java_com_pilinara_core_NativeCore_buildTodayWatchPlan<'local>(
    mut env: JNIEnv<'local>,
    _class: JClass<'local>,
    history_json: JString<'local>,
    candidates_json: JString<'local>,
    mode: JString<'local>,
    strategy: JString<'local>,
) -> jstring {
    let history = match deserialize::<Vec<crate::today_watch::HistoryVideo>>(&mut env, &history_json) {
        Ok(v) => v,
        Err(j) => return j,
    };
    let candidates =
        match deserialize::<Vec<crate::today_watch::CandidateVideo>>(&mut env, &candidates_json) {
            Ok(v) => v,
            Err(j) => return j,
        };
    let mode = match parse_str_enum::<TodayWatchMode>(&mut env, &mode) {
        Ok(v) => v,
        Err(j) => return j,
    };
    let strategy = match parse_str_enum::<TodayWatchStrategy>(&mut env, &strategy) {
        Ok(v) => v,
        Err(j) => return j,
    };
    let plan = build_today_watch_plan(&history, &candidates, mode, strategy, 5, 20, now_epoch_sec());
    serialize(&mut env, &plan)
}

/// 解析订阅清单 body → manifest JSON。
#[no_mangle]
pub extern "system" fn Java_com_pilinara_core_NativeCore_parseManifest<'local>(
    mut env: JNIEnv<'local>,
    _class: JClass<'local>,
    body: JString<'local>,
) -> jstring {
    let body = match get_string(&mut env, &body) {
        Ok(s) => s,
        Err(e) => return throw(&mut env, e),
    };
    match SubscriptionManifest::parse(&body) {
        Some(m) => serialize(&mut env, &m),
        None => throw(&mut env, "invalid manifest"),
    }
}

/// 应用订阅清单 diff：返回更新后的 instances JSON 数组。
#[no_mangle]
pub extern "system" fn Java_com_pilinara_core_NativeCore_applyManifest<'local>(
    mut env: JNIEnv<'local>,
    _class: JClass<'local>,
    subscription_id: JString<'local>,
    body: JString<'local>,
    instances_json: JString<'local>,
) -> jstring {
    let subscription_id = match get_string(&mut env, &subscription_id) {
        Ok(s) => s,
        Err(e) => return throw(&mut env, e),
    };
    let body = match get_string(&mut env, &body) {
        Ok(s) => s,
        Err(e) => return throw(&mut env, e),
    };
    let mut instances = match deserialize::<Vec<SourceInstance>>(&mut env, &instances_json) {
        Ok(v) => v,
        Err(j) => return j,
    };
    let manifest = match SubscriptionManifest::parse(&body) {
        Some(m) => m,
        None => return throw(&mut env, "invalid manifest"),
    };
    apply_manifest(&subscription_id, &manifest, &mut instances);
    serialize(&mut env, &instances)
}

/// 构造搜索 URL。
#[no_mangle]
pub extern "system" fn Java_com_pilinara_core_NativeCore_buildSearchUrl<'local>(
    mut env: JNIEnv<'local>,
    _class: JClass<'local>,
    instance_json: JString<'local>,
    keyword: JString<'local>,
) -> jstring {
    let instance = match deserialize::<SourceInstance>(&mut env, &instance_json) {
        Ok(v) => v,
        Err(j) => return j,
    };
    let keyword = match get_string(&mut env, &keyword) {
        Ok(s) => s,
        Err(e) => return throw(&mut env, e),
    };
    let engine = SelectorEngine::new(&instance);
    match engine.build_search_url(&keyword) {
        Some(url) => to_jstring(&mut env, url),
        None => throw(&mut env, "searchUrl not configured"),
    }
}

/// 解析搜索结果页 → subjects JSON。
#[no_mangle]
pub extern "system" fn Java_com_pilinara_core_NativeCore_parseSubjectList<'local>(
    mut env: JNIEnv<'local>,
    _class: JClass<'local>,
    instance_json: JString<'local>,
    html: JString<'local>,
    search_url: JString<'local>,
) -> jstring {
    let instance = match deserialize::<SourceInstance>(&mut env, &instance_json) {
        Ok(v) => v,
        Err(j) => return j,
    };
    let html = match get_string(&mut env, &html) {
        Ok(s) => s,
        Err(e) => return throw(&mut env, e),
    };
    let search_url = match get_string(&mut env, &search_url) {
        Ok(s) => s,
        Err(e) => return throw(&mut env, e),
    };
    let engine = SelectorEngine::new(&instance);
    let subjects = engine.parse_subject_list_from_search_url(&html, &search_url);
    serialize(&mut env, &subjects)
}

/// 解析条目详情页 → channels JSON。
#[no_mangle]
pub extern "system" fn Java_com_pilinara_core_NativeCore_parseChannels<'local>(
    mut env: JNIEnv<'local>,
    _class: JClass<'local>,
    instance_json: JString<'local>,
    html: JString<'local>,
    subject_url: JString<'local>,
) -> jstring {
    let instance = match deserialize::<SourceInstance>(&mut env, &instance_json) {
        Ok(v) => v,
        Err(j) => return j,
    };
    let html = match get_string(&mut env, &html) {
        Ok(s) => s,
        Err(e) => return throw(&mut env, e),
    };
    let subject_url = match get_string(&mut env, &subject_url) {
        Ok(s) => s,
        Err(e) => return throw(&mut env, e),
    };
    let engine = SelectorEngine::new(&instance);
    let channels = engine.parse_channels(&html, &subject_url);
    serialize(&mut env, &channels)
}

/// 从页面 HTML 提取视频直链（返回 JSON 字符串或 null）。
#[no_mangle]
pub extern "system" fn Java_com_pilinara_core_NativeCore_matchVideo<'local>(
    mut env: JNIEnv<'local>,
    _class: JClass<'local>,
    instance_json: JString<'local>,
    html: JString<'local>,
) -> jstring {
    let instance = match deserialize::<SourceInstance>(&mut env, &instance_json) {
        Ok(v) => v,
        Err(j) => return j,
    };
    let html = match get_string(&mut env, &html) {
        Ok(s) => s,
        Err(e) => return throw(&mut env, e),
    };
    let engine = SelectorEngine::new(&instance);
    match engine.match_video(&html) {
        Some(url) => serialize(&mut env, &url),
        None => to_jstring(&mut env, "null"),
    }
}

/// 视频直链追加请求头 → JSON object。
#[no_mangle]
pub extern "system" fn Java_com_pilinara_core_NativeCore_videoHeaders<'local>(
    mut env: JNIEnv<'local>,
    _class: JClass<'local>,
    instance_json: JString<'local>,
) -> jstring {
    let instance = match deserialize::<SourceInstance>(&mut env, &instance_json) {
        Ok(v) => v,
        Err(j) => return j,
    };
    let engine = SelectorEngine::new(&instance);
    let headers: HashMap<String, String> = engine.video_headers();
    serialize(&mut env, &headers)
}

/// 解析旧版 XML 弹幕并（可选）合并。window_ms <= 0 表示不合并。
#[no_mangle]
pub extern "system" fn Java_com_pilinara_core_NativeCore_parseDanmakuXml<'local>(
    mut env: JNIEnv<'local>,
    _class: JClass<'local>,
    body: JString<'local>,
    window_ms: jni::sys::jlong,
) -> jstring {
    let body = match get_string(&mut env, &body) {
        Ok(s) => s,
        Err(e) => return throw(&mut env, e),
    };
    to_jstring(&mut env, crate::danmaku::parse_xml_json(&body, window_ms as i64))
}

/// 解析 seg.so protobuf 弹幕（body 需经 base64 编码传入）并（可选）合并。
#[no_mangle]
pub extern "system" fn Java_com_pilinara_core_NativeCore_parseDanmakuSegSo<'local>(
    mut env: JNIEnv<'local>,
    _class: JClass<'local>,
    base64_body: JString<'local>,
    window_ms: jni::sys::jlong,
) -> jstring {
    let b64 = match get_string(&mut env, &base64_body) {
        Ok(s) => s,
        Err(e) => return throw(&mut env, e),
    };
    match crate::danmaku::parse_seg_so_base64_json(&b64, window_ms as i64) {
        Ok(json) => to_jstring(&mut env, json),
        Err(e) => throw(&mut env, format!("danmaku seg.so: {}", e)),
    }
}

/// 信息流规则过滤：输入视频数组 JSON 与规则 JSON，返回过滤后的数组 JSON。
#[no_mangle]
pub extern "system" fn Java_com_pilinara_core_NativeCore_applyFeedFilter<'local>(
    mut env: JNIEnv<'local>,
    _class: JClass<'local>,
    videos_json: JString<'local>,
    rules_json: JString<'local>,
) -> jstring {
    let videos = match get_string(&mut env, &videos_json) {
        Ok(s) => s,
        Err(e) => return throw(&mut env, e),
    };
    let rules = match get_string(&mut env, &rules_json) {
        Ok(s) => s,
        Err(e) => return throw(&mut env, e),
    };
    to_jstring(&mut env, crate::feed_filter::apply(&videos, &rules))
}

/// 嗅探视频直链。config_json 为空串或 "null" 时使用内置兜底规则。
/// 命中返回 URL 字符串（非 JSON），未命中返回 "null"。
#[no_mangle]
pub extern "system" fn Java_com_pilinara_core_NativeCore_sniffVideo<'local>(
    mut env: JNIEnv<'local>,
    _class: JClass<'local>,
    html: JString<'local>,
    config_json: JString<'local>,
) -> jstring {
    let html = match get_string(&mut env, &html) {
        Ok(s) => s,
        Err(e) => return throw(&mut env, e),
    };
    let cfg = get_string(&mut env, &config_json).ok().and_then(optional_arg);
    match crate::sniffer::sniff(&html, cfg.as_deref()) {
        Some(url) => to_jstring(&mut env, url),
        None => to_jstring(&mut env, "null"),
    }
}

/// 嗅探嵌套页地址（iframe / 跳转），规则同 `sniffVideo`。
#[no_mangle]
pub extern "system" fn Java_com_pilinara_core_NativeCore_sniffNested<'local>(
    mut env: JNIEnv<'local>,
    _class: JClass<'local>,
    html: JString<'local>,
    config_json: JString<'local>,
) -> jstring {
    let html = match get_string(&mut env, &html) {
        Ok(s) => s,
        Err(e) => return throw(&mut env, e),
    };
    let cfg = get_string(&mut env, &config_json).ok().and_then(optional_arg);
    match crate::sniffer::sniff_nested(&html, cfg.as_deref()) {
        Some(url) => to_jstring(&mut env, url),
        None => to_jstring(&mut env, "null"),
    }
}

/// 空串 / "null" 视为未提供可选配置。
fn optional_arg(s: String) -> Option<String> {
    if s.is_empty() || s == "null" {
        None
    } else {
        Some(s)
    }
}

/// 应用「大会员无限试用」改写：对 B 站 API 返回的 JSON 做本地会员字段改写。
///
/// - `body`：原始 JSON 字符串；
/// - `config_json`：`VipTrialConfig` 的 JSON（解析失败时回退到默认配置）；
/// - `now_ms`：当前时间（Unix 毫秒），用于滚动顺延到期时间。
#[no_mangle]
pub extern "system" fn Java_com_pilinara_core_NativeCore_applyVipTrial<'local>(
    mut env: JNIEnv<'local>,
    _class: JClass<'local>,
    body: JString<'local>,
    config_json: JString<'local>,
    now_ms: jni::sys::jlong,
) -> jstring {
    let body = match get_string(&mut env, &body) {
        Ok(s) => s,
        Err(e) => return throw(&mut env, e),
    };
    let config = match get_string(&mut env, &config_json) {
        Ok(s) => serde_json::from_str::<VipTrialConfig>(&s).unwrap_or_default(),
        Err(_) => VipTrialConfig::default(),
    };
    let out = apply_vip_trial(&body, &config, now_ms as i64);
    to_jstring(&mut env, out)
}