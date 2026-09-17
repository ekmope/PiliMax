//! `bili_vip`：大会员无限试用。
//!
//! 参考哔哩漫游（BiliRoaming）的思路，对 B 站 API 返回 JSON 里的会员字段做本地改写，
//! 让客户端认为当前账号处于「大会员试用」状态，并把到期时间持续顺延，从而达到“无限试用”。
//!
//! 本模块只做纯 JSON 改写（无网络、无 TLS），便于交叉编译进 `libpilinara_core.so`；
//! 网络抓取与持久化由 Android 壳完成，壳拿到 API 响应后调用这里的改写函数再交给 UI。

use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};

const MS_PER_DAY: i64 = 86_400_000;

/// 触发“大会员节点”的容器键：命中后对其子对象里的通用字段（status/type/due_date）也做改写。
const VIP_CONTAINER_KEYS: [&str; 3] = ["vip", "vipInfo", "vip_info"];

/// 大会员试用配置。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct VipTrialConfig {
    /// 是否启用改写。
    #[serde(default = "default_true")]
    pub enabled: bool,
    /// 写入的会员类型：1=月度大会员, 2=年度大会员。
    #[serde(rename = "vipType", default = "default_vip_type")]
    pub vip_type: i64,
    /// 每次改写时把到期时间顺延的「额外天数」，配合滚动顺延制造无限试用。
    #[serde(rename = "extendDays", default = "default_extend_days")]
    pub extend_days: i64,
}

fn default_true() -> bool {
    true
}

fn default_vip_type() -> i64 {
    2
}

fn default_extend_days() -> i64 {
    3650
}

impl Default for VipTrialConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            vip_type: 2,
            extend_days: 3650,
        }
    }
}

/// 改写 `body` 中的会员字段，返回改写后的 JSON 字符串。
///
/// - 非 JSON 输入、或 `enabled == false` 时原样返回；
/// - 会递归处理数组与嵌套对象；
/// - `now_ms` 为当前时间（Unix 毫秒），用于计算滚动到期的日期。
pub fn apply_vip_trial(body: &str, config: &VipTrialConfig, now_ms: i64) -> String {
    if !config.enabled {
        return body.to_string();
    }
    let mut value: Value = match serde_json::from_str(body) {
        Ok(v) => v,
        Err(_) => return body.to_string(),
    };
    rewrite(&mut value, config, now_ms, false);
    serde_json::to_string(&value).unwrap_or_else(|_| body.to_string())
}

fn rewrite(value: &mut Value, cfg: &VipTrialConfig, now_ms: i64, in_vip: bool) {
    match value {
        Value::Array(items) => {
            for item in items {
                rewrite(item, cfg, now_ms, in_vip);
            }
        }
        Value::Object(map) => {
            patch_vip_specific(map, cfg, now_ms);
            patch_playurl_trial(map);
            if in_vip {
                patch_vip_generic(map, cfg, now_ms);
            }
            for (key, child) in map.iter_mut() {
                let child_in_vip = VIP_CONTAINER_KEYS.contains(&key.as_str());
                rewrite(child, cfg, now_ms, child_in_vip);
            }
        }
        _ => {}
    }
}

fn future_due(now_ms: i64, extend_days: i64) -> i64 {
    now_ms.saturating_add(extend_days.saturating_mul(MS_PER_DAY))
}

fn set_vip_label(label: &mut Value) {
    if let Value::Object(obj) = label {
        obj.insert("text".to_string(), Value::from("大会员"));
        obj.insert("label_theme".to_string(), Value::from("annual_vip"));
    }
}

/// 带 vip 前缀的会员字段：命中即改写（这些键名足够专属，可全局安全改写）。
fn patch_vip_specific(map: &mut Map<String, Value>, cfg: &VipTrialConfig, now_ms: i64) {
    for key in ["vipStatus", "vip_status"] {
        if map.contains_key(key) {
            map.insert(key.to_string(), Value::from(1_i64));
        }
    }
    for key in ["vipType", "vip_type"] {
        if map.contains_key(key) {
            map.insert(key.to_string(), Value::from(cfg.vip_type));
        }
    }
    for key in ["vipDueDate", "vip_due_date", "vipDueDateMsec"] {
        if map.contains_key(key) {
            map.insert(key.to_string(), Value::from(future_due(now_ms, cfg.extend_days)));
        }
    }
    for key in ["vipLabel", "vip_label"] {
        if let Some(label) = map.get_mut(key) {
            set_vip_label(label);
        }
    }
}

