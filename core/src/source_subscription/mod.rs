//! animeko 风格「源订阅 / 多源聚合」的模型与清单解析。
//!
//! 端口自 Dart 端 `services/source_subscription/models.dart`：订阅指向一个 animeko
//! 兼容 JSON 清单，清单内每条记录会实例化为一个数据源。仅做纯数据建模与解析，不涉及
//! 网络 I/O（网络由 Android 壳完成）。

use serde::{Deserialize, Serialize};

pub mod selector;

/// 源订阅：一个 URL 指向 animeko 兼容的 JSON 清单。
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SourceSubscription {
    #[serde(rename = "subscriptionId")]
    pub subscription_id: String,
    pub url: String,
    #[serde(default = "default_update_period_sec")]
    pub update_period_sec: i64,
    #[serde(rename = "lastUpdateAt")]
    pub last_update_at: Option<i64>,
    #[serde(rename = "mediaSourceCount")]
    pub media_source_count: Option<i64>,
    #[serde(rename = "lastError")]
    pub last_error: Option<String>,
}

fn default_update_period_sec() -> i64 {
    3600
}

impl SourceSubscription {
    /// 是否已过期（距离上次更新超过更新周期）。
    pub fn is_outdated(&self, now_ms: i64) -> bool {
        match self.last_update_at {
            None => true,
            Some(last) => now_ms - last > self.update_period_sec * 1000,
        }
    }
}

/// 订阅清单中的单个数据源导出数据（animeko `ExportedMediaSourceData`）。
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExportedMediaSourceData {
    #[serde(rename = "factoryId")]
    pub factory_id: String,
    #[serde(default = "default_version")]
    pub version: i64,
    #[serde(default)]
    pub arguments: serde_json::Map<String, serde_json::Value>,
}

fn default_version() -> i64 {
    1
}

/// 订阅 URL 返回的顶层 JSON。
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SubscriptionManifest {
    #[serde(rename = "mediaSources")]
    pub media_sources: Vec<ExportedMediaSourceData>,
}

impl SubscriptionManifest {
    /// 解析清单。兼容两种顶层结构：
    /// - `{"exportedMediaSourceDataList": {"mediaSources": [...]}}`
    /// - `{"mediaSources": [...]}`
    pub fn parse(body: &str) -> Option<SubscriptionManifest> {
        let value: serde_json::Value = serde_json::from_str(body).ok()?;
        let root = value.as_object()?;

        let list: Option<&serde_json::Value> = if let Some(exported) =
            root.get("exportedMediaSourceDataList").and_then(|v| v.as_object())
        {
            exported.get("mediaSources")
        } else {
            root.get("mediaSources")
        };

        let arr = list?.as_array()?;
        let media_sources = arr
            .iter()
            .filter_map(|e| serde_json::from_value::<ExportedMediaSourceData>(e.clone()).ok())
            .collect();

        Some(SubscriptionManifest { media_sources })
    }
}

/// 数据源实例：由订阅或用户手动创建，持久化并在运行期实例化。
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SourceInstance {
    #[serde(rename = "instanceId")]
    pub instance_id: String,
    #[serde(rename = "factoryId")]
    pub factory_id: String,
    #[serde(rename = "isEnabled", default = "default_true")]
    pub is_enabled: bool,
    #[serde(rename = "sortOrder", default)]
    pub sort_order: i64,
    #[serde(rename = "subscriptionId")]
    pub subscription_id: Option<String>,
    #[serde(default)]
    pub arguments: serde_json::Map<String, serde_json::Value>,
}

fn default_true() -> bool {
    true
}

impl SourceInstance {
    pub fn name(&self) -> String {
        self.arguments
            .get("name")
            .and_then(|v| v.as_str())
            .map(|s| s.to_string())
            .unwrap_or_else(|| self.instance_id.clone())
    }

    pub fn description(&self) -> Option<String> {
        self.arguments
            .get("description")
            .and_then(|v| v.as_str())
            .map(|s| s.to_string())
    }

    pub fn icon_url(&self) -> Option<String> {
        self.arguments
            .get("iconUrl")
            .and_then(|v| v.as_str())
            .map(|s| s.to_string())
    }

    pub fn tier(&self) -> i64 {
        self.arguments
            .get("tier")
            .and_then(|v| v.as_i64())
            .unwrap_or(0)
    }
}

/// 一次源查询得到的条目（番剧/影视等聚合条目）。
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SourceSubject {
    pub name: String,
    pub url: String,
}

