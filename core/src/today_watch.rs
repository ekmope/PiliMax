//! 「今日推荐单」——基于本地观看历史与首页候选生成个性化队列。
//!
//! 纯计算模块：输入为观看历史与候选视频（由 Android 壳从 B 站接口抓取并序列化为
//! JSON），输出为 `TodayWatchPlan`（含 UP 主榜、视频队列、每条解释与打分）。
//! 无网络、无 TLS，可交叉编译到 arm64-v8a。

use std::collections::{HashMap, HashSet};

use serde::{Deserialize, Serialize};

/// 今日推荐单模式：娱乐 / 学习。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum TodayWatchMode {
    Relax,
    Learn,
}

impl TodayWatchMode {
    pub fn label(self) -> &'static str {
        match self {
            Self::Relax => "娱乐",
            Self::Learn => "学习",
        }
    }
}

/// 推荐策略权重。与 Dart 端 `TodayWatchStrategy` 一一对应。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum TodayWatchStrategy {
    Balanced,
    Affinity,
    Explore,
}

impl TodayWatchStrategy {
    fn weights(self) -> Weights {
        match self {
            Self::Balanced => Weights {
                interest: 0.34,
                mode: 0.20,
                freshness: 0.16,
                quality: 0.15,
                exploration: 0.15,
                diversity: 0.18,
            },
            Self::Affinity => Weights {
                interest: 0.52,
                mode: 0.18,
                freshness: 0.10,
                quality: 0.15,
                exploration: 0.05,
                diversity: 0.08,
            },
            Self::Explore => Weights {
                interest: 0.20,
                mode: 0.18,
                freshness: 0.22,
                quality: 0.15,
                exploration: 0.25,
                diversity: 0.30,
            },
        }
    }
}

struct Weights {
    interest: f64,
    mode: f64,
    freshness: f64,
    quality: f64,
    exploration: f64,
    diversity: f64,
}

/// 观看历史条目（扁平字段，由 Android 壳序列化）。
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct HistoryVideo {
    #[serde(default)]
    pub bvid: String,
    #[serde(default)]
    pub title: String,
    #[serde(default)]
    pub author_mid: i64,
    #[serde(default)]
    pub author_name: String,
    /// 观看时间（Unix 秒）。
    #[serde(default)]
    pub view_at: i64,
    /// 观看进度（秒；-1 表示已看完）。
    #[serde(default)]
    pub progress: i64,
    /// 视频时长（秒）。
    #[serde(default)]
    pub duration: i64,
    #[serde(default)]
    pub tag_name: String,
}

