//! 信息流规则过滤（思路来自 bilipai / BiliPaiPlus 的自定义屏蔽规则）。
//!
//! 规则以 JSON 描述，在 Rust 侧对候选视频数组做纯函数过滤，方便高频执行且零 GC 压力：
//! ```json
//! [
//!   { "name": "标题含抽奖", "enabled": true, "field": "title",
//!     "op": "contains", "value": "抽奖" },
//!   { "name": "短于10秒", "field": "duration", "op": "lt", "value": 10 }
//! ]
//! ```
//! 语义：任意一条启用的规则命中 → 该视频被隐藏（OR 隐藏，AND 保留）。

use regex::Regex;
use serde::Deserialize;
use serde_json::Value;

#[derive(Debug, Deserialize)]
pub struct FilterRule {
    #[serde(default)]
    pub name: String,
    #[serde(default = "default_true")]
    pub enabled: bool,
    #[serde(default)]
    pub field: String,
    #[serde(default)]
    pub op: String,
    #[serde(default)]
    pub value: Value,
}

fn default_true() -> bool {
    true
}

/// 对视频数组应用规则，返回过滤后的 JSON 数组字符串。
///
/// - `videos_json` 不是数组时原样返回；
/// - 规则非法（编译失败/字段缺失）时该条规则被跳过，不影响其他规则；
/// - 非 object 的数组元素永远保留。
pub fn apply(videos_json: &str, rules_json: &str) -> String {
    let videos: Value = match serde_json::from_str(videos_json) {
        Ok(v @ Value::Array(_)) => v,
        _ => return videos_json.to_string(),
    };
    let rules = parse_rules(rules_json);
    let compiled = compile_rules(&rules);

    let arr = match videos.as_array() {
        Some(a) => a,
        None => return videos_json.to_string(),
    };
    let kept: Vec<&Value> = arr
        .iter()
        .filter(|v| !v.is_object() || !compiled.iter().any(|r| r.matches(v)))
        .collect();
    serde_json::to_string(&kept).unwrap_or_else(|_| "[]".to_string())
}

fn parse_rules(raw: &str) -> Vec<FilterRule> {
    // 既接受裸数组，也接受 {"rules":[...]}。
    if let Ok(v) = serde_json::from_str::<Vec<FilterRule>>(raw) {
        return v;
    }
    #[derive(Deserialize)]
    struct Wrapper {
        #[serde(default)]
        rules: Vec<FilterRule>,
    }
    serde_json::from_str::<Wrapper>(raw)
        .map(|w| w.rules)
        .unwrap_or_default()
}

struct CompiledRule {
    field: String,
    op: Op,
}

enum Op {
    Contains(String),
    NotContains(String),
    Eq(String),
    Regex(Regex),
    Lt(f64),
    Gt(f64),
}

impl CompiledRule {
    fn matches(&self, video: &Value) -> bool {
        match self.op {
            Op::Contains(ref needle) => field_str(video, &self.field)
                .map(|s| s.to_lowercase().contains(&needle.to_lowercase()))
                .unwrap_or(false),
            Op::NotContains(ref needle) => match field_str(video, &self.field) {
                Some(s) => !s.to_lowercase().contains(&needle.to_lowercase()),
                None => false,
            },
            Op::Eq(ref target) => field_str(video, &self.field)
                .map(|s| s.eq_ignore_ascii_case(target))
                .unwrap_or(false),
            Op::Regex(ref re) => field_str(video, &self.field)
                .map(|s| re.is_match(&s))
                .unwrap_or(false),
            Op::Lt(n) => field_num(video, &self.field).map(|x| x < n).unwrap_or(false),
            Op::Gt(n) => field_num(video, &self.field).map(|x| x > n).unwrap_or(false),
        }
    }
}

fn compile_rules(rules: &[FilterRule]) -> Vec<CompiledRule> {
    rules
        .iter()
        .filter(|r| r.enabled)
        .filter_map(|r| {
            let op = match r.op.as_str() {
                "contains" => Op::Contains(r.value.as_str()?.to_string()),
                "not_contains" => Op::NotContains(r.value.as_str()?.to_string()),
                "eq" => Op::Eq(stringify_value(&r.value)),
                "regex" => Op::Regex(Regex::new(r.value.as_str()?).ok()?),
                "lt" => Op::Lt(r.value.as_f64()?),
                "gt" => Op::Gt(r.value.as_f64()?),
                _ => return None,
            };
            Some(CompiledRule {
                field: r.field.clone(),
                op,
            })
        })
        .collect()
}

fn stringify_value(v: &Value) -> String {
    match v {
        Value::String(s) => s.clone(),
        Value::Null => String::new(),
        other => other.to_string(),
    }
}