/// playurl 响应：携带 `dash`/`durl` 的对象若带 `trial: true`（试看片段标记），
/// 清除该标记，使客户端按完整正片播放（无限试用：试看限制只在本地字段层生效）。
fn patch_playurl_trial(map: &mut Map<String, Value>) {
    if map.contains_key("trial")
        && (map.contains_key("dash") || map.contains_key("durl"))
    {
        map.insert("trial".to_string(), Value::Bool(false));
    }
}

/// 通用字段：仅在「大会员容器节点」内部改写，避免影响无关的 `status`/`type` 字段。
fn patch_vip_generic(map: &mut Map<String, Value>, cfg: &VipTrialConfig, now_ms: i64) {
    if map.contains_key("status") {
        map.insert("status".to_string(), Value::from(1_i64));
    }
    if map.contains_key("type") {
        map.insert("type".to_string(), Value::from(cfg.vip_type));
    }
    for key in ["dueDate", "due_date", "dueDateMsec"] {
        if map.contains_key(key) {
            map.insert(key.to_string(), Value::from(future_due(now_ms, cfg.extend_days)));
        }
    }
    if let Some(label) = map.get_mut("label") {
        set_vip_label(label);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    const NOW: i64 = 1_700_000_000_000;

    #[test]
    fn patches_flat_vip_fields() {
        let body = r#"{"code":0,"data":{"isLogin":true,"vipStatus":0,"vipType":0,"vipDueDate":1600000000000,"vipLabel":{"text":"","label_theme":""},"uname":"test"}}"#;
        let out = apply_vip_trial(body, &VipTrialConfig::default(), NOW);
        let v: Value = serde_json::from_str(&out).unwrap();
        assert_eq!(v["data"]["vipStatus"], json!(1));
        assert_eq!(v["data"]["vipType"], json!(2));
        assert!(v["data"]["vipDueDate"].as_i64().unwrap() > NOW);
        assert_eq!(v["data"]["vipLabel"]["text"], json!("大会员"));
        assert_eq!(v["data"]["vipLabel"]["label_theme"], json!("annual_vip"));
        // 非会员字段保持原样
        assert_eq!(v["data"]["uname"], json!("test"));
        assert_eq!(v["code"], json!(0));
    }

    #[test]
    fn patches_nested_vip_object() {
        let body = r#"{"data":{"vip":{"type":0,"status":0,"due_date":1600000000000,"label":{"text":"","label_theme":""}}}}"#;
        let out = apply_vip_trial(body, &VipTrialConfig::default(), NOW);
        let v: Value = serde_json::from_str(&out).unwrap();
        assert_eq!(v["data"]["vip"]["status"], json!(1));
        assert_eq!(v["data"]["vip"]["type"], json!(2));
        assert!(v["data"]["vip"]["due_date"].as_i64().unwrap() > NOW);
        assert_eq!(v["data"]["vip"]["label"]["text"], json!("大会员"));
    }

    #[test]
    fn leaves_non_vip_fields_untouched() {
        let body = r#"{"status":0,"type":9,"due_date":0,"uname":"test"}"#;
        let out = apply_vip_trial(body, &VipTrialConfig::default(), NOW);
        let v: Value = serde_json::from_str(&out).unwrap();
        assert_eq!(v["status"], json!(0));
        assert_eq!(v["type"], json!(9));
        assert_eq!(v["due_date"], json!(0));
        assert_eq!(v["uname"], json!("test"));
    }

    #[test]
    fn disabled_returns_input_unchanged() {
        let cfg = VipTrialConfig {
            enabled: false,
            ..VipTrialConfig::default()
        };
        let body = r#"{"vipStatus":0}"#;
        assert_eq!(apply_vip_trial(body, &cfg, NOW), body);
    }

    #[test]
    fn clears_playurl_trial_flag() {
        let body = r#"{"code":0,"data":{"quality":127,"trial":true,"dash":{"video":[],"audio":[]}}}"#;
        let out = apply_vip_trial(body, &VipTrialConfig::default(), NOW);
        let v: Value = serde_json::from_str(&out).unwrap();
        assert_eq!(v["data"]["trial"], json!(false));
        // 非 playurl 上下文里的同名字段不受影响
        let body2 = r#"{"trial":true}"#;
        let out2 = apply_vip_trial(body2, &VipTrialConfig::default(), NOW);
        assert!(out2.contains(r#""trial":true"#));
    }

    #[test]
    fn invalid_json_is_passthrough() {
        let body = "not json";
        assert_eq!(apply_vip_trial(body, &VipTrialConfig::default(), NOW), body);
    }
}