/// 首页候选视频（扁平字段，由 Android 壳序列化）。
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct CandidateVideo {
    #[serde(default)]
    pub bvid: String,
    #[serde(default)]
    pub cid: i64,
    #[serde(default)]
    pub aid: i64,
    #[serde(default)]
    pub cover: String,
    #[serde(default)]
    pub title: String,
    /// 视频时长（秒）。
    #[serde(default)]
    pub duration: i64,
    #[serde(default)]
    pub pubdate: i64,
    #[serde(default)]
    pub goto: String,
    #[serde(default)]
    pub owner_mid: i64,
    #[serde(default)]
    pub owner_name: String,
    #[serde(default)]
    pub owner_face: String,
    #[serde(default)]
    pub stat_view: i64,
    #[serde(default)]
    pub stat_like: i64,
    #[serde(default)]
    pub stat_danmu: i64,
    /// App 副标题 / 分区名（用于话题解析）。
    #[serde(default)]
    pub tname: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct TodayUpRank {
    pub mid: i64,
    pub name: String,
    pub score: f64,
    pub watch_count: i64,
}

#[derive(Debug, Clone, Serialize)]
pub struct TodayWatchPlan {
    pub mode: TodayWatchMode,
    pub up_ranks: Vec<TodayUpRank>,
    pub video_queue: Vec<CandidateVideo>,
    pub explanation_by_bvid: HashMap<String, String>,
    pub score_by_bvid: HashMap<String, f64>,
    pub history_sample_count: usize,
    pub generated_at_ms: i64,
}

#[derive(Debug, Clone)]
struct CreatorAggregate {
    mid: i64,
    name: String,
    score: f64,
    watch_count: i64,
}

#[derive(Debug, Clone)]
struct CandidateFeatures {
    creator_affinity: f64,
    topic_affinity: f64,
    interest: f64,
    mode_fit: f64,
    freshness: f64,
    quality: f64,
    exploration: f64,
    partial_watch_penalty: f64,
    topic_keys: Vec<String>,
}

#[derive(Debug, Clone)]
struct ScoredCandidate {
    video: CandidateVideo,
    original_index: usize,
    base_score: f64,
    features: CandidateFeatures,
    explanation: String,
    final_score: f64,
}

const COMPLETED_WATCH_THRESHOLD: f64 = 0.8;
const TOP_PREVIEW_LIMIT: usize = 6;
const TOP_PREVIEW_REPEAT_LIMIT: i64 = 2;

const RELAX_KEYWORDS: &[&str] = &[
    "音乐", "vlog", "日常", "搞笑", "轻松", "治愈", "asmr", "旅行", "美食", "游戏",
];

const LEARN_KEYWORDS: &[&str] = &[
    "教程", "科普", "知识", "学习", "原理", "实战", "复盘", "编程", "数学", "英语",
    "课程", "技术", "分析", "入门", "进阶",
];

const TOPIC_KEYWORDS: &[(&str, &[&str])] = &[
    ("music", &["音乐", "唱", "歌", "演奏", "翻唱", "live"]),
    (
        "learn",
        &[
            "教程", "科普", "知识", "学习", "原理", "实战", "复盘", "编程", "数学", "英语",
            "课程", "技术", "分析", "入门", "进阶", "kotlin", "android", "flutter",
        ],
    ),
    ("game", &["游戏", "实况", "通关", "原神", "崩坏", "minecraft"]),
    ("food", &["美食", "做饭", "料理", "探店"]),
    ("travel", &["旅行", "旅游", "城市", "徒步", "露营", "vlog"]),
    ("relax", &["日常", "搞笑", "轻松", "治愈", "asmr"]),
];

/// 构建「今日推荐单」。
///
/// 历史归一化后与候选特征统一到 0..1，由策略权重与 MMR 排序。`generated_at_ms` 使用
/// 当前时间（毫秒），由调用方提供以保证可测试性。
pub fn build_today_watch_plan(
    history_videos: &[HistoryVideo],
    candidate_videos: &[CandidateVideo],
    mode: TodayWatchMode,
    strategy: TodayWatchStrategy,
    up_rank_limit: usize,
    queue_limit: usize,
    now_epoch_sec: i64,
) -> TodayWatchPlan {
    let generated_at_ms = now_epoch_sec.saturating_mul(1000);

    let mut cleaned_history: Vec<&HistoryVideo> = history_videos
        .iter()
        .filter(|i| !i.bvid.is_empty())
        .collect();
    cleaned_history.sort_by(|a, b| b.view_at.cmp(&a.view_at));

    // 无历史时无法建立任何兴趣偏好，直接返回空计划（与 Dart 端控制器行为一致）。
    if cleaned_history.is_empty() {
        return TodayWatchPlan {
            mode,
            up_ranks: Vec::new(),
            video_queue: Vec::new(),
            explanation_by_bvid: HashMap::new(),
            score_by_bvid: HashMap::new(),
            history_sample_count: 0,
            generated_at_ms,
        };
    }

    let completion_by_bvid: HashMap<String, f64> = cleaned_history
        .iter()
        .map(|i| (i.bvid.clone(), estimate_completion_ratio(i)))
        .collect();

    let mut recent_creator_scores: HashMap<i64, f64> = HashMap::new();
    let mut recent_creator_counts: HashMap<i64, i64> = HashMap::new();
    let mut creator_names: HashMap<i64, String> = HashMap::new();
    let mut raw_topic_scores: HashMap<String, f64> = HashMap::new();

    for item in &cleaned_history {
        let completion = estimate_completion_ratio(item);
        let affinity = watch_affinity_score(completion, recency_bonus(item.view_at, now_epoch_sec));
        let mid = item.author_mid;
        if mid > 0 {
            *recent_creator_scores.entry(mid).or_insert(0.0) += affinity;
            *recent_creator_counts.entry(mid).or_insert(0) += 1;
            let name = item.author_name.trim();
            creator_names.entry(mid).or_insert_with(|| {
                if name.is_empty() {
                    format!("UP主{}", mid)
                } else {
                    name.to_string()
                }
            });
        }
        for topic in resolve_topic_keys(&item.title, &item.tag_name) {
            *raw_topic_scores.entry(topic).or_insert(0.0) += affinity;
        }
    }

    let creator_affinity = normalize_positive_scores(&recent_creator_scores);
    let topic_affinity = normalize_positive_scores(&raw_topic_scores);

    let creators: Vec<CreatorAggregate> = creator_affinity
        .iter()
        .map(|(mid, score)| CreatorAggregate {
            mid: *mid,
            name: creator_names
                .get(mid)
                .cloned()
                .unwrap_or_else(|| format!("UP主{}", mid)),
            score: *score,
            watch_count: recent_creator_counts.get(mid).copied().unwrap_or(0).max(1),
        })
        .collect();

    let mut eligible_candidates: Vec<CandidateVideo> = candidate_videos
        .iter()
        .filter(|v| {
            !v.bvid.is_empty() && !v.title.trim().is_empty() && v.goto == "av"
        })
        .filter(|v| {
            completion_by_bvid.get(&v.bvid).copied().unwrap_or(0.0)
                < COMPLETED_WATCH_THRESHOLD
        })
        .cloned()
        .collect();

    // 按 bvid 去重，保留首次出现。
    let mut seen: HashSet<String> = HashSet::new();
    eligible_candidates.retain(|v| seen.insert(v.bvid.clone()));

    let quality_by_bvid = build_candidate_quality_scores(&eligible_candidates);
    let weights = strategy.weights();

    let mut scored_candidates: Vec<ScoredCandidate> = Vec::with_capacity(eligible_candidates.len());
    for (index, video) in eligible_candidates.iter().enumerate() {
        let topics = resolve_topic_keys(&video.title, &video.tname);
        let creator_score = creator_affinity.get(&video.owner_mid).copied().unwrap_or(0.0);
        let topic_score = if topics.is_empty() {
            0.0
        } else {
            topics
                .iter()
                .map(|t| topic_affinity.get(t).copied().unwrap_or(0.0))
                .fold(0.0f64, f64::max)
        };

        let features = CandidateFeatures {
            creator_affinity: creator_score,
            topic_affinity: topic_score,
            interest: (creator_score * 0.65 + topic_score * 0.35).clamp(0.0, 1.0),
            mode_fit: mode_fit_score(video, mode),
            freshness: continuous_freshness_score(video.pubdate, now_epoch_sec),
            quality: quality_by_bvid.get(&video.bvid).copied().unwrap_or(0.5),
            exploration: exploration_score(creator_score, topic_score, &topics),
            partial_watch_penalty: (completion_by_bvid
                .get(&video.bvid)
                .copied()
                .unwrap_or(0.0)
                * 0.4)
                .clamp(0.0, 0.4),
            topic_keys: topics,
        };

        let score = (features.interest * weights.interest
            + features.mode_fit * weights.mode
            + features.freshness * weights.freshness
            + features.quality * weights.quality
            + features.exploration * weights.exploration
            - features.partial_watch_penalty)
            .clamp(0.0, 1.0);

        scored_candidates.push(ScoredCandidate {
            video: video.clone(),
            original_index: index,
            base_score: score,
            final_score: score,
            explanation: build_explanation(video, mode, &features),
            features,
        });
    }

    // 稳定排序：按分数降序，分数相同时按原始顺序。
    scored_candidates.sort_by(|a, b| {
        b.base_score
            .partial_cmp(&a.base_score)
            .unwrap_or(std::cmp::Ordering::Equal)
            .then(a.original_index.cmp(&b.original_index))
    });

    let queue_limit = queue_limit.clamp(1, 60);
    let selected_indices = build_diverse_queue(&mut scored_candidates, queue_limit, weights.diversity);

    let video_queue: Vec<CandidateVideo> = selected_indices
        .iter()
        .map(|&i| scored_candidates[i].video.clone())
        .collect();

    let explanation_by_bvid: HashMap<String, String> = selected_indices
        .iter()
        .map(|&i| {
            (
                scored_candidates[i].video.bvid.clone(),
                scored_candidates[i].explanation.clone(),
            )
        })
        .collect();

    let score_by_bvid: HashMap<String, f64> = selected_indices
        .iter()
        .map(|&i| {
            (
                scored_candidates[i].video.bvid.clone(),
                scored_candidates[i].final_score,
            )
        })
        .collect();

    TodayWatchPlan {
        mode,
        up_ranks: build_up_ranks(&creators, up_rank_limit.clamp(1, 20)),
        video_queue,
        explanation_by_bvid,
        score_by_bvid,
        history_sample_count: cleaned_history.len(),
        generated_at_ms,
    }
}

/// 便捷入口：解析 JSON 输入并返回 JSON 输出。
pub fn build_today_watch_plan_json(
    history_json: &str,
    candidates_json: &str,
    mode: TodayWatchMode,
    strategy: TodayWatchStrategy,
    up_rank_limit: usize,
    queue_limit: usize,
    now_epoch_sec: i64,
) -> Result<String, String> {
    let history: Vec<HistoryVideo> =
        serde_json::from_str(history_json).map_err(|e| format!("history: {}", e))?;
    let candidates: Vec<CandidateVideo> =
        serde_json::from_str(candidates_json).map_err(|e| format!("candidates: {}", e))?;
    let plan = build_today_watch_plan(
        &history,
        &candidates,
        mode,
        strategy,
        up_rank_limit,
        queue_limit,
        now_epoch_sec,
    );
    serde_json::to_string(&plan).map_err(|e| e.to_string())
}

fn build_up_ranks(creators: &[CreatorAggregate], limit: usize) -> Vec<TodayUpRank> {
    let mut sorted = creators.to_vec();
    sorted.sort_by(|a, b| {
        b.score
            .partial_cmp(&a.score)
            .unwrap_or(std::cmp::Ordering::Equal)
            .then(b.watch_count.cmp(&a.watch_count))
    });
    sorted
        .into_iter()
        .take(limit)
        .map(|e| TodayUpRank {
            mid: e.mid,
            name: e.name,
            score: e.score,
            watch_count: e.watch_count,
        })
        .collect()
}

fn normalize_positive_scores<K>(scores: &HashMap<K, f64>) -> HashMap<K, f64>
where
    K: Clone + Eq + std::hash::Hash,
{
    if scores.is_empty() {
        return HashMap::new();
    }
    let max = scores.values().copied().fold(0.0f64, f64::max);
    if max <= 0.0 {
        return HashMap::new();
    }
    scores
        .iter()
        .map(|(k, v)| (k.clone(), (v / max).clamp(0.0, 1.0)))
        .collect()
}

fn build_candidate_quality_scores(candidates: &[CandidateVideo]) -> HashMap<String, f64> {
    if candidates.is_empty() {
        return HashMap::new();
    }
    let mut view_metrics: Vec<f64> = candidates
        .iter()
        .map(|v| ((v.stat_view as f64).max(0.0) + 1.0).ln())
        .collect();
    view_metrics.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));

    let mut engagement_metrics: Vec<f64> =
        candidates.iter().map(smoothed_engagement_rate).collect();
    engagement_metrics.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));

    candidates
        .iter()
        .map(|v| {
            let view_value = ((v.stat_view as f64).max(0.0) + 1.0).ln();
            let score = (percentile_rank(&view_metrics, view_value) * 0.6
                + percentile_rank(&engagement_metrics, smoothed_engagement_rate(v)) * 0.4)
                .clamp(0.0, 1.0);
            (v.bvid.clone(), score)
        })
        .collect()
}