/// 条目下的一条线路（如"新番主线①"）。
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SourceChannel {
    pub name: String,
    pub tier: i64,
    pub episodes: Vec<SourceEpisode>,
}

/// 线路内的一集。
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SourceEpisode {
    pub name: String,
    pub sort: String,
    #[serde(rename = "pageUrl")]
    pub page_url: String,
}

/// 按名称 diff 订阅清单并应用到实例列表：增/删/改 + 顺序跟随远程。
/// 返回此次更新涉及的实例数量（新增 + 更新）。
pub fn apply_manifest(
    subscription_id: &str,
    manifest: &SubscriptionManifest,
    instances: &mut Vec<SourceInstance>,
) -> usize {
    // imported：按名称去重（保留首次出现）。
    let mut imported: Vec<(String, ExportedMediaSourceData)> = Vec::new();
    for m in &manifest.media_sources {
        if let Some(name) = m.arguments.get("name").and_then(|v| v.as_str()) {
            if !name.is_empty() && !imported.iter().any(|(n, _)| n == name) {
                imported.push((name.to_string(), m.clone()));
            }
        }
    }
    if imported.is_empty() {
        return 0;
    }

    // 删除：订阅内本地有、远程没有。
    instances.retain(|i| {
        if i.subscription_id.as_deref() != Some(subscription_id) {
            return true;
        }
        imported.iter().any(|(name, _)| name == &i.name())
    });

    // 新增/更新 + 按远程顺序重排。
    let mut order: i64 = 0;
    let mut updated = 0usize;
    for (name, data) in &imported {
        order += 1;
        let pos = instances.iter().position(|i| {
            i.subscription_id.as_deref() == Some(subscription_id) && i.name() == *name
        });
        if let Some(pos) = pos {
            instances[pos].arguments = data.arguments.clone();
            instances[pos].sort_order = order;
        } else {
            instances.push(SourceInstance {
                instance_id: format!("{}:{}", subscription_id, name),
                factory_id: data.factory_id.clone(),
                is_enabled: true,
                sort_order: order,
                subscription_id: Some(subscription_id.to_string()),
                arguments: data.arguments.clone(),
            });
        }
        updated += 1;
    }
    updated
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_exported_top_level() {
        let body = r#"{"mediaSources":[{"factoryId":"web-selector","version":1,"arguments":{"name":"源A"}}]}"#;
        let m = SubscriptionManifest::parse(body).expect("manifest");
        assert_eq!(m.media_sources.len(), 1);
        assert_eq!(m.media_sources[0].factory_id, "web-selector");
    }

    #[test]
    fn parses_wrapped_list() {
        let body = r#"{"exportedMediaSourceDataList":{"mediaSources":[{"factoryId":"web-selector","arguments":{"name":"源B"}}]}}"#;
        let m = SubscriptionManifest::parse(body).expect("manifest");
        assert_eq!(m.media_sources.len(), 1);
    }

    #[test]
    fn rejects_invalid() {
        assert!(SubscriptionManifest::parse("not json").is_none());
        assert!(SubscriptionManifest::parse(r#"{"other":1}"#).is_none());
    }

    #[test]
    fn instance_defaults() {
        let inst: SourceInstance = serde_json::from_str(
            r#"{"instanceId":"a","factoryId":"web-selector","arguments":{"name":"源"}}"#,
        )
        .expect("instance");
        assert!(inst.is_enabled);
        assert_eq!(inst.sort_order, 0);
        assert_eq!(inst.name(), "源");
    }

    #[test]
    fn applies_manifest_diff() {
        let manifest = SubscriptionManifest::parse(
            r#"{"mediaSources":[
                {"factoryId":"web-selector","arguments":{"name":"源B"}},
                {"factoryId":"web-selector","arguments":{"name":"源A"}}
            ]}"#,
        )
        .expect("manifest");
        let mut instances = vec![SourceInstance {
            instance_id: "sub:源A".to_string(),
            factory_id: "web-selector".to_string(),
            is_enabled: true,
            sort_order: 1,
            subscription_id: Some("sub".to_string()),
            arguments: serde_json::json!({"name":"源A"}).as_object().unwrap().clone(),
        }];
        let n = apply_manifest("sub", &manifest, &mut instances);
        assert_eq!(n, 2);
        // 源B 新增，源A 保留并重排，无多余实例。
        assert_eq!(instances.len(), 2);
        let names: Vec<String> = instances.iter().map(|i| i.name()).collect();
        assert!(names.contains(&"源A".to_string()));
        assert!(names.contains(&"源B".to_string()));
    }
}