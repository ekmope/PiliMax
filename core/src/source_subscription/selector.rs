//! web-selector 通用源引擎（animeko `SelectorMediaSource` 的 Rust 移植）。
//!
//! 按 `searchConfig` 中的 CSS 选择器与正则解析第三方站点的搜索结果、线路与集数。
//! 为保持核心可交叉编译、无网络依赖，本模块只实现纯解析（输入 HTML / 配置，输出结构化
//! 数据）；HTTP 抓取由 Android 壳完成，再调用这里的解析函数。

use std::collections::HashMap;

use regex::Regex;
use scraper::{ElementRef, Html, Selector};
use url::Url;

use super::{SourceChannel, SourceEpisode, SourceInstance, SourceSubject};

/// 单个数据源的解析配置 + 通用解析逻辑。
pub struct SelectorEngine {
    search_config: serde_json::Value,
    instance_name: String,
    instance_tier: i64,
}

impl SelectorEngine {
    pub fn new(instance: &SourceInstance) -> Self {
        let raw = instance
            .arguments
            .get("searchConfig")
            .cloned()
            .unwrap_or(serde_json::Value::Null);
        let search_config = if raw.is_object() {
            raw
        } else {
            serde_json::Value::Object(Default::default())
        };
        SelectorEngine {
            search_config,
            instance_name: instance.name(),
            instance_tier: instance.tier(),
        }
    }

    fn str_cfg(&self, key: &str) -> Option<String> {
        self.search_config
            .get(key)
            .and_then(|v| v.as_str())
            .map(|s| s.to_string())
    }

    fn map_cfg(&self, key: &str) -> Option<&serde_json::Map<String, serde_json::Value>> {
        self.search_config.get(key).and_then(|v| v.as_object())
    }

    fn bool_cfg(&self, key: &str) -> bool {
        self.search_config
            .get(key)
            .and_then(|v| v.as_bool())
            .unwrap_or(false)
    }

    pub fn match_video_config(&self) -> Option<&serde_json::Map<String, serde_json::Value>> {
        self.map_cfg("matchVideo")
    }

    pub fn match_video_url(&self) -> Option<String> {
        self.match_video_config()?
            .get("matchVideoUrl")
            .and_then(|v| v.as_str())
            .map(|s| s.to_string())
    }

    pub fn match_nested_url(&self) -> Option<String> {
        self.match_video_config()?
            .get("matchNestedUrl")
            .and_then(|v| v.as_str())
            .map(|s| s.to_string())
    }

    /// 追加到视频直链的请求头（`matchVideo.addHeadersToVideo`）。
    pub fn video_headers(&self) -> HashMap<String, String> {
        let mut headers = HashMap::new();
        if let Some(add) = self
            .match_video_config()
            .and_then(|m| m.get("addHeadersToVideo"))
            .and_then(|v| v.as_object())
        {
            for (k, v) in add {
                if let Some(s) = v.as_str() {
                    headers.insert(k.clone(), s.to_string());
                } else {
                    headers.insert(k.clone(), v.to_string());
                }
            }
        }
        headers
    }

    /// 直接用 `matchVideoUrl` 正则从页面 HTML 中提取直链。
    pub fn match_video(&self, html: &str) -> Option<String> {
        let pattern = self.match_video_url()?;
        if pattern.is_empty() {
            return None;
        }
        let re = Regex::new(&pattern).ok()?;
        let caps = re.captures(html)?;
        caps.get(0).or_else(|| caps.get(1)).map(|m| m.as_str().to_string())
    }

    /// 构造搜索 URL（含关键词归一化与 URL 编码）。
    pub fn build_search_url(&self, keyword: &str) -> Option<String> {
        let search_url = self.str_cfg("searchUrl")?;
        let mut kw = keyword.trim().to_string();
        if self.bool_cfg("searchUseOnlyFirstWord") {
            kw = kw.split_whitespace().next().unwrap_or("").to_string();
        }
        if self.bool_cfg("searchRemoveSpecial") {
            kw = remove_special(&kw);
        }
        Some(search_url.replace("{keyword}", &encode_component(&kw)))
    }

    fn resolve_base(&self, url: &str) -> String {
        if let Some(base) = self.str_cfg("rawBaseUrl") {
            if !base.is_empty() {
                return base;
            }
        }
        origin_of(url).unwrap_or_else(|| url.to_string())
    }

