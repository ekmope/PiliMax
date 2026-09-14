import 'dart:math' as math;

import 'package:PiliPlus/models/home/rcmd/result.dart';
import 'package:PiliPlus/models/model_rec_video_item.dart';
import 'package:PiliPlus/models_new/history/list.dart';

/// 今日推荐单模式：娱乐 / 学习
enum TodayWatchMode {
  relax('娱乐'),
  learn('学习');

  final String label;
  const TodayWatchMode(this.label);
}

/// 推荐策略权重
enum TodayWatchStrategy {
  balanced(
    interest: 0.34,
    mode: 0.20,
    freshness: 0.16,
    quality: 0.15,
    exploration: 0.15,
    diversity: 0.18,
  ),
  affinity(
    interest: 0.52,
    mode: 0.18,
    freshness: 0.10,
    quality: 0.15,
    exploration: 0.05,
    diversity: 0.08,
  ),
  explore(
    interest: 0.20,
    mode: 0.18,
    freshness: 0.22,
    quality: 0.15,
    exploration: 0.25,
    diversity: 0.30,
  );

  final double interest;
  final double mode;
  final double freshness;
  final double quality;
  final double exploration;
  final double diversity;

  const TodayWatchStrategy({
    required this.interest,
    required this.mode,
    required this.freshness,
    required this.quality,
    required this.exploration,
    required this.diversity,
  });
}

class TodayUpRank {
  final int mid;
  final String name;
  final double score;
  final int watchCount;

  const TodayUpRank(this.mid, this.name, this.score, this.watchCount);
}

class TodayWatchPlan {
  final TodayWatchMode mode;
  final List<TodayUpRank> upRanks;
  final List<BaseRcmdVideoItemModel> videoQueue;
  final Map<String, String> explanationByBvid;
  final Map<String, double> scoreByBvid;
  final int historySampleCount;
  final int generatedAt;

  const TodayWatchPlan({
    required this.mode,
    required this.upRanks,
    required this.videoQueue,
    required this.explanationByBvid,
    required this.scoreByBvid,
    required this.historySampleCount,
    required this.generatedAt,
  });
}

class _CreatorAggregate {
  final int mid;
  final String name;
  final double score;
  final int watchCount;

  const _CreatorAggregate(this.mid, this.name, this.score, this.watchCount);
}

class _CandidateFeatures {
  final double creatorAffinity;
  final double topicAffinity;
  final double interest;
  final double modeFit;
  final double freshness;
  final double quality;
  final double exploration;
  final double partialWatchPenalty;
  final Set<String> topicKeys;

  const _CandidateFeatures({
    required this.creatorAffinity,
    required this.topicAffinity,
    required this.interest,
    required this.modeFit,
    required this.freshness,
    required this.quality,
    required this.exploration,
    required this.partialWatchPenalty,
    required this.topicKeys,
  });
}

class _ScoredCandidate {
  final BaseRcmdVideoItemModel video;
  final int originalIndex;
  final double baseScore;
  final double confidence;
  final _CandidateFeatures features;
  final String explanation;
  double finalScore;

  _ScoredCandidate({
    required this.video,
    required this.originalIndex,
    required this.baseScore,
    required this.confidence,
    required this.features,
    required this.explanation,
  }) : finalScore = baseScore;
}

const double _completedWatchThreshold = 0.8;
const int _topPreviewLimit = 6;
const int _topPreviewRepeatLimit = 2;

