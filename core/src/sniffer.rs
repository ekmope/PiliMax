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

/// 解码后判定为可播放直链：必须是 http(s) 且路径/查询里带媒体后缀。
fn looks_like_media_url(s: &str) -> bool {
    let s = s.trim();
    if !s.starts_with("http://") && !s.starts_with("https://") {
        return false;
    }
    let lower = s.to_ascii_lowercase();
    lower.contains(".m3u8") || lower.contains(".mp4") || lower.contains(".flv")
}

/// 标准 Base64 解码（容忍缺省 padding 与空白，不支持 URL-safe 字母表）。
fn b64_decode(input: &str) -> Option<Vec<u8>> {
    let table = |c: u8| -> Option<u8> {
        match c {
            b'A'..=b'Z' => Some(c - b'A'),
            b'a'..=b'z' => Some(c - b'a' + 26),
            b'0'..=b'9' => Some(c - b'0' + 52),
            b'+' => Some(62),
            b'/' => Some(63),
            b'=' | b'\n' | b'\r' | b' ' | b'\t' => None,
            _ => Some(0xFF),
        }
    };
    let cleaned: Vec<u8> = input
        .bytes()
        .filter(|c| !matches!(c, b'\n' | b'\r' | b' ' | b'\t'))
        .collect();
    if cleaned.len() < 8 || cleaned.iter().any(|&c| table(c) == Some(0xFF)) {
        return None;
    }
    let mut out = Vec::with_capacity(cleaned.len() * 3 / 4);
    let mut acc: u32 = 0;
    let mut bits = 0u32;
    for c in &cleaned {
        if *c == b'=' {
            break;
        }
        acc = (acc << 6) | table(*c)? as u32;
        bits += 6;
        if bits >= 8 {
            bits -= 8;
            out.push((acc >> bits) as u8);
            acc &= (1 << bits) - 1;
        }
    }
    if out.is_empty() { None } else { Some(out) }
}

/// 尝试把 token 当作 Base64（标准形态 / fed 模板「3 字符随机前缀」形态）解出媒体直链。
fn decode_media_token(token: &str) -> Option<String> {
    let try_decode = |s: &str| -> Option<String> {
        let bytes = b64_decode(s)?;
        let text = String::from_utf8(bytes).ok()?;
        let text = text.trim_matches('\0').trim();
        looks_like_media_url(text).then(|| text.to_string())
    };
    try_decode(token).or_else(|| {
        // 苹果 CMS fed 播放模板：data-play = 3 位随机字符 + base64(真实地址)。
        token
            .char_indices()
            .nth(3)
            .map(|(i, _)| &token[i..])
            .and_then(try_decode)
    })
}

/// 苹果 CMS 经典 `player_aaaa` 配置：{"encrypt":0,"url":"直链或base64"}。
fn extract_player_aaaa(html: &str) -> Option<String> {
    let start = html.find("player_aaaa")?;
    let brace = html[start..].find('{')? + start;
    // 取到第一个 `};` 或 `}<` 边界（url 字段不会含未转义大括号）。
    let tail = &html[brace..];
    let end = tail
        .find("};")
        .map(|i| i + 1)
        .or_else(|| tail.find("}<"))
        .unwrap_or(tail.len().min(2000));
    let obj = serde_json::from_str::<serde_json::Value>(&tail[..end]).ok()?;
    let url = obj.get("url")?.as_str()?;
    let encrypt = obj.get("encrypt").and_then(|v| v.as_i64()).unwrap_or(0);
    if encrypt == 0 {
        looks_like_media_url(url).then(|| url.to_string())
    } else {
        decode_media_token(url)
    }
}

/// fed 播放模板：iframe 上 `data-play` 即「3 位前缀 + base64(直链)」。
fn extract_fed_data_play(html: &str) -> Option<String> {
    let re = Regex::new(r#"data-play=["']([A-Za-z0-9+/=_-]{16,})["']"#).ok()?;
    for caps in re.captures_iter(html) {
        if let Some(url) = caps
            .get(1)
            .map(|m| m.as_str())
            .and_then(decode_media_token)
        {
            return Some(url);
        }
    }
    None
}

/// 兜底：扫描页面中的长 Base64 片段，解出媒体直链（限制尝试次数防 CPU 浪费）。
fn scan_base64_media(html: &str) -> Option<String> {
    let re = Regex::new(r#"["']([A-Za-z0-9+/]{40,}={0,2})["']"#).ok()?;
    for caps in re.captures_iter(html).take(40) {
        if let Some(url) = caps
            .get(1)
            .map(|m| m.as_str())
            .and_then(decode_media_token)
        {
            return Some(url);
        }
    }
    None
}

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
    if let Some(url) = match_patterns(html, &defaults) {
        return Some(unescape(&url));
    }
    // 明文 URL 都没有时，处理常见播放器混淆。
    extract_player_aaaa(html)
        .or_else(|| extract_fed_data_play(html))
        .or_else(|| scan_base64_media(html))
        .map(|u| unescape(&u))
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

    #[test]
    fn decodes_fed_data_play() {
        let html = r#"<iframe id="fed-play-iframe" data-pars="/1006/vip/?url="
            data-play="FGyaHR0cHM6Ly92aXAuZHl0dC1ob3QuY29tLzIwMjUwMjEzLzcyOTE4X2IwYThkOTJiL2luZGV4Lm0zdTg="></iframe>"#;
        assert_eq!(
            sniff(html, None).unwrap(),
            "https://vip.dytt-hot.com/20250213/72918_b0a8d92b/index.m3u8"
        );
    }

    #[test]
    fn parses_player_aaaa_plain_and_encrypted() {
        let plain = r#"<script>var player_aaaa={"flag":"","encrypt":0,"url":"https://cdn.example.com/a/index.m3u8"}</script>"#;
        assert_eq!(sniff(plain, None).unwrap(), "https://cdn.example.com/a/index.m3u8");

        let enc_url = "https://cdn.example.com/b/play.m3u8";
        let b64 = simple_b64(enc_url.as_bytes());
        let encrypted = format!(
            r#"<script>var player_aaaa = {{"encrypt":1,"url":"{b64}"}};</script>"#
        );
        assert_eq!(sniff(&encrypted, None).unwrap(), enc_url);
    }

    /// 测试用标准 base64 编码。
    fn simple_b64(data: &[u8]) -> String {
        const T: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        let mut out = String::new();
        for chunk in data.chunks(3) {
            let b0 = chunk[0] as u32;
            let b1 = if chunk.len() > 1 { chunk[1] as u32 } else { 0 };
            let b2 = if chunk.len() > 2 { chunk[2] as u32 } else { 0 };
            let n = (b0 << 16) | (b1 << 8) | b2;
            out.push(T[((n >> 18) & 63) as usize] as char);
            out.push(T[((n >> 12) & 63) as usize] as char);
            if chunk.len() > 1 {
                out.push(T[((n >> 6) & 63) as usize] as char);
            } else {
                out.push('=');
            }
            if chunk.len() > 2 {
                out.push(T[(n & 63) as usize] as char);
            } else {
                out.push('=');
            }
        }
        out
    }
}