    /// 解析搜索结果页的条目列表（支持 indexed / flattened 两种条目格式）。
    pub fn parse_subject_list(&self, html: &str, base: &str) -> Vec<SourceSubject> {
        let document = Html::parse_document(html);
        let format_id = self
            .str_cfg("subjectFormatId")
            .unwrap_or_else(|| "flattened".to_string());
        let mut results: Vec<SourceSubject> = Vec::new();

        if format_id == "indexed" {
            let cfg = self.map_cfg("selectorSubjectFormatIndexed");
            let select_names = cfg
                .and_then(|c| c.get("selectNames"))
                .and_then(|v| v.as_str())
                .map(|s| s.to_string());
            let select_links = cfg
                .and_then(|c| c.get("selectLinks"))
                .and_then(|v| v.as_str())
                .map(|s| s.to_string());
            if let (Some(select_names), Some(select_links)) = (select_names, select_links) {
                let names = query_all(&document, &select_names);
                let links = query_all(&document, &select_links);
                for (name_el, link_el) in names.iter().zip(links.iter()) {
                    let name = name_el.text().collect::<String>().trim().to_string();
                    if let Some(href) = link_el.value().attr("href") {
                        if !name.is_empty() {
                            results.push(SourceSubject {
                                name,
                                url: abs(href, base),
                            });
                        }
                    }
                }
            }
        } else {
            let cfg = self.map_cfg("selectorSubjectFormatFlattened");
            let select_items = cfg
                .and_then(|c| c.get("selectItems"))
                .or_else(|| cfg.and_then(|c| c.get("selectNames")))
                .and_then(|v| v.as_str())
                .map(|s| s.to_string());
            if let Some(select_items) = select_items {
                for el in query_all(&document, &select_items) {
                    let name = el.text().collect::<String>().trim().to_string();
                    let href = el
                        .value()
                        .attr("href")
                        .map(|s| s.to_string())
                        .or_else(|| {
                            el.select(&Selector::parse("a").ok()?)
                                .next()
                                .and_then(|a| a.value().attr("href").map(|s| s.to_string()))
                        });
                    if !name.is_empty() {
                        if let Some(href) = href {
                            results.push(SourceSubject {
                                name,
                                url: abs(&href, base),
                            });
                        }
                    }
                }
            }
        }

        // 按 url 去重，保留首次出现。
        let mut seen: Vec<String> = Vec::new();
        results.retain(|s| {
            if seen.iter().any(|u| u == &s.url) {
                false
            } else {
                seen.push(s.url.clone());
                true
            }
        });
        results
    }

    /// 从搜索 URL 推导基准地址后解析条目列表。
    pub fn parse_subject_list_from_search_url(&self, html: &str, search_url: &str) -> Vec<SourceSubject> {
        let base = self.resolve_base(search_url);
        self.parse_subject_list(html, &base)
    }

    /// 解析条目详情页，得到线路与集数。
    pub fn parse_channels(&self, html: &str, subject_url: &str) -> Vec<SourceChannel> {
        let document = Html::parse_document(html);
        let channel_format = self
            .str_cfg("channelFormatId")
            .unwrap_or_else(|| "no-channel".to_string());

        let channel_tiers: HashMap<String, i64> = self
            .map_cfg("channelTiers")
            .map(|m| {
                m.iter()
                    .filter_map(|(k, v)| v.as_i64().map(|n| (k.clone(), n)))
                    .collect()
            })
            .unwrap_or_default();

        let tier_of = |name: &str| -> i64 {
            channel_tiers.get(name).copied().unwrap_or(self.instance_tier)
        };

        if channel_format == "index-grouped" {
            let cfg = self
                .map_cfg("selectorChannelFormatFlattened")
                .map(|m| m.clone())
                .unwrap_or_default();
            return self.parse_grouped_channels(&document, subject_url, &cfg, &tier_of);
        }

        // no-channel
        let cfg = self.map_cfg("selectorChannelFormatNoChannel");
        let select_episodes = cfg
            .and_then(|c| c.get("selectEpisodes"))
            .and_then(|v| v.as_str())
            .map(|s| s.to_string());
        let match_sort = self.str_cfg("matchEpisodeSortFromName");
        let root_el = document.root_element();
        let episodes = self.parse_episode_list(root_el, subject_url, select_episodes, match_sort);
        vec![SourceChannel {
            name: self.instance_name.clone(),
            tier: self.instance_tier,
            episodes,
        }]
    }