/// 基于本地观看历史与首页候选生成「今日推荐单」。
/// 历史归一化后与候选特征统一到 0..1，由策略权重与 MMR 排序。
TodayWatchPlan buildTodayWatchPlan({
  required List<HistoryItemModel> historyVideos,
  required List<BaseRcmdVideoItemModel> candidateVideos,
  required TodayWatchMode mode,
  int upRankLimit = 5,
  int queueLimit = 20,
  TodayWatchStrategy strategy = TodayWatchStrategy.balanced,
}) {
  final nowEpochSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;

  final cleanedHistory = historyVideos
      .where((i) => (i.history.bvid ?? '').isNotEmpty)
      .toList()
    ..sort((a, b) => (b.viewAt ?? 0).compareTo(a.viewAt ?? 0));

  final completionByBvid = <String, double>{
    for (final i in cleanedHistory) i.history.bvid!: _estimateCompletionRatio(i),
  };

  final recentCreatorScores = <int, double>{};
  final recentCreatorCounts = <int, int>{};
  final creatorNames = <int, String>{};
  final rawTopicScores = <String, double>{};

  for (final item in cleanedHistory) {
    final completion = _estimateCompletionRatio(item);
    final affinity = _watchAffinityScore(
      completion,
      _recencyBonus(item.viewAt ?? 0, nowEpochSec),
    );
    final mid = item.authorMid ?? 0;
    if (mid > 0) {
      recentCreatorScores[mid] = (recentCreatorScores[mid] ?? 0) + affinity;
      recentCreatorCounts[mid] = (recentCreatorCounts[mid] ?? 0) + 1;
      final name = (item.authorName ?? '').trim();
      creatorNames[mid] = name.isEmpty ? 'UP主$mid' : name;
    }
    for (final topic in _resolveTopicKeys(
      item.title ?? '',
      item.tagName ?? '',
    )) {
      rawTopicScores[topic] = (rawTopicScores[topic] ?? 0) + affinity;
    }
  }

  final normalizedRecentCreators = _normalizePositiveScores(recentCreatorScores);
  final creatorAffinity = Map.of(normalizedRecentCreators);
  final topicAffinity = _normalizePositiveScores(rawTopicScores);

  final creators = creatorAffinity.entries
      .map(
        (e) => _CreatorAggregate(
          e.key,
          creatorNames[e.key] ?? 'UP主${e.key}',
          e.value,
          math.max(recentCreatorCounts[e.key] ?? 0, 1),
        ),
      )
      .toList();

  final eligibleCandidates = candidateVideos
      .where(
        (v) =>
            (v.bvid ?? '').isNotEmpty && v.title.trim().isNotEmpty && v.goto == 'av',
      )
      .where((v) => (completionByBvid[v.bvid!] ?? 0) < _completedWatchThreshold)
      .fold<List<BaseRcmdVideoItemModel>>([], (list, v) {
        if (!list.any((e) => e.bvid == v.bvid)) {
          list.add(v);
        }
        return list;
      });

  final qualityByBvid = _buildCandidateQualityScores(eligibleCandidates);
  final weights = strategy;

  final scoredCandidates = <_ScoredCandidate>[];
  for (final (index, video) in eligibleCandidates.indexed) {
    final topics = _resolveTopicKeys(
      video.title,
      video is RcmdVideoItemAppModel ? (video.tname ?? '') : '',
    );
    final creatorScore = creatorAffinity[video.owner.mid ?? 0] ?? 0.0;
    final topicScore = topics.isEmpty
        ? 0.0
        : topics
              .map((t) => topicAffinity[t] ?? 0.0)
              .reduce((a, b) => math.max(a, b));

    final features = _CandidateFeatures(
      creatorAffinity: creatorScore,
      topicAffinity: topicScore,
      interest: (creatorScore * 0.65 + topicScore * 0.35).clamp(0.0, 1.0),
      modeFit: _modeFitScore(video, mode),
      freshness: _continuousFreshnessScore(video.pubdate ?? 0, nowEpochSec),
      quality: qualityByBvid[video.bvid] ?? 0.5,
      exploration: _explorationScore(creatorScore, topicScore, topics),
      partialWatchPenalty:
          ((completionByBvid[video.bvid!] ?? 0) * 0.4).clamp(0.0, 0.4),
      topicKeys: topics,
    );

    final score = (features.interest * weights.interest +
            features.modeFit * weights.mode +
            features.freshness * weights.freshness +
            features.quality * weights.quality +
            features.exploration * weights.exploration -
            features.partialWatchPenalty)
        .clamp(0.0, 1.0);

    scoredCandidates.add(
      _ScoredCandidate(
        video: video,
        originalIndex: index,
        baseScore: score,
        confidence: score,
        features: features,
        explanation: _buildExplanation(video, mode, features),
      ),
    );
  }
  scoredCandidates.sort(
    (a, b) => b.baseScore != a.baseScore
        ? b.baseScore.compareTo(a.baseScore)
        : a.originalIndex.compareTo(b.originalIndex),
  );

  final selected = _buildDiverseQueue(
    scoredCandidates,
    queueLimit.clamp(1, 60),
    weights.diversity,
  );

  return TodayWatchPlan(
    mode: mode,
    upRanks: _buildUpRanks(creators, upRankLimit.clamp(1, 20)),
    videoQueue: selected.map((e) => e.video).toList(),
    explanationByBvid: {
      for (final e in selected) e.video.bvid!: e.explanation,
    },
    scoreByBvid: {
      for (final e in selected) e.video.bvid!: e.finalScore,
    },
    historySampleCount: cleanedHistory.length,
    generatedAt: DateTime.now().millisecondsSinceEpoch,
  );
}

