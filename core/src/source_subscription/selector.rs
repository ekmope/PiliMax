//! web-selector 通用源引擎（animeko `SelectorMediaSource` 的 Rust 移植）。
//!
//! 按 `searchConfig` 中的 CSS 选择器与正则解析第三方站点的搜索结果、线路与集数。
//! 为保持核心可交叉编译、无网络依赖，本模块只实现纯解析（输入 HTML / 配置，输出结构化
//! 数据）；HTTP 抓取由 Android 壳完成，再调用这里的解析函数。
//!
//! 格式与 open-ani/animeko 主分支（2026）保持一致：
//! - 条目格式：`a` / `indexed` / `json-path-indexed`；
//! - 线路格式：`index-grouped` / `no-channel`，均支持独立的链接选择器。

use std::collections::HashMap;

use regex::Regex;
use scraper::{ElementRef, Html, Selector};
use url::Url;

use super::{SourceChannel, SourceEpisode, SourceInstance, SourceSubject};

/// 条目解析用的最小 JSONPath 引擎（支持 `.key` / `[*]` / `['a','b']` 子集）。
use super::jsonpath;

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
    ///
    /// 与 animeko 一致：优先命名捕获组 `v`，没有则取整个匹配。
    pub fn match_video(&self, html: &str) -> Option<String> {
        let pattern = self.match_video_url()?;
        if pattern.is_empty() {
            return None;
        }
        let re = Regex::new(&pattern).ok()?;
        let caps = re.captures(html)?;
        caps.name("v")
            .or_else(|| caps.get(0))
            .map(|m| m.as_str().to_string())
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

    /// 条目解析的基准地址：`rawBaseUrl` 优先，否则取搜索 URL 的 origin。
    fn resolve_base(&self, url: &str) -> String {
        if let Some(base) = self.str_cfg("rawBaseUrl") {
            if !base.is_empty() {
                return base;
            }
        }
        origin_of(url).unwrap_or_else(|| url.to_string())
    }

    /// 解析搜索结果页的条目列表（a / indexed / json-path-indexed 三种格式）。
    pub fn parse_subject_list(&self, html: &str, base: &str) -> Vec<SourceSubject> {
        let document = Html::parse_document(html);
        let format_id = self
            .str_cfg("subjectFormatId")
            .unwrap_or_else(|| "a".to_string());

        let mut results: Vec<SourceSubject> = match format_id.as_str() {
            "a" => self.parse_subject_format_a(&document, base),
            "indexed" => self.parse_subject_format_indexed(&document, base),
            "json-path-indexed" => self.parse_subject_format_json_path(&document, base),
            _ => Vec::new(),
        };

        dedup_by_url(&mut results);
        results
    }

    /// 格式 `a`：直接选出 `<a>`，title 属性（非空）优先，否则用文本。
    fn parse_subject_format_a(&self, document: &Html, base: &str) -> Vec<SourceSubject> {
        let cfg = self.map_cfg("selectorSubjectFormatA");
        let select_lists = cfg.and_then(|c| str_field(c, "selectLists"));
        let Some(select_lists) = select_lists else {
            return Vec::new();
        };
        let elements = query_all(document, &select_lists);
        let mut results: Vec<SourceSubject> = elements
            .iter()
            .filter_map(|el| {
                let name = attr(el, "title");
                let name = if name.trim().is_empty() {
                    el.text().collect::<String>()
                } else {
                    name
                };
                let href = attr(el, "href");
                let name = name.trim().to_string();
                if name.is_empty() || href.trim().is_empty() {
                    None
                } else {
                    Some(SourceSubject {
                        name,
                        url: abs(&href, base),
                    })
                }
            })
            .collect();
        if opt_bool_field(cfg, "preferShorterName").unwrap_or(true) {
            results.sort_by_key(|s| s.name.len());
        }
        results
    }

    /// 格式 `indexed`：一条语句选名称、一条语句选链接，按顺序对应。
    fn parse_subject_format_indexed(&self, document: &Html, base: &str) -> Vec<SourceSubject> {
        let cfg = self.map_cfg("selectorSubjectFormatIndexed");
        let select_names = cfg.and_then(|c| str_field(c, "selectNames"));
        let select_links = cfg.and_then(|c| str_field(c, "selectLinks"));
        let (Some(select_names), Some(select_links)) = (select_names, select_links) else {
            return Vec::new();
        };

        let names: Vec<String> = query_all(document, &select_names)
            .iter()
            .map(|el| el.text().collect::<String>().trim().to_string())
            .filter(|s| !s.is_empty())
            .collect();
        let links: Vec<String> = query_all(document, &select_links)
            .iter()
            .map(|el| attr(el, "href").trim().to_string())
            .filter(|s| !s.is_empty())
            .collect();

        let mut results: Vec<SourceSubject> = names
            .into_iter()
            .zip(links)
            .map(|(name, href)| SourceSubject {
                name,
                url: abs(&href, base),
            })
            .collect();
        if opt_bool_field(cfg, "preferShorterName").unwrap_or(true) {
            results.sort_by_key(|s| s.name.len());
        }
        results
    }

    /// 格式 `json-path-indexed`：页面文本是 JSON，用 JSONPath 取名称/链接序列。
    fn parse_subject_format_json_path(&self, document: &Html, base: &str) -> Vec<SourceSubject> {
        let cfg = self.map_cfg("selectorSubjectFormatJsonPathIndexed");
        let links_path = cfg.and_then(|c| str_field(c, "selectLinks"));
        let names_path = cfg.and_then(|c| str_field(c, "selectNames"));
        let (Some(links_path), Some(names_path)) = (links_path, names_path) else {
            return Vec::new();
        };

        let links_p = match jsonpath::compile(&links_path) {
            Some(p) => p,
            None => return Vec::new(),
        };
        let names_p = match jsonpath::compile(&names_path) {
            Some(p) => p,
            None => return Vec::new(),
        };
        let text = document.root_element().text().collect::<String>();
        let json: serde_json::Value = match serde_json::from_str(text.trim()) {
            Ok(v) => v,
            Err(_) => return Vec::new(),
        };

        let links: Vec<String> = jsonpath::resolve(&json, &links_p)
            .into_iter()
            .filter_map(single_string)
            .filter(|s| !s.trim().is_empty())
            .collect();
        let names: Vec<String> = jsonpath::resolve(&json, &names_p)
            .into_iter()
            .filter_map(single_string)
            .filter(|s| !s.trim().is_empty())
            .collect();

        let mut results: Vec<SourceSubject> = names
            .into_iter()
            .zip(links)
            .map(|(name, href)| SourceSubject {
                name,
                url: abs(&href, base),
            })
            .collect();
        if opt_bool_field(cfg, "preferShorterName").unwrap_or(true) {
            results.sort_by_key(|s| s.name.len());
        }
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
        // Ktor: 基准地址 = 条目 URL 去掉最后一个路径段（保留 query）。
        let base = drop_last_path_segment(subject_url).unwrap_or_else(|| subject_url.to_string());

        match channel_format.as_str() {
            "index-grouped" => self.parse_grouped_channels(&document, &base),
            "no-channel" => {
                let episodes = self.parse_no_channel_episodes(&document, &base);
                vec![SourceChannel {
                    name: self.instance_name.clone(),
                    tier: self.instance_tier,
                    episodes,
                }]
            }
            _ => Vec::new(),
        }
    }

    /// index-grouped：线路名与剧集列表容器按顺序对应，容器内选剧集元素。
    fn parse_grouped_channels(&self, document: &Html, base: &str) -> Vec<SourceChannel> {
        let cfg = match self.map_cfg("selectorChannelFormatFlattened") {
            Some(c) => c.clone(),
            None => return Vec::new(),
        };
        let Some(select_channel_names) = str_field(&cfg, "selectChannelNames") else {
            return Vec::new();
        };
        let Some(select_episode_lists) = str_field(&cfg, "selectEpisodeLists") else {
            return Vec::new();
        };
        let select_episodes_from_list =
            str_field(&cfg, "selectEpisodesFromList").unwrap_or_else(|| "a".to_string());
        let select_episode_links_from_list =
            str_field(&cfg, "selectEpisodeLinksFromList").unwrap_or_default();
        let match_channel_name = str_field(&cfg, "matchChannelName");
        let match_ep_sort = str_field(&cfg, "matchEpisodeSortFromName")
            .or_else(|| self.str_cfg("matchEpisodeSortFromName"));

        let channel_regex = match_channel_name
            .filter(|s| !s.is_empty())
            .and_then(|p| Regex::new(&p).ok());

        let channel_texts: Vec<Option<String>> = query_all(document, &select_channel_names)
            .iter()
            .map(|el| {
                let text = el.text().collect::<String>().trim().to_string();
                if text.is_empty() {
                    return None;
                }
                match &channel_regex {
                    Some(re) => named_group_or_text(re, &text, "ch"),
                    None => Some(text),
                }
            })
            .collect();

        let list_elements = query_all(document, &select_episode_lists);
        let count = channel_texts.len().min(list_elements.len());

        let mut channels: Vec<SourceChannel> = Vec::new();
        for i in 0..count {
            let Some(channel_name) = &channel_texts[i] else {
                continue;
            };
            let episodes = self.parse_episode_elements(
                &list_elements[i],
                base,
                &select_episodes_from_list,
                &select_episode_links_from_list,
                match_ep_sort.as_deref(),
            );
            if !episodes.is_empty() {
                channels.push(SourceChannel {
                    name: channel_name.clone(),
                    tier: self.instance_tier,
                    episodes,
                });
            }
        }
        channels
    }

    /// no-channel：整页选出剧集元素。
    fn parse_no_channel_episodes(&self, document: &Html, base: &str) -> Vec<SourceEpisode> {
        let cfg = match self.map_cfg("selectorChannelFormatNoChannel") {
            Some(c) => c.clone(),
            None => return Vec::new(),
        };
        let Some(select_episodes) = str_field(&cfg, "selectEpisodes") else {
            return Vec::new();
        };
        let select_episode_links = str_field(&cfg, "selectEpisodeLinks").unwrap_or_default();
        let match_ep_sort = str_field(&cfg, "matchEpisodeSortFromName")
            .or_else(|| self.str_cfg("matchEpisodeSortFromName"));
        let root_el = document.root_element();
        self.parse_episode_elements(
            &root_el,
            base,
            &select_episodes,
            &select_episode_links,
            match_ep_sort.as_deref(),
        )
    }

    /// 在一个容器内选出剧集元素并映射为 [SourceEpisode]。
    fn parse_episode_elements(
        &self,
        container: &ElementRef<'_>,
        base: &str,
        select_episodes: &str,
        select_episode_links: &str,
        match_ep_sort: Option<&str>,
    ) -> Vec<SourceEpisode> {
        let Ok(ep_selector) = Selector::parse(select_episodes) else {
            return Vec::new();
        };
        // 独立的链接选择器（元素不是 <a> 时必须配置）。
        let links: Vec<String> = if !select_episode_links.trim().is_empty() {
            container
                .select(&Selector::parse(select_episode_links).unwrap_or_else(|_| {
                    Selector::parse("__never__").expect("static")
                }))
                .map(|el| attr(&el, "href").trim().to_string())
                .collect()
        } else {
            // 无独立链接选择器：使用元素自身 href。
            vec![]
        };
        let sort_regex = match_ep_sort
            .filter(|s| !s.is_empty())
            .and_then(|p| Regex::new(p).ok());

        let mut episodes: Vec<SourceEpisode> = container
            .select(&ep_selector)
            .enumerate()
            .filter_map(|(index, el)| {
                let text = el.text().collect::<String>();
                let anchor = text.trim().to_string();
                let href = if !links.is_empty() {
                    links.get(index).cloned().unwrap_or_default()
                } else {
                    attr(&el, "href").trim().to_string()
                };
                if anchor.is_empty()
                    || href.is_empty()
                    || href.starts_with("javascript")
                    || href.starts_with('#')
                {
                    return None;
                }
                let raw_sort = sort_regex
                    .as_ref()
                    .and_then(|re| named_group_or_text(re, &anchor, "ep"));
                let sort = convert_special_episode(&anchor, raw_sort.as_deref());
                Some(SourceEpisode {
                    name: anchor.clone(),
                    sort: sort.clone(),
                    page_url: abs(&href, base),
                })
            })
            .collect();

        // 自然排序：能解析成数字的按数字排，否则按字符串。
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

// ---------------- 工具函数 ----------------

fn str_field(map: &serde_json::Map<String, serde_json::Value>, key: &str) -> Option<String> {
    map.get(key).and_then(|v| v.as_str()).map(String::from)
}

/// 读取可选布尔字段：配置缺失或字段缺失时返回 None，由调用方给默认值。
fn opt_bool_field(
    map: Option<&serde_json::Map<String, serde_json::Value>>,
    key: &str,
) -> Option<bool> {
    map.and_then(|m| m.get(key)).and_then(|v| v.as_bool())
}

/// 取 JSON 值中首个字符串内容（数组/对象递归取首个字符串成员），
/// 对应 animeko `getSingleStringValueOrNull`。
fn single_string(v: &serde_json::Value) -> Option<String> {
    match v {
        serde_json::Value::String(s) => Some(s.clone()),
        serde_json::Value::Array(a) => a.iter().find_map(single_string),
        serde_json::Value::Object(o) => o.values().find_map(single_string),
        _ => None,
    }
}

/// 对应 animeko `getGroupValue`：命中命名捕获组取组内容；命中但组为空取整段匹配；
/// 完全未命中时**回退原文**（正则只是可选的提取器，不能因不匹配而丢掉元素）。
fn named_group_or_text(re: &Regex, text: &str, group: &str) -> Option<String> {
    match re.captures(text) {
        Some(caps) => Some(
            match caps.name(group) {
                Some(m) if !m.as_str().trim().is_empty() => m.as_str().to_string(),
                _ => caps
                    .get(0)
                    .map(|m| m.as_str().to_string())
                    .unwrap_or_else(|| text.to_string()),
            },
        ),
        None => Some(text.to_string()),
    }
}

///
/// 对应 animeko `SelectorChannelFormat.convertSpecialEpisodes`：
/// "正片/高清版/720P/1080P/4K..." 这类电影标记统一映射为 "1"；
/// 否则优先使用 `raw`，raw 不可解析为纯文本数字时保留。
fn convert_special_episode(text: &str, raw: Option<&str>) -> String {
    let is_movie = text == "正片"
        || text == "高清版"
        || text.contains("2160P")
        || text.contains("1440P")
        || text.contains("2K")
        || text.contains("4K")
        || text.contains("1080P")
        || text.contains("720P");

    if let Some(raw) = raw {
        if !raw.trim().is_empty() {
            return if is_movie { "1".to_string() } else { raw.trim().to_string() };
        }
    }
    if is_movie {
        "1".to_string()
    } else {
        text.trim().to_string()
    }
}

/// 从字符串中提取首个数字序列（支持小数，例如 "第12.5集" → 12.5）。
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

/// ElementRef 的属性值（不存在时返回空串）。
fn attr(el: &ElementRef<'_>, name: &str) -> String {
    el.value().attr(name).unwrap_or("").to_string()
}

fn query_all<'a>(document: &'a Html, sel: &str) -> Vec<ElementRef<'a>> {
    match Selector::parse(sel) {
        Ok(s) => document.select(&s).collect(),
        Err(_) => Vec::new(),
    }
}

