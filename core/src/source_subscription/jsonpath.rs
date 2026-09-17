//! 最小 JSONPath 实现。
//!
//! 仅支持 animeko `SelectorSubjectFormatJsonPathIndexed` 实际使用到的语法子集：
//! - `$` 开头；
//! - `.key` 命名字段；
//! - `[*]` 数组全体；
//! - `['a', 'b']` 多键并集（也支持双引号）。
//!
//! 解析结果为一个扁平的 JSON 值列表；多键并集在数组上下文中展开。

use serde_json::Value;

#[derive(Debug, Clone, PartialEq, Eq)]
enum Seg {
    Key(String),
    AnyIndex,
    Union(Vec<String>),
}

/// 已编译的 JSONPath。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct JsonPath {
    segs: Vec<Seg>,
}

/// 编译 JSONPath 表达式；语法不支持时返回 `None`。
pub fn compile(expr: &str) -> Option<JsonPath> {
    let body = expr.strip_prefix('$')?;
    let chars: Vec<char> = body.chars().collect();
    let mut i = 0;
    let mut segs: Vec<Seg> = Vec::new();

    while i < chars.len() {
        if chars[i] == '.' {
            i += 1;
            let start = i;
            while i < chars.len() && chars[i] != '.' && chars[i] != '[' {
                i += 1;
            }
            let key: String = chars[start..i].iter().collect();
            if key.is_empty() {
                return None;
            }
            segs.push(Seg::Key(key));
        } else if chars[i] == '[' {
            let start = i;
            i += 1;
            while i < chars.len() && chars[i] != ']' {
                i += 1;
            }
            if i >= chars.len() {
                return None;
            }
            let inner: String = chars[start + 1..i].iter().collect();
            i += 1;
            let t = inner.trim();
            if t == "*" {
                segs.push(Seg::AnyIndex);
            } else {
                // 取出引号内的键（'a' 或 "a"）。
                let mut keys: Vec<String> = Vec::new();
                let mut k = 0;
                let tc: Vec<char> = t.chars().collect();
                while k < tc.len() {
                    let quote = tc[k];
                    if quote == '\'' || quote == '"' {
                        k += 1;
                        let s = k;
                        while k < tc.len() && tc[k] != quote {
                            k += 1;
                        }
                        if k >= tc.len() {
                            return None;
                        }
                        keys.push(tc[s..k].iter().collect());
                        k += 1;
                    } else {
                        k += 1;
                    }
                }
                if keys.is_empty() {
                    return None;
                }
                segs.push(Seg::Union(keys));
            }
        } else {
            return None;
        }
    }

    Some(JsonPath { segs })
}

/// 按已编译的路径解析，返回所有命中的值（保持顺序）。
pub fn resolve<'a>(root: &'a Value, path: &JsonPath) -> Vec<&'a Value> {
    let mut current: Vec<&Value> = vec![root];
    for seg in &path.segs {
        let mut next: Vec<&Value> = Vec::new();
        for v in &current {
            match seg {
                Seg::Key(k) => {
                    if let Some(x) = v.get(k) {
                        next.push(x);
                    }
                }
                Seg::AnyIndex => {
                    if let Some(arr) = v.as_array() {
                        for x in arr {
                            next.push(x);
                        }
                    }
                }
                Seg::Union(keys) => {
                    if let Some(obj) = v.as_object() {
                        for k in keys {
                            if let Some(x) = obj.get(k) {
                                next.push(x);
                            }
                        }
                    }
                }
            }
        }
        current = next;
    }
    current
}
