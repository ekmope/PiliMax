//! B 站弹幕解析与合并。
//!
//! 支持两种载荷：
//! - 旧版 XML（`https://comment.bilibili.com/{cid}.xml`）：`<d p="时间,模式,字号,颜色,...">文本</d>`；
//! - 新版 protobuf（`/x/v2/dm/web/seg.so`）：手写的最小 protobuf 线格式解码器，
//!   只取渲染所需字段（progress / mode / color / content），不引入 prost/protoc 依赖。
//!
//! 合并算法参考 pakku / PiliNara：规范化（去空白与标点、小写）后相同文本，
//! 在滚动时间窗内只保留最早的一条并累加计数，显著降低弹幕密度与渲染开销。

use std::collections::HashMap;

use serde::{Deserialize, Serialize};

/// 渲染所需的最小弹幕模型。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Danmaku {
    /// 出现时间（秒）。
    pub t: f64,
    /// 模式：1-3 滚动，4 底部，5 顶部，6 逆向，7 高级，8 代码，9 BAS。
    pub mode: u32,
    /// 颜色（0xRRGGBB）。
    pub color: u32,
    /// 文本。
    pub text: String,
    /// 合并计数（>= 1，渲染时可附加 ×N）。
    pub count: u32,
}

/// 解析旧版 XML 弹幕。
pub fn parse_xml(body: &str) -> Vec<Danmaku> {
    let bytes = body.as_bytes();
    let mut out: Vec<Danmaku> = Vec::new();
    let mut i = 0usize;
    while i < bytes.len() {
        // 寻找下一个 <d
        if bytes[i] == b'<' && body[i..].starts_with("<d") {
            // 标签起点，找该标签的结束 '>'
            let tag_start = i + 2;
            let mut j = tag_start;
            while j < bytes.len() && bytes[j] != b'>' {
                j += 1;
            }
            if j >= bytes.len() {
                break;
            }
            let tag = &body[tag_start..j]; // 形如 ` p="..."/`
            let self_closing = tag.trim_end().ends_with('/');
            let content_start = j + 1;

            // 提取 p="..." 属性。
            let p_value = tag.find("p=\"").and_then(|s| {
                let vstart = s + 3;
                tag[vstart..]
                    .find('"')
                    .map(|e| tag[vstart..vstart + e].to_string())
            });

            if self_closing {
                i = j + 1;
                continue;
            }

            // 文本截至 </d>
            if let Some(rel) = body[content_start..].find("</d>") {
                let raw_text = &body[content_start..content_start + rel];
                let end = content_start + rel + 4;
                if let Some(p) = p_value {
                    if let Some(d) = parse_xml_d(&p, raw_text) {
                        out.push(d);
                    }
                }
                i = end;
                continue;
            }
        }
        i += 1;
    }
    out
}

fn parse_xml_d(p: &str, raw_text: &str) -> Option<Danmaku> {
    let parts: Vec<&str> = p.split(',').collect();
    if parts.len() < 4 {
        return None;
    }
    let t: f64 = parts[0].parse().ok()?;
    let mode: u32 = parts[1].parse().unwrap_or(1);
    // parts[2] 字号，渲染端自行决定。
    let color: u32 = parts[3].parse().unwrap_or(0xFFFFFF);
    let text = unescape_xml(raw_text);
    if text.trim().is_empty() {
        return None;
    }
    Some(Danmaku {
        t,
        mode,
        color,
        text,
        count: 1,
    })
}

/// 解析 `/x/v2/dm/web/seg.so` 的 protobuf 响应。
pub fn parse_seg_so(body: &[u8]) -> Vec<Danmaku> {
    let mut out: Vec<Danmaku> = Vec::new();
    let mut cur = 0usize;
    while cur < body.len() {
        let (key, next) = match read_varint(body, cur) {
            Some(v) => v,
            None => break,
        };
        let field = key >> 3;
        let wire = (key & 0x7) as u8;
        cur = next;
        if field == 1 && wire == 2 {
            // DmSegMobileReply.elems
            let (len, after_len) = match read_varint(body, cur) {
                Some(v) => v,
                None => break,
            };
            let end = after_len.saturating_add(len as usize).min(body.len());
            if let Some(d) = parse_elem(&body[after_len..end]) {
                out.push(d);
            }
            cur = end;
        } else {
            cur = skip_field(body, cur, wire);
            if cur == usize::MAX {
                break;
            }
        }
    }
    out
}