fn smoothed_engagement_rate(video: &CandidateVideo) -> f64 {
    let weighted_engagement = video.stat_like as f64 + (video.stat_danmu as f64) * 2.0;
    (weighted_engagement / ((video.stat_view as f64).max(0.0) + 2000.0)).clamp(0.0, 1.0)
}

fn percentile_rank(sorted_values: &[f64], value: f64) -> f64 {
    if sorted_values.len() <= 1 {
        return 0.5;
    }
    let less_or_equal = sorted_values.iter().filter(|v| **v <= value).count();
    ((less_or_equal as f64 - 1.0) / (sorted_values.len() as f64 - 1.0)).clamp(0.0, 1.0)
}

/// MMR 多样化选择：返回被选中的候选在 `candidates` 中的下标（按选择顺序）。
/// 同时就地更新被选候选的 `final_score`。
fn build_diverse_queue(
    candidates: &mut [ScoredCandidate],
    queue_limit: usize,
    diversity_strength: f64,
) -> Vec<usize> {
    if candidates.is_empty() {
        return Vec::new();
    }
    let mut remaining: Vec<usize> = (0..candidates.len()).collect();
    let mut selected_indices: Vec<usize> = Vec::new();
    let mut creator_counts: HashMap<i64, i64> = HashMap::new();
    let mut topic_counts: HashMap<String, i64> = HashMap::new();

    while selected_indices.len() < queue_limit && !remaining.is_empty() {
        let pool: Vec<usize> = if selected_indices.len() < TOP_PREVIEW_LIMIT {
            let capped: Vec<usize> = remaining
                .iter()
                .copied()
                .filter(|&idx| {
                    let c = &candidates[idx];
                    let mid = c.video.owner_mid;
                    let creator_allowed =
                        mid <= 0 || creator_counts.get(&mid).copied().unwrap_or(0) < TOP_PREVIEW_REPEAT_LIMIT;
                    let primary_topic = c.features.topic_keys.first();
                    let topic_allowed = primary_topic.map_or(true, |t| {
                        topic_counts.get(t).copied().unwrap_or(0) < TOP_PREVIEW_REPEAT_LIMIT
                    });
                    creator_allowed && topic_allowed
                })
                .collect();
            if capped.is_empty() {
                remaining.clone()
            } else {
                capped
            }
        } else {
            remaining.clone()
        };

        let mut picked: Option<usize> = None;
        let mut picked_score: f64 = -1.0;
        for &idx in &pool {
            let adjusted = candidates[idx].base_score
                - diversity_strength * maximum_similarity(&candidates[idx], candidates, &selected_indices);
            if adjusted > picked_score {
                picked_score = adjusted;
                picked = Some(idx);
            }
        }

        let Some(picked) = picked else { break };
        candidates[picked].final_score = picked_score.clamp(0.0, 1.0);

        selected_indices.push(picked);
        remaining.retain(|&i| i != picked);

        let picked_mid = candidates[picked].video.owner_mid;
        if picked_mid > 0 {
            *creator_counts.entry(picked_mid).or_insert(0) += 1;
        }
        if let Some(topic) = candidates[picked].features.topic_keys.first() {
            *topic_counts.entry(topic.clone()).or_insert(0) += 1;
        }
    }

    selected_indices
}