List<TodayUpRank> _buildUpRanks(
  List<_CreatorAggregate> creators,
  int limit,
) {
  final sorted = [...creators]..sort((a, b) {
      if (b.score != a.score) return b.score.compareTo(a.score);
      return b.watchCount.compareTo(a.watchCount);
    });
  return sorted
      .take(limit)
      .map((e) => TodayUpRank(e.mid, e.name, e.score, e.watchCount))
      .toList();
}

Map<K, double> _normalizePositiveScores<K>(Map<K, double> scores) {
  if (scores.isEmpty) return {};
  final max = scores.values.reduce(math.max);
  if (max <= 0) return {};
  return {
    for (final e in scores.entries) e.key: (e.value / max).clamp(0.0, 1.0),
  };
}

Map<String, double> _buildCandidateQualityScores(
  List<BaseRcmdVideoItemModel> candidates,
) {
  if (candidates.isEmpty) return {};
  final viewMetrics = candidates
      .map((v) => math.log((v.stat.view ?? 0) + 1.0))
      .toList()
    ..sort();
  final engagementMetrics = candidates.map(_smoothedEngagementRate).toList()
    ..sort();
  return {
    for (final v in candidates)
      v.bvid!: (_percentileRank(viewMetrics, math.log((v.stat.view ?? 0) + 1.0)) *
              0.6 +
          _percentileRank(engagementMetrics, _smoothedEngagementRate(v)) * 0.4)
          .clamp(0.0, 1.0),
  };
}

double _smoothedEngagementRate(BaseRcmdVideoItemModel video) {
  final weightedEngagement = (video.stat.like ?? 0).toDouble() +
      (video.stat.danmu ?? 0) * 2.0;
  return (weightedEngagement / ((video.stat.view ?? 0) + 2000.0)).clamp(0.0, 1.0);
}

double _percentileRank(List<double> sortedValues, double value) {
  if (sortedValues.length <= 1) return 0.5;
  final lessOrEqual = sortedValues.where((v) => v <= value).length;
  return ((lessOrEqual - 1) / (sortedValues.length - 1)).clamp(0.0, 1.0);
}