fn parse_elem(buf: &[u8]) -> Option<Danmaku> {
    let mut progress_ms: i64 = 0;
    let mut mode: u32 = 1;
    let mut color: u32 = 0xFFFFFF;
    let mut content = String::new();

    let mut cur = 0usize;
    while cur < buf.len() {
        let (key, next) = read_varint(buf, cur)?;
        let field = key >> 3;
        let wire = (key & 0x7) as u8;
        cur = next;
        match (field, wire) {
            (2, 0) => {
                let (v, n) = read_varint(buf, cur)?;
                progress_ms = v as i64;
                cur = n;
            }
            (3, 0) => {
                let (v, n) = read_varint(buf, cur)?;
                mode = v as u32;
                cur = n;
            }
            (5, 0) => {
                let (v, n) = read_varint(buf, cur)?;
                color = v as u32;
                cur = n;
            }
            (7, 2) => {
                let (len, after_len) = read_varint(buf, cur)?;
                let end = after_len.saturating_add(len as usize).min(buf.len());
                content = String::from_utf8_lossy(&buf[after_len..end]).into_owned();
                cur = end;
            }
            _ => {
                cur = skip_field(buf, cur, wire);
                if cur == usize::MAX {
                    return None;
                }
            }
        }
    }

    if content.trim().is_empty() {
        return None;
    }
    Some(Danmaku {
        t: progress_ms as f64 / 1000.0,
        mode: normalize_mode(mode),
        color,
        text: content,
        count: 1,
    })
}

/// 服务端 mode 枚举对齐到渲染端使用的 1-9 语义（未知值回落滚动）。
fn normalize_mode(mode: u32) -> u32 {
    match mode {
        1..=9 => mode,
        _ => 1,
    }
}

fn read_varint(buf: &[u8], start: usize) -> Option<(u64, usize)> {
    let mut value: u64 = 0;
    let mut shift = 0u32;
    let mut i = start;
    loop {
        if i >= buf.len() || shift >= 64 {
            return None;
        }
        let b = buf[i];
        value |= ((b & 0x7F) as u64) << shift;
        i += 1;
        if b & 0x80 == 0 {
            return Some((value, i));
        }
        shift += 7;
    }
}

/// 跳过未知字段；返回 usize::MAX 表示载荷损坏。
fn skip_field(buf: &[u8], start: usize, wire: u8) -> usize {
    match wire {
        0 => read_varint(buf, start).map(|(_, n)| n).unwrap_or(usize::MAX),
        1 => start.saturating_add(8).min(buf.len()),
        2 => match read_varint(buf, start) {
            Some((len, n)) => n.saturating_add(len as usize).min(buf.len()),
            None => usize::MAX,
        },
        5 => start.saturating_add(4).min(buf.len()),
        // 已废弃的 group（wire 3 开始 / 4 结束）：弹幕载荷里不会出现，保守中止。
        _ => usize::MAX,
    }
}

/// 合并弹幕：输入任意顺序的弹幕，输出按时间排序、去重合并后的列表。
///
/// - `window_ms <= 0` 时仅排序、不合并；
/// - 相同规范化文本且与当前组时间差不超过窗口的，累加到计数并保留最早时间。
pub fn merge(mut danmaku: Vec<Danmaku>, window_ms: i64) -> Vec<Danmaku> {
    danmaku.sort_by(|a, b| {
        a.t.partial_cmp(&b.t)
            .unwrap_or(std::cmp::Ordering::Equal)
            .then(a.text.cmp(&b.text))
    });
    if window_ms <= 0 {
        return danmaku;
    }
    let window = window_ms as f64 / 1000.0;

    // norm -> 输出列表中“开放分组”的下标
    let mut open: HashMap<String, usize> = HashMap::new();
    let mut out: Vec<Danmaku> = Vec::with_capacity(danmaku.len());

    for d in danmaku {
        let key = normalize_text(&d.text);
        if key.is_empty() {
            out.push(d);
            continue;
        }
        if let Some(&idx) = open.get(&key) {
            if d.t - out[idx].t <= window {
                out[idx].count = out[idx].count.saturating_add(1);
                // 开放组的时间锚点用最新一条，允许链式合并连续刷屏。
                continue;
            }
        }
        let idx = out.len();
        out.push(d);
        open.insert(key, idx);
    }
    out
}