fn maximum_similarity(
    candidate: &ScoredCandidate,
    all: &[ScoredCandidate],
    selected_indices: &[usize],
) -> f64 {
    let mut max = 0.0;
    for &idx in selected_indices {
        let existing = &all[idx];
        let same_creator = candidate.video.owner_mid > 0
            && candidate.video.owner_mid == existing.video.owner_mid;
        let topic_overlap = candidate
            .features
            .topic_keys
            .iter()
            .any(|t| existing.features.topic_keys.contains(t));
        let sim = (if same_creator { 0.6 } else { 0.0 }) + (if topic_overlap { 0.4 } else { 0.0 });
        if sim > max {
            max = sim;
        }
    }
    max
}

fn build_explanation(
    video: &CandidateVideo,
    mode: TodayWatchMode,
    features: &CandidateFeatures,
) -> String {
    let _ = video;
    let mut reasons: Vec<&str> = Vec::new();
    if features.mode_fit >= 0.7 {
        reasons.push(match mode {
            TodayWatchMode::Relax => "轻松向",
            TodayWatchMode::Learn => "学习向",
        });
    }
    if features.freshness >= 0.75 {
        reasons.push("近期更新");
    }
    if features.creator_affinity >= 0.45 {
        reasons.push("常看UP");
    }
    if features.topic_affinity >= 0.45 {
        reasons.push("常看分区");
    }
    if features.exploration >= 0.8 {
        reasons.push("新UP探索");
    }
    if features.quality >= 0.75 {
        reasons.push("优质内容");
    }
    if reasons.is_empty() {
        reasons.push(match mode {
            TodayWatchMode::Relax => "轻松向",
            TodayWatchMode::Learn => "学习向",
        });
    }
    reasons.into_iter().take(3).collect::<Vec<_>>().join(" · ")
}

