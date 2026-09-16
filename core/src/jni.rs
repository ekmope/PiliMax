//! JNI 桥接：Android 壳（Kotlin）通过字符串（JSON）调用核心逻辑。
//!
//! 约定：核心只接收/返回 JSON 字符串，网络与持久化留在 Android 端。所有导出函数的
//! Java 侧定义在 `com.pilinara.core.NativeCore`。

use std::collections::HashMap;

use jni::objects::{JClass, JString};
use jni::sys::jstring;
use jni::JNIEnv;

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