/// 规范化：去空白与标点（保留中日韩与字母数字）、小写。
fn normalize_text(text: &str) -> String {
    text.chars()
        .filter(|c| c.is_alphanumeric() || ('\u{4e00}'..='\u{9fff}').contains(c))
        .flat_map(char::to_lowercase)
        .collect()
}

fn unescape_xml(s: &str) -> String {
    // 手写最小实体解码，避免依赖 HTML 实体库（弹幕文本只会出现这几个 + 数字实体）。
    let mut out = String::with_capacity(s.len());
    let bytes = s.as_bytes();
    let mut i = 0usize;
    while i < bytes.len() {
        if bytes[i] == b'&' {
            let rest = &s[i..];
            let candidates = [
                ("&quot;", '"'),
                ("&apos;", '\''),
                ("&lt;", '<'),
                ("&gt;", '>'),
                ("&amp;", '&'),
                ("&nbsp;", ' '),
            ];
            let mut hit = false;
            for (entity, ch) in candidates {
                if rest.starts_with(entity) {
                    out.push(ch);
                    i += entity.len();
                    hit = true;
                    break;
                }
            }
            if hit {
                continue;
            }
            if rest.starts_with("&#") {
                if let Some(end) = rest.find(';') {
                    let code = &rest[2..end];
                    let parsed = code
                        .strip_prefix('x')
                        .or_else(|| code.strip_prefix('X'))
                        .and_then(|h| u32::from_str_radix(h, 16).ok())
                        .or_else(|| code.parse::<u32>().ok());
                    if let Some(cp) = parsed.and_then(char::from_u32) {
                        out.push(cp);
                        i += end + 1;
                        continue;
                    }
                }
            }
        }
        // push 一个字符（注意 UTF-8 边界）
        let ch_len = utf8_char_len(bytes[i]);
        out.push_str(&s[i..i + ch_len.min(s.len() - i)]);
        i += ch_len;
    }
    out
}

fn utf8_char_len(first: u8) -> usize {
    if first < 0x80 {
        1
    } else if first >> 5 == 0b110 {
        2
    } else if first >> 4 == 0b1110 {
        3
    } else {
        4
    }
}

/// 便捷入口：解析 XML 并合并后序列化为 JSON。
pub fn parse_xml_json(body: &str, window_ms: i64) -> String {
    let list = merge(parse_xml(body), window_ms);
    serde_json::to_string(&list).unwrap_or_else(|_| "[]".to_string())
}

/// 便捷入口：解析 seg.so（调用方传入原始字节的 Latin1 透传字符串）并合并后序列化。
///
/// JNI 拿到的是 UTF-16 String；protobuf 是二进制，直接传 String 会破坏字节。
/// 因此 Android 端会先做 base64，本函数也接受 base64 输入。
pub fn parse_seg_so_base64_json(b64: &str, window_ms: i64) -> Result<String, String> {
    let bytes = decode_base64(b64)?;
    let list = merge(parse_seg_so(&bytes), window_ms);
    serde_json::to_string(&list).map_err(|e| e.to_string())
}