fn dedup_by_url(results: &mut Vec<SourceSubject>) {
    let mut seen: Vec<String> = Vec::new();
    results.retain(|s| {
        if seen.iter().any(|u| u == &s.url) {
            false
        } else {
            seen.push(s.url.clone());
            true
        }
    });
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

/// 去掉 URL 最后一个路径段（保留 query），对应 Ktor `pathSegments.dropLast(1)`。
fn drop_last_path_segment(url: &str) -> Option<String> {
    let u = Url::parse(url).ok()?;
    let segs: Vec<&str> = u.path_segments()?.filter(|s| !s.is_empty()).collect();
    let kept = &segs[..segs.len().saturating_sub(1)];
    let mut b = u.clone();
    b.set_path(&("/".to_string() + &kept.join("/")));
    Some(b.to_string())
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
    fn parses_format_a() {
        let inst = instance_with(serde_json::json!({
            "subjectFormatId": "a",
            "selectorSubjectFormatA": {"selectLists": "a.item"}
        }));
        let engine = SelectorEngine::new(&inst);
        let html = r#"<a class="item" href="/v/1">长标题的番剧 AAAAA</a>
                      <a class="item" href="/v/2">短</a>"#;
        let subjects = engine.parse_subject_list(html, "https://example.com");
        assert_eq!(subjects.len(), 2);
        // preferShorterName：短标题排前面
        assert_eq!(subjects[0].name, "短");
        assert_eq!(subjects[0].url, "https://example.com/v/2");
    }

    #[test]
    fn parses_indexed_subjects() {
        let inst = instance_with(serde_json::json!({
            "subjectFormatId": "indexed",
            "selectorSubjectFormatIndexed": {
                "selectNames": ".n",
                "selectLinks": ".l"
            }
        }));
        let engine = SelectorEngine::new(&inst);
        let html = r#"<div class="n">番剧 A</div><a class="l" href="/v/1"></a>
                      <div class="n">番剧 B</div><a class="l" href="/v/2"></a>"#;
        let subjects = engine.parse_subject_list(html, "https://example.com");
        assert_eq!(subjects.len(), 2);
        assert_eq!(subjects[0].name, "番剧 A");
        assert_eq!(subjects[0].url, "https://example.com/v/1");
    }

    #[test]
    fn parses_grouped_channels() {
        let inst = instance_with(serde_json::json!({
            "channelFormatId": "index-grouped",
            "selectorChannelFormatFlattened": {
                "selectChannelNames": ".tabs a",
                "matchChannelName": "^(?<ch>.+?)(\\d+)?$",
                "selectEpisodeLists": ".list",
                "selectEpisodesFromList": "a",
                "matchEpisodeSortFromName": "第\\s*(?<ep>.+)\\s*[话集]"
            }
        }));
        let engine = SelectorEngine::new(&inst);
        let html = r#"
          <div class="tabs"><a>线路1</a><a>线路2</a></div>
          <div class="list"><a href="/p/2">第2话</a><a href="/p/1">第1话</a></div>
          <div class="list"><a href="/p/4">第4话</a><a href="/p/3">第3话</a></div>
        "#;
        let channels = engine.parse_channels(html, "https://example.com/vod/detail/100.html");
        assert_eq!(channels.len(), 2);
        assert_eq!(channels[0].name, "线路");
        let sorts: Vec<&String> = channels[0].episodes.iter().map(|e| &e.sort).collect();
        assert_eq!(sorts, vec!["1", "2"]);
    }

    #[test]
    fn no_channel_with_separate_links() {
        let inst = instance_with(serde_json::json!({
            "channelFormatId": "no-channel",
            "selectorChannelFormatNoChannel": {
                "selectEpisodes": ".eps li",
                "selectEpisodeLinks": ".eps a",
                "matchEpisodeSortFromName": "第\\s*(?<ep>.+)\\s*[话集]"
            }
        }));
        let engine = SelectorEngine::new(&inst);
        let html = r#"
          <ul class="eps">
            <li><a href="/p/2">第2话</a></li><li><a href="/p/1">第1话</a></li>
          </ul>
        "#;
        let channels = engine.parse_channels(html, "https://example.com/ani/5");
        assert_eq!(channels.len(), 1);
        let eps = &channels[0].episodes;
        assert_eq!(eps[0].sort, "1");
        assert_eq!(eps[0].page_url, "https://example.com/p/1");
    }

    #[test]
    fn special_movie_episode_becomes_one() {
        assert_eq!(convert_special_episode("正片", Some("正片")), "1");
        assert_eq!(convert_special_episode("1080P", Some("1080P")), "1");
        assert_eq!(convert_special_episode("第5话", Some("5")), "5");
        assert_eq!(convert_special_episode("OVA", None), "OVA");
    }

    #[test]
    fn match_video_group_v() {
        let inst = instance_with(serde_json::json!({
            "matchVideo": {"matchVideoUrl": "url=(?<v>.+playlist\\.m3u8)"}
        }));
        let engine = SelectorEngine::new(&inst);
        let html = r#"<iframe src="url=https://cdn.example.com/a/playlist.m3u8"></iframe>"#;
        assert_eq!(
            engine.match_video(html),
            Some("https://cdn.example.com/a/playlist.m3u8".to_string()),
        );
    }

    #[test]
    fn jsonpath_dot_and_union() {
        let v: serde_json::Value = serde_json::from_str(
            r#"{"data":{"videos":[{"slug":"a","name":"A"},{"slug":"b","name":"B"}]}}"#,
        )
        .unwrap();
        let p = jsonpath::compile("$.data.videos[*].slug").unwrap();
        let got: Vec<String> = jsonpath::resolve(&v, &p)
            .into_iter()
            .filter_map(single_string)
            .collect();
        assert_eq!(got, vec!["a", "b"]);

        let v2: serde_json::Value = serde_json::from_str(
            r#"[{"url":"/u1","title":"T1"}]"#,
        )
        .unwrap();
        let p2 = jsonpath::compile("$[*]['url', 'link']").unwrap();
        let got2: Vec<String> = jsonpath::resolve(&v2, &p2)
            .into_iter()
            .filter_map(single_string)
            .collect();
        assert_eq!(got2, vec!["/u1"]);
    }
}