fn mode_fit_score(video: &CandidateVideo, mode: TodayWatchMode) -> f64 {
    let title = video.title.to_lowercase();
    let duration_min = video.duration as f64 / 60.0;
    let view = video.stat_view;
    let intensity = if view > 0 {
        video.stat_danmu as f64 / view as f64
    } else {
        video.stat_danmu as f64
    };
    let relax_cue = RELAX_KEYWORDS.iter().any(|k| title.contains(k));
    let learn_cue = LEARN_KEYWORDS.iter().any(|k| title.contains(k));

    match mode {
        TodayWatchMode::Relax => {
            let duration_fit: f64 = if duration_min < 2.0 {
                0.3
            } else if duration_min <= 12.0 {
                1.0
            } else if duration_min <= 20.0 {
                0.75
            } else if duration_min <= 35.0 {
                0.45
            } else {
                0.15
            };
            let calm_fit: f64 = if intensity < 0.004 {
                1.0
            } else if intensity < 0.01 {
                0.65
            } else {
                0.2
            };
            (duration_fit * 0.45
                + calm_fit * 0.25
                + if relax_cue { 0.30 } else { 0.12 }
                - if learn_cue { 0.22 } else { 0.0 })
            .clamp(0.0, 1.0)
        }
        TodayWatchMode::Learn => {
            let duration_fit: f64 = if duration_min < 5.0 {
                0.2
            } else if duration_min < 10.0 {
                0.55
            } else if duration_min <= 35.0 {
                1.0
            } else if duration_min <= 55.0 {
                0.7
            } else {
                0.35
            };
            (duration_fit * 0.55
                + if learn_cue { 0.45 } else { 0.12 }
                - if relax_cue && duration_min < 12.0 {
                    0.2
                } else {
                    0.0
                })
            .clamp(0.0, 1.0)
        }
    }
}