/// 极简 base64 解码（标准字母表），避免给核心增加依赖。
fn decode_base64(input: &str) -> Result<Vec<u8>, String> {
    fn val(b: u8) -> Option<u8> {
        match b {
            b'A'..=b'Z' => Some(b - b'A'),
            b'a'..=b'z' => Some(b - b'a' + 26),
            b'0'..=b'9' => Some(b - b'0' + 52),
            b'+' => Some(62),
            b'/' => Some(63),
            _ => None,
        }
    }
    let clean: Vec<u8> = input
        .bytes()
        .filter(|b| !matches!(b, b'\n' | b'\r' | b' ' | b'\t'))
        .collect();
    let mut out = Vec::with_capacity(clean.len() * 3 / 4);
    let mut chunk = 0u32;
    let mut bits = 0u32;
    for b in clean {
        if b == b'=' {
            break;
        }
        let v = val(b).ok_or_else(|| "invalid base64".to_string())?;
        chunk = (chunk << 6) | v as u32;
        bits += 6;
        if bits >= 8 {
            bits -= 8;
            out.push(((chunk >> bits) & 0xFF) as u8);
        }
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_xml_basic() {
        let body = r#"<?xml version="1.0"?><i><d p="23.826,1,25,16777215,1423434321,0,abc,123">哈哈</d>
<d p="24.000,4,25,16711680,1423434321,0,abc,124">红色底部</d></i>"#;
        let list = parse_xml(body);
        assert_eq!(list.len(), 2);
        assert_eq!(list[0].text, "哈哈");
        assert_eq!(list[0].mode, 1);
        assert_eq!(list[1].color, 0xFF0000);
        assert_eq!(list[1].mode, 4);
    }

    #[test]
    fn unescapes_xml_entities() {
        let body = r#"<i><d p="1,1,25,16777215,1,0,a,1">a &amp; b &lt;&gt; &quot;x&quot;</d></i>"#;
        let list = parse_xml(body);
        assert_eq!(list[0].text, "a & b <> \"x\"");
    }

    #[test]
    fn merges_duplicates_in_window() {
        let mk = |t: f64, text: &str| Danmaku {
            t,
            mode: 1,
            color: 0xFFFFFF,
            text: text.to_string(),
            count: 1,
        };
        let input = vec![
            mk(3.0, "哈哈"),
            mk(1.0, "2333"),
            mk(1.5, "2333！！"), // 标点不同，规范化后相同
            mk(12.0, "2333"),   // 超出 10s 窗口，独立一条
        ];
        let out = merge(input, 10_000);
        let count_2333: u32 = out.iter().filter(|d| d.text.starts_with("2333")).map(|d| d.count).sum();
        // 第 1、2 条合并为 count=2，第 4 条独立 → 总计数 3
        assert_eq!(count_2333, 3);
        // 合并后保留最早时间
        let first = out.iter().find(|d| d.text == "2333").unwrap();
        assert_eq!(first.t, 1.0);
        assert_eq!(first.count, 2);
    }

    #[test]
    fn no_merge_when_disabled() {
        let mk = |t: f64| Danmaku {
            t,
            mode: 1,
            color: 0,
            text: "x".into(),
            count: 1,
        };
        let out = merge(vec![mk(1.0), mk(1.2)], 0);
        assert_eq!(out.len(), 2);
    }

    #[test]
    fn parses_protobuf_elems() {
        // 手工构造：top-level field 1 (elem)，elem 内含 progress(2)/mode(3)/color(5)/content(7)
        fn elem(progress: u64, mode: u64, color: u64, text: &str) -> Vec<u8> {
            let mut e = Vec::new();
            put_field_varint(&mut e, 2, progress);
            put_field_varint(&mut e, 3, mode);
            put_field_varint(&mut e, 5, color);
            put_field_string(&mut e, 7, text);
            let mut top = Vec::new();
            put_tag(&mut top, 1, 2);
            put_varint(&mut top, e.len() as u64);
            top.extend_from_slice(&e);
            top
        }
        fn put_tag(out: &mut Vec<u8>, field: u64, wire: u8) {
            put_varint(out, (field << 3) | wire as u64);
        }
        fn put_varint(out: &mut Vec<u8>, mut v: u64) {
            while v >= 0x80 {
                out.push((v as u8) | 0x80);
                v >>= 7;
            }
            out.push(v as u8);
        }
        fn put_field_varint(out: &mut Vec<u8>, field: u64, v: u64) {
            put_tag(out, field, 0);
            put_varint(out, v);
        }
        fn put_field_string(out: &mut Vec<u8>, field: u64, s: &str) {
            put_tag(out, field, 2);
            put_varint(out, s.len() as u64);
            out.extend_from_slice(s.as_bytes());
        }

        let mut body = Vec::new();
        body.extend(elem(12_340, 1, 0xFF_FF_FF, "第一条"));
        body.extend(elem(60_000, 4, 0xFF_00_00, "顶部"));

        let list = parse_seg_so(&body);
        assert_eq!(list.len(), 2);
        assert_eq!(list[0].t, 12.34);
        assert_eq!(list[0].text, "第一条");
        assert_eq!(list[1].mode, 4);
        assert_eq!(list[1].color, 0xFF0000);
    }

    #[test]
    fn base64_roundtrip() {
        // "Man" -> "TWFu"
        assert_eq!(decode_base64("TWFu").unwrap(), b"Man");
        assert_eq!(decode_base64("TWE=").unwrap(), b"Ma");
    }
}