    fn parse_grouped_channels<F>(
        &self,
        document: &Html,
        subject_url: &str,
        cfg: &serde_json::Map<String, serde_json::Value>,
        tier_of: &F,
    ) -> Vec<SourceChannel>
    where
        F: Fn(&str) -> i64,
    {
        let mut results: Vec<SourceChannel> = Vec::new();

        let select_channel_names = cfg
            .get("selectChannelNames")
            .and_then(|v| v.as_str())
            .map(|s| s.to_string());
        let select_episode_lists = cfg
            .get("selectEpisodeLists")
            .and_then(|v| v.as_str())
            .map(|s| s.to_string());
        let select_episodes_from_list = cfg
            .get("selectEpisodesFromList")
            .and_then(|v| v.as_str())
            .unwrap_or("a")
            .to_string();
        let match_channel_name = cfg
            .get("matchChannelName")
            .and_then(|v| v.as_str())
            .map(|s| s.to_string())
            .filter(|s| !s.is_empty());
        let match_episode_sort = cfg
            .get("matchEpisodeSortFromName")
            .and_then(|v| v.as_str())
            .map(|s| s.to_string())
            .or_else(|| self.str_cfg("matchEpisodeSortFromName"));

        let channel_els = select_channel_names
            .as_deref()
            .map(|s| query_all(document, s))
            .unwrap_or_default();
        let list_els = select_episode_lists
            .as_deref()
            .map(|s| query_all(document, s))
            .unwrap_or_default();

        let count = channel_els.len().min(list_els.len());
        for i in 0..count {
            let mut name = channel_els[i].text().collect::<String>().trim().to_string();
            if let Some(ref pattern) = match_channel_name {
                if let Ok(re) = Regex::new(pattern) {
                    if let Some(caps) = re.captures(&name) {
                        if let Some(named) = caps.name("name") {
                            name = named.as_str().trim().to_string();
                        }
                    }
                }
            }
            let episodes = self.parse_episode_list(
                list_els[i],
                subject_url,
                Some(select_episodes_from_list.clone()),
                match_episode_sort.clone(),
            );
            if !episodes.is_empty() {
                let final_name = if name.is_empty() {
                    format!("线路{}", i + 1)
                } else {
                    name.clone()
                };
                results.push(SourceChannel {
                    name: final_name,
                    tier: tier_of(&name),
                    episodes,
                });
            }
        }
        results
    }

    fn parse_episode_list(
        &self,
        root_el: ElementRef<'_>,
        subject_url: &str,
        select: Option<String>,
        match_sort: Option<String>,
    ) -> Vec<SourceEpisode> {
        let mut episodes: Vec<SourceEpisode> = Vec::new();
        let Some(select) = select else {
            return episodes;
        };
        if select.is_empty() {
            return episodes;
        }
        let Ok(selector) = Selector::parse(&select) else {
            return episodes;
        };
        for el in root_el.select(&selector) {
            let anchor = el.text().collect::<String>().trim().to_string();
            let href = el
                .value()
                .attr("href")
                .map(|s| s.to_string())
                .or_else(|| {
                    el.select(&Selector::parse("a").ok()?)
                        .next()
                        .and_then(|a| a.value().attr("href").map(|s| s.to_string()))
                });
            let Some(href) = href else { continue };
            if anchor.is_empty() || href.starts_with("javascript") {
                continue;
            }
            let mut sort = anchor.clone();
            if let Some(ref pattern) = match_sort {
                if !pattern.is_empty() {
                    if let Ok(re) = Regex::new(pattern) {
                        if let Some(caps) = re.captures(&anchor) {
                            if let Some(ep) = caps.name("ep") {
                                sort = ep.as_str().trim().to_string();
                            } else if let Some(g) = caps.get(1) {
                                sort = g.as_str().trim().to_string();
                            } else {
                                sort = anchor.clone();
                            }
                        }
                    }
                }
            }
            episodes.push(SourceEpisode {
                name: anchor,
                sort,
                page_url: abs(&href, subject_url),
            });
        }
        episodes.sort_by(|a, b| {
            match (extract_number(&a.sort), extract_number(&b.sort)) {
                (Some(an), Some(bn)) => an
                    .partial_cmp(&bn)
                    .unwrap_or(std::cmp::Ordering::Equal)
                    .then(a.sort.cmp(&b.sort)),
                _ => a.sort.cmp(&b.sort),
            }
        });
        episodes
    }
}

/// 从字符串中提取首个数字序列（支持小数，例如 "第12.5集" → 12.5）。
/// 用于剧集名称的自然排序：纯数字直接比较，否则回退到字符串比较。
fn extract_number(s: &str) -> Option<f64> {
    let chars: Vec<char> = s.chars().collect();
    let mut start = 0;
    while start < chars.len() && !chars[start].is_ascii_digit() {
        start += 1;
    }
    let mut end = start;
    while end < chars.len() && (chars[end].is_ascii_digit() || chars[end] == '.') {
        end += 1;
    }
    if start == end {
        return None;
    }
    let num: String = chars[start..end].iter().collect();
    num.parse::<f64>().ok()
}