List<_ScoredCandidate> _buildDiverseQueue(
  List<_ScoredCandidate> candidates,
  int queueLimit,
  double diversityStrength,
) {
  if (candidates.isEmpty) return [];
  final remaining = [...candidates];
  final selected = <_ScoredCandidate>[];
  final creatorCounts = <int, int>{};
  final topicCounts = <String, int>{};

  while (selected.length < queueLimit && remaining.isNotEmpty) {
    List<_ScoredCandidate> pool = remaining;
    if (selected.length < _topPreviewLimit) {
      final capped = remaining.where((c) {
        final mid = c.video.owner.mid ?? 0;
        final creatorAllowed = mid <= 0 ||
            (creatorCounts[mid] ?? 0) < _topPreviewRepeatLimit;
        final primaryTopic = c.features.topicKeys.isEmpty
            ? null
            : c.features.topicKeys.first;
        final topicAllowed = primaryTopic == null ||
            (topicCounts[primaryTopic] ?? 0) < _topPreviewRepeatLimit;
        return creatorAllowed && topicAllowed;
      }).toList();
      if (capped.isNotEmpty) pool = capped;
    }

    _ScoredCandidate? picked;
    double pickedScore = -1;
    for (final c in pool) {
      final adjusted = c.baseScore - diversityStrength * _maximumSimilarity(c, selected);
      if (adjusted > pickedScore) {
        pickedScore = adjusted;
        picked = c;
      }
    }
    if (picked == null) break;

    picked.finalScore = pickedScore.clamp(0.0, 1.0);
    selected.add(picked);
    remaining.remove(picked);

    final mid = picked.video.owner.mid ?? 0;
    if (mid > 0) {
      creatorCounts[mid] = (creatorCounts[mid] ?? 0) + 1;
    }
    if (picked.features.topicKeys.isNotEmpty) {
      final topic = picked.features.topicKeys.first;
      topicCounts[topic] = (topicCounts[topic] ?? 0) + 1;
    }
  }
  return selected;
}

double _maximumSimilarity(
  _ScoredCandidate candidate,
  List<_ScoredCandidate> selected,
) {
  double max = 0;
  for (final existing in selected) {
    final sameCreator =
        (candidate.video.owner.mid ?? 0) > 0 &&
            candidate.video.owner.mid == existing.video.owner.mid;
    final topicOverlap = candidate.features.topicKeys
        .intersection(existing.features.topicKeys)
        .isNotEmpty;
    final sim = (sameCreator ? 0.6 : 0.0) + (topicOverlap ? 0.4 : 0.0);
    if (sim > max) max = sim;
  }
  return max;
}

String _buildExplanation(
  BaseRcmdVideoItemModel video,
  TodayWatchMode mode,
  _CandidateFeatures features,
) {
  final reasons = <String>[];
  if (features.modeFit >= 0.7) reasons.add(mode == TodayWatchMode.relax ? '轻松向' : '学习向');
  if (features.freshness >= 0.75) reasons.add('近期更新');
  if (features.creatorAffinity >= 0.45) reasons.add('常看UP');
  if (features.topicAffinity >= 0.45) reasons.add('常看分区');
  if (features.exploration >= 0.8) reasons.add('新UP探索');
  if (features.quality >= 0.75) reasons.add('优质内容');
  if (reasons.isEmpty) {
    reasons.add(mode == TodayWatchMode.relax ? '轻松向' : '学习向');
  }
  return reasons.take(3).join(' · ');
}

double _modeFitScore(BaseRcmdVideoItemModel video, TodayWatchMode mode) {
  final title = video.title.toLowerCase();
  final durationMin = video.duration / 60.0;
  final view = video.stat.view ?? 0;
  final intensity = (video.stat.danmu ?? 0) / (view > 0 ? view : 1);
  final relaxCue = _relaxKeywords.any(title.contains);
  final learnCue = _learnKeywords.any(title.contains);

  double base;
  switch (mode) {
    case TodayWatchMode.relax:
      final durationFit = durationMin < 2
          ? 0.3
          : durationMin <= 12
          ? 1.0
          : durationMin <= 20
          ? 0.75
          : durationMin <= 35
          ? 0.45
          : 0.15;
      final calmFit = intensity < 0.004
          ? 1.0
          : intensity < 0.01
          ? 0.65
          : 0.2;
      base = (durationFit * 0.45 +
              calmFit * 0.25 +
              (relaxCue ? 0.30 : 0.12) -
              (learnCue ? 0.22 : 0.0))
          .clamp(0.0, 1.0);
    case TodayWatchMode.learn:
      final durationFit = durationMin < 5
          ? 0.2
          : durationMin < 10
          ? 0.55
          : durationMin <= 35
          ? 1.0
          : durationMin <= 55
          ? 0.7
          : 0.35;
      base = (durationFit * 0.55 +
              (learnCue ? 0.45 : 0.12) -
              (relaxCue && durationMin < 12 ? 0.2 : 0.0))
          .clamp(0.0, 1.0);
  }
  return base;
}

