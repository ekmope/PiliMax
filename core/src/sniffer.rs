//! 视频地址嗅探器（kazumi 规则集的实用子集）。
//!
//! 源详情页拿到的往往不是直链，而是内嵌播放器 / 混淆 JS，本模块按正则优先级从 HTML 中
//! 提取直链（m3u8 / mp4 / flv）或嵌套页面地址（iframe / 跳转 URL）。
//!
//! 配置形如：
//! ```json
//! {
//!   "patterns": ["https?://[^\"']+?\\.m3u8[^\"']*"],
//!   "nestedPatterns": ["<iframe[^>]+src=[\"']([^\"']+)[\"']"]
//! }
//! ```
//! 带捕获组时取第一个捕获组，否则取整段匹配；按数组顺序首个命中即返回。

use regex::Regex;
use serde::Deserialize;

#[derive(Debug, Default, Deserialize)]
#[serde(default)]
pub struct SnifferConfig {
    /// 直链匹配（命中即播放）。
    pub patterns: Vec<String>,
    /// 嵌套页匹配（命中后由壳再次抓取该 URL 并重新嗅探）。
    #[serde(rename = "nestedPatterns")]
    pub nested_patterns: Vec<String>,
}

/// 内置直链兜底规则：兼容正斜杠与 JS 转义 `\/` 的写法。
/// 注意：转义形态的 URL 路径中本身含有反斜杠，字符类不能排除 `\`。
const DEFAULT_PATTERNS: &[&str] = &[
    r#"https?:\\/\\/[^"'\s<>]+?\.m3u8(?:\\?\?[^"'\s<>]*)?"#,
    r#"https?://[^"'\s<>]+?\.m3u8(?:\?[^"'\s<>]*)?"#,
    r#"https?:\\/\\/[^"'\s<>]+?\.mp4(?:\\?\?[^"'\s<>]*)?"#,
    r#"https?://[^"'\s<>]+?\.mp4(?:\?[^"'\s<>]*)?"#,
    r#"https?://[^"'\s<>]+?\.flv(?:\?[^"'\s<>]*)?"#,
];

/// 嵌套页兜底：iframe src / location 跳转 / 常见 player 路径。
const DEFAULT_NESTED: &[&str] = &[
    r#"<iframe[^>]+src=["']([^"']+)["']"#,
    r#"["'](?:url|link|src|file)["']\s*[:=]\s*["']([^"']+)["']"#,
    r#"(?:window\.)?location(?:\.href)?\s*=\s*["']([^"']+)["']"#,
];

fn load_config(raw: Option<&str>) -> SnifferConfig {
    raw.and_then(|s| serde_json::from_str::<SnifferConfig>(s).ok())
        .unwrap_or_default()
}

/// 嗅探视频直链。自定义规则优先；未命中（或规则全失效）时回退内置规则。
pub fn sniff(html: &str, config: Option<&str>) -> Option<String> {
    let cfg = load_config(config);
    if let Some(url) = match_patterns(html, &cfg.patterns) {
        return Some(unescape(&url));
    }
    let defaults: Vec<String> = DEFAULT_PATTERNS.iter().map(|s| s.to_string()).collect();
    match_patterns(html, &defaults).map(|u| unescape(&u))
}

/// 嗅探嵌套页面地址（壳随后重新抓取并递归 `sniff`）。
pub fn sniff_nested(html: &str, config: Option<&str>) -> Option<String> {
    let cfg = load_config(config);
    if let Some(url) = match_patterns(html, &cfg.nested_patterns) {
        return Some(unescape(&url));
    }
    let defaults: Vec<String> = DEFAULT_NESTED.iter().map(|s| s.to_string()).collect();
    match_patterns(html, &defaults).map(|u| unescape(&u))
}

fn match_patterns(html: &str, patterns: &[String]) -> Option<String> {
    for raw in patterns {
        let re = match Regex::new(raw) {
            Ok(re) => re,
            // 单条坏规则不应让整套嗅探失败。
            Err(_) => continue,
        };
        if let Some(caps) = re.captures(html) {
            let hit = caps
                .get(1)
                .or_else(|| caps.get(0))
                .map(|m| m.as_str().to_string());
            if let Some(url) = hit {
                if !url.is_empty() {
                    return Some(url);
                }
            }
        }
    }
    None
}

/// 还原 JS/HTML 转义：`\/` → `/`，常见 HTML 实体。
fn unescape(s: &str) -> String {
    s.replace("\\/", "/")
        .replace("&amp;", "&")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&quot;", "\"")
        .replace("&#x2F;", "/")
        .replace("\\u002F", "/")
        .replace("\\u002f", "/")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn finds_m3u8_with_escaped_slashes() {
        let html = r#"<script>var player="https:\/\/cdn.example.com\/path\/index.m3u8?auth=123&t=9"</script>"#;
        let url = sniff(html, None).unwrap();
        assert_eq!(url, "https://cdn.example.com/path/index.m3u8?auth=123&t=9");
    }

    #[test]
    fn finds_plain_mp4_before_html_boundary() {
        let html = r#"<video src="https://v.example.com/a/b.mp4"></video>"#;
        let url = sniff(html, None).unwrap();
        assert_eq!(url, "https://v.example.com/a/b.mp4");
    }

    #[test]
    fn custom_pattern_has_priority() {
        let html = "data-url=\"https://x.com/a.m3u8\"; other=\"https://y.com/b.mp4\"";
        let cfg = r#"{"patterns":["https://y\\.com/[^\"]+"]}"#;
        let url = sniff(html, Some(cfg)).unwrap();
        assert_eq!(url, "https://y.com/b.mp4");
    }

    #[test]
    fn nested_iframe_and_location() {
        let html = r#"<div><iframe allowfullscreen src="/player/123.html"></iframe></div>"#;
        assert_eq!(sniff_nested(html, None).unwrap(), "/player/123.html");

        let js = r#"<script>location.href = "https://play.example.com/e/42"</script>"#;
        assert_eq!(
            sniff_nested(js, None).unwrap(),
            "https://play.example.com/e/42"
        );
    }

    #[test]
    fn no_match_is_none() {
        assert!(sniff("<html>nothing</html>", None).is_none());
        // 坏正则被跳过
        assert!(sniff("https://x.com/a.m3u8", Some(r#"{"patterns":["([unclosed"]}"#)).is_some());
    }
}