fn query_all<'a>(document: &'a Html, sel: &str) -> Vec<ElementRef<'a>> {
    match Selector::parse(sel) {
        Ok(s) => document.select(&s).collect(),
        Err(_) => Vec::new(),
    }
}

/// 相对 URL → 绝对 URL。
fn abs(href: &str, base: &str) -> String {
    if href.starts_with("http://") || href.starts_with("https://") {
        return href.to_string();
    }
    match Url::parse(base) {
        Ok(b) => b
            .join(href)
            .map(|u| u.to_string())
            .unwrap_or_else(|_| href.to_string()),
        Err(_) => href.to_string(),
    }
}

/// 取 URL 的 origin（scheme://host[:port]），用于相对路径解析基准。
fn origin_of(url: &str) -> Option<String> {
    let u = Url::parse(url).ok()?;
    let scheme = u.scheme();
    let host = u.host_str()?;
    Some(match u.port() {
        Some(p) => format!("{}://{}:{}", scheme, host, p),
        None => format!("{}://{}", scheme, host),
    })
}

/// URL 组件编码（保留 A-Za-z0-9 - _ . ~，与 Dart `Uri.encodeComponent` 一致）。
fn encode_component(input: &str) -> String {
    let mut out = String::with_capacity(input.len());
    for b in input.bytes() {
        match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                out.push(b as char);
            }
            _ => out.push_str(&format!("%{:02X}", b)),
        }
    }
    out
}

/// 将非 CJK / 字母数字的连续片段替换为单个空格（与 Dart `replaceAll(RegExp(r'[^...]+'), ' ')` 一致）。
fn remove_special(input: &str) -> String {
    let mut out = String::with_capacity(input.len());
    let mut in_run = false;
    for c in input.chars() {
        if c.is_ascii_alphanumeric() || matches!(c, '\u{4e00}'..='\u{9fa5}') {
            out.push(c);
            in_run = false;
        } else if !in_run {
            out.push(' ');
            in_run = true;
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn instance_with(search_config: serde_json::Value) -> SourceInstance {
        let mut arguments = serde_json::Map::new();
        arguments.insert("name".to_string(), serde_json::json!("测试源"));
        arguments.insert("searchConfig".to_string(), search_config);
        SourceInstance {
            instance_id: "inst".to_string(),
            factory_id: "web-selector".to_string(),
            is_enabled: true,
            sort_order: 0,
            subscription_id: None,
            arguments,
        }
    }

    #[test]
    fn encodes_and_builds_search_url() {
        let inst = instance_with(serde_json::json!({
            "searchUrl": "https://example.com/s?q={keyword}",
            "searchRemoveSpecial": true
        }));
        let engine = SelectorEngine::new(&inst);
        let url = engine.build_search_url(" 一拳 超人!! ").expect("url");
        assert_eq!(url, "https://example.com/s?q=%E4%B8%80%E6%8B%B3%20%E8%B6%85%E4%BA%BA%20");
    }

    #[test]
    fn parses_flattened_subjects() {
        let inst = instance_with(serde_json::json!({
            "rawBaseUrl": "https://example.com",
            "selectorSubjectFormatFlattened": {"selectItems": "a.item"}
        }));
        let engine = SelectorEngine::new(&inst);
        let html = r#"<a class="item" href="/v/1">番剧 A</a><a class="item" href="/v/1">重复</a>"#;
        let subjects = engine.parse_subject_list(html, "https://example.com");
        assert_eq!(subjects.len(), 1);
        assert_eq!(subjects[0].name, "番剧 A");
        assert_eq!(subjects[0].url, "https://example.com/v/1");
    }

    #[test]
    fn parses_no_channel_episodes() {
        let inst = instance_with(serde_json::json!({
            "selectorChannelFormatNoChannel": {"selectEpisodes": "a"},
            "rawBaseUrl": "https://example.com"
        }));
        let engine = SelectorEngine::new(&inst);
        let html = r#"<a href="/p/2">第2集</a><a href="/p/10">第10集</a><a href="/p/1">第1集</a>"#;
        let channels = engine.parse_channels(html, "https://example.com/ani/1");
        assert_eq!(channels.len(), 1);
        let eps = &channels[0].episodes;
        assert_eq!(eps[0].sort, "第1集");
        assert_eq!(eps[2].sort, "第10集");
    }

    #[test]
    fn matches_video_url() {
        let inst = instance_with(serde_json::json!({
            "matchVideo": {"matchVideoUrl": "https://cdn\\.example\\.com/[^\"']+\\.mp4"}
        }));
        let engine = SelectorEngine::new(&inst);
        let html = r#"<video src="https://cdn.example.com/v.mp4"></video>"#;
        assert_eq!(engine.match_video(html), Some("https://cdn.example.com/v.mp4".to_string()));
    }
}