fn continuous_freshness_score(pubdate: i64, now_epoch_sec: i64) -> f64 {
    if pubdate <= 0 {
        return 0.5;
    }
    let age_days = (now_epoch_sec - pubdate) as f64 / 86400.0;
    2f64.powf(-age_days / 30.0).clamp(0.0, 1.0)
}

fn exploration_score(creator_affinity: f64, topic_affinity: f64, topics: &[String]) -> f64 {
    let unseen_creator = if creator_affinity < 0.05 { 1.0 } else { 0.0 };
    let unseen_topic = if topics.is_empty() || topic_affinity < 0.05 {
        1.0
    } else {
        0.0
    };
    unseen_creator * 0.6 + unseen_topic * 0.4
}

fn resolve_topic_keys(title: &str, tname: &str) -> Vec<String> {
    let mut keys: Vec<String> = Vec::new();
    let t = tname.trim().to_lowercase();
    if !t.is_empty() {
        keys.push(format!("partition:{}", t));
    }
    let searchable = format!("{} {}", title, tname).to_lowercase();
    for (key, kws) in TOPIC_KEYWORDS {
        if kws.iter().any(|k| searchable.contains(k)) {
            keys.push(format!("topic:{}", key));
        }
    }
    keys
}

fn estimate_completion_ratio(item: &HistoryVideo) -> f64 {
    let progress = item.progress as f64;
    let duration = item.duration as f64;
    // 历史接口用 -1 表示已看完。
    if item.progress == -1 {
        return 1.0;
    }
    if item.progress < 0 {
        return 0.35;
    }
    if duration <= 0.0 {
        return (progress / 600.0).clamp(0.0, 1.0);
    }
    (progress / duration).clamp(0.0, 1.0)
}