double _continuousFreshnessScore(int pubdate, int nowEpochSec) {
  if (pubdate <= 0) return 0.5;
  final ageDays = (nowEpochSec - pubdate) / 86400.0;
  return math.pow(2, -ageDays / 30.0).clamp(0.0, 1.0).toDouble();
}

double _explorationScore(
  double creatorAffinity,
  double topicAffinity,
  Set<String> topics,
) {
  final unseenCreator = creatorAffinity < 0.05 ? 1.0 : 0.0;
  final unseenTopic = topics.isEmpty || topicAffinity < 0.05 ? 1.0 : 0.0;
  return unseenCreator * 0.6 + unseenTopic * 0.4;
}

Set<String> _resolveTopicKeys(String title, String tname) {
  final keys = <String>{};
  final t = tname.trim().toLowerCase();
  if (t.isNotEmpty) keys.add('partition:$t');
  final searchable = '$title $tname'.toLowerCase();
  for (final e in _topicKeywords.entries) {
    if (e.value.any(searchable.contains)) {
      keys.add('topic:${e.key}');
    }
  }
  return keys;
}

double _estimateCompletionRatio(HistoryItemModel item) {
  final progress = item.progress ?? 0;
  final duration = item.duration ?? 0;
  // 历史接口用 -1 表示已看完（见 HistoryItemModel.playbackProgress 注释）
  if (progress == -1) return 1.0;
  if (progress < 0) return 0.35;
  if (duration <= 0) return (progress / 600).clamp(0.0, 1.0);
  return (progress / duration).clamp(0.0, 1.0);
}

double _watchAffinityScore(double completion, double recencyBonus) {
  final completionScore = completion >= 0.9
      ? 1.85
      : completion >= 0.6
      ? 0.9 + completion * 0.75
      : completion >= 0.3
      ? 0.25 + completion * 0.45
      : 0.1;
  return completionScore +
      recencyBonus * (completion >= 0.6 ? 1.0 : 0.35);
}

double _recencyBonus(int viewAt, int nowEpochSec) {
  if (viewAt <= 0) return 0.25;
  final days = (nowEpochSec - viewAt) / 86400.0;
  return days <= 1
      ? 1.0
      : days <= 3
      ? 0.8
      : days <= 7
      ? 0.6
      : days <= 30
      ? 0.35
      : 0.15;
}

const List<String> _relaxKeywords = [
  '音乐', 'vlog', '日常', '搞笑', '轻松', '治愈', 'asmr', '旅行', '美食', '游戏',
];

const List<String> _learnKeywords = [
  '教程', '科普', '知识', '学习', '原理', '实战', '复盘', '编程', '数学', '英语',
  '课程', '技术', '分析', '入门', '进阶',
];

const Map<String, List<String>> _topicKeywords = {
  'music': ['音乐', '唱', '歌', '演奏', '翻唱', 'live'],
  'learn': [
    '教程', '科普', '知识', '学习', '原理', '实战', '复盘', '编程', '数学', '英语',
    '课程', '技术', '分析', '入门', '进阶', 'kotlin', 'android', 'flutter',
  ],
  'game': ['游戏', '实况', '通关', '原神', '崩坏', 'minecraft'],
  'food': ['美食', '做饭', '料理', '探店'],
  'travel': ['旅行', '旅游', '城市', '徒步', '露营', 'vlog'],
  'relax': ['日常', '搞笑', '轻松', '治愈', 'asmr'],
};