/// 读取视频对象上的文本字段，兼容 B 站 API 与本应用自己的多种命名。
fn field_str<'a>(video: &'a Value, field: &str) -> Option<String> {
    let obj = video.as_object()?;
    let candidates = field_aliases(field);
    for key in candidates {
        if let Some(v) = obj.get(key) {
            match v {
                Value::String(s) if !s.is_empty() => return Some(s.clone()),
                Value::Number(n) => return Some(n.to_string()),
                Value::Bool(b) => return Some(b.to_string()),
                _ => {}
            }
        }
    }
    None
}

fn field_num(video: &Value, field: &str) -> Option<f64> {
    let obj = video.as_object()?;
    for key in field_aliases(field) {
        if let Some(v) = obj.get(key) {
            if let Some(n) = v.as_f64() {
                return Some(n);
            }
            if let Some(s) = v.as_str() {
                if let Some(n) = parse_duration(s) {
                    return Some(n);
                }
                if let Ok(n) = s.parse::<f64>() {
                    return Some(n);
                }
            }
        }
    }
    None
}

fn field_aliases(field: &str) -> Vec<&str> {
    match field {
        "title" | "name" | "keyword" => vec!["title", "name", "keyword"],
        "uploader" | "author" | "up" | "owner" => {
            vec!["uploader", "author", "owner", "name", "uname"]
        }
        "duration" | "length" => vec!["duration", "length"],
        "view" | "play" | "stat_view" => {
            vec!["stat_view", "view", "play", "play_count"]
        }
        "danmaku" | "danmu" | "stat_danmu" => {
            vec!["stat_danmu", "danmaku", "danmu", "video_review"]
        }
        "bvid" | "id" => vec!["bvid", "id", "aid"],
        "tid" | "category" => vec!["tid", "category", "tname"],
        other => vec![other],
    }
}

/// 解析 "mm:ss" / "hh:mm:ss" 时长为秒（数值字段直接由上层处理）。
fn parse_duration(s: &str) -> Option<f64> {
    let parts: Vec<&str> = s.trim().split(':').collect();
    if parts.is_empty() || parts.len() > 3 {
        return None;
    }
    let mut secs = 0f64;
    for p in parts {
        secs = secs * 60.0 + p.parse::<f64>().ok()?;
    }
    Some(secs)
}

#[cfg(test)]
mod tests {
    use super::*;

    const VIDEOS: &str = r#"[
      {"title":"【抽奖】关注转发","author":"营销号","duration":120,"stat_view":5,"stat_danmu":0,"bvid":"BV1aa"},
      {"title":"正常视频","author":"正经UP","duration":600,"stat_view":9999,"stat_danmu":100,"bvid":"BV1bb"},
      {"title":"短视频","author":"正经UP","duration":8,"stat_view":50,"stat_danmu":1,"bvid":"BV1cc"}
    ]"#;

    #[test]
    fn contains_and_numeric_rules() {
        let rules = r#"[
          {"field":"title","op":"contains","value":"抽奖"},
          {"field":"duration","op":"lt","value":10}
        ]"#;
        let out = apply(VIDEOS, rules);
        assert!(out.contains("正常视频"));
        assert!(!out.contains("抽奖"));
        assert!(!out.contains("短视频"));
    }

    #[test]
    fn not_contains_hides_when_missing() {
        let rules = r#"[{"field":"title","op":"not_contains","value":"正常"}]"#;
        let out = apply(VIDEOS, rules);
        assert!(out.contains("正常视频"));
        assert!(!out.contains("抽奖"));
    }

    #[test]
    fn disabled_rules_ignored_and_alias_fields() {
        let rules = r#"{"rules":[
          {"enabled":false,"field":"title","op":"contains","value":"正常"},
          {"field":"uploader","op":"eq","value":"营销号"}
        ]}"#;
        let out = apply(VIDEOS, rules);
        assert!(out.contains("正常视频"));
        assert!(!out.contains("营销号"));
    }

    #[test]
    fn regex_and_duration_text() {
        let videos = r#"[
          {"title":"P1","duration":"00:30"},
          {"title":"P2","duration":"1:00:00"}
        ]"#;
        // 长于 60 秒被隐藏：P2（1:00:00）隐藏，P1（00:30）保留。
        let rules = r#"[{"field":"duration","op":"gt","value":60}]"#;
        let out = apply(videos, rules);
        assert!(out.contains("P1"));
        assert!(!out.contains("P2"));

        let rules2 = r#"[{"field":"title","op":"regex","value":"^P[0-9]$"}]"#;
        assert_eq!(apply(videos, rules2), "[]");
    }

    #[test]
    fn invalid_input_passthrough() {
        // 非数组原样返回
        assert_eq!(apply("{}", "[]"), "{}");
        // 非法规则不会误伤
        assert!(apply(VIDEOS, "[{bad").contains("正常视频"));
    }
}