fn watch_affinity_score(completion: f64, recency_bonus: f64) -> f64 {
    let completion_score = if completion >= 0.9 {
        1.85
    } else if completion >= 0.6 {
        0.9 + completion * 0.75
    } else if completion >= 0.3 {
        0.25 + completion * 0.45
    } else {
        0.1
    };
    completion_score + recency_bonus * (if completion >= 0.6 { 1.0 } else { 0.35 })
}

fn recency_bonus(view_at: i64, now_epoch_sec: i64) -> f64 {
    if view_at <= 0 {
        return 0.25;
    }
    let days = (now_epoch_sec - view_at) as f64 / 86400.0;
    if days <= 1.0 {
        1.0
    } else if days <= 3.0 {
        0.8
    } else if days <= 7.0 {
        0.6
    } else if days <= 30.0 {
        0.35
    } else {
        0.15
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn history(bvid: &str, mid: i64, name: &str, view_at: i64, progress: i64, duration: i64, title: &str) -> HistoryVideo {
        HistoryVideo {
            bvid: bvid.to_string(),
            title: title.to_string(),
            author_mid: mid,
            author_name: name.to_string(),
            view_at,
            progress,
            duration,
            tag_name: String::new(),
        }
    }

    fn candidate(bvid: &str, title: &str, mid: i64, duration: i64, pubdate: i64) -> CandidateVideo {
        CandidateVideo {
            bvid: bvid.to_string(),
            cid: 0,
            aid: 0,
            cover: String::new(),
            title: title.to_string(),
            duration,
            pubdate,
            goto: "av".to_string(),
            owner_mid: mid,
            owner_name: String::new(),
            owner_face: String::new(),
            stat_view: 10000,
            stat_like: 500,
            stat_danmu: 100,
            tname: String::new(),
        }
    }

    #[test]
    fn computes_a_plan() {
        let history = [
            history("BV1x1", 10, "UP甲", 1_700_000_000, 300, 300, "开心每一天 vlog"),
            history("BV1x2", 11, "UP乙", 1_690_000_000, -1, 600, "Rust 编程入门教程"),
        ];
        let candidates = [
            candidate("BV1c1", "一首好听的翻唱", 11, 180, 1_700_000_000),
            candidate("BV1c2", "Python 实战教程", 12, 900, 1_699_000_000),
            candidate("BV1c3", "旅行 vlog", 13, 240, 1_700_000_000),
        ];
        let plan = build_today_watch_plan(
            &history,
            &candidates,
            TodayWatchMode::Relax,
            TodayWatchStrategy::Balanced,
            5,
            20,
            1_700_000_000,
        );
        assert_eq!(plan.history_sample_count, 2);
        assert!(!plan.video_queue.is_empty());
        assert!(!plan.up_ranks.is_empty());
        assert_eq!(plan.video_queue.len(), plan.score_by_bvid.len());
    }

    #[test]
    fn empty_history_yields_empty_queue() {
        let candidates = [candidate("BV1c1", "教程", 1, 600, 1_700_000_000)];
        let plan = build_today_watch_plan(
            &[],
            &candidates,
            TodayWatchMode::Learn,
            TodayWatchStrategy::Balanced,
            5,
            20,
            1_700_000_000,
        );
        assert!(plan.video_queue.is_empty());
        assert!(plan.up_ranks.is_empty());
    }

    #[test]
    fn json_roundtrip() {
        let history_json = r#"[{"bvid":"BV1x1","title":"开心","author_mid":10,"author_name":"UP甲","view_at":1700000000,"progress":300,"duration":300}]"#;
        let candidates_json = r#"[{"bvid":"BV1c1","title":"一首翻唱","duration":180,"pubdate":1700000000,"goto":"av","owner_mid":11,"stat_view":10000,"stat_like":500,"stat_danmu":100}]"#;
        let out = build_today_watch_plan_json(
            history_json,
            candidates_json,
            TodayWatchMode::Relax,
            TodayWatchStrategy::Balanced,
            5,
            20,
            1_700_000_000,
        )
        .expect("json io");
        let parsed: serde_json::Value = serde_json::from_str(&out).expect("valid json");
        assert!(parsed["video_queue"].is_array());
    }
}