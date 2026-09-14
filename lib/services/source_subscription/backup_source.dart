import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

import 'package:PiliPlus/models_new/pgc/pgc_info_model/episode.dart';
import 'package:PiliPlus/models_new/pgc/pgc_info_model/result.dart';
import 'package:PiliPlus/pages/core_video/controller.dart';
import 'package:PiliPlus/player_core/core_player.dart';
import 'package:PiliPlus/services/source_subscription/models.dart';
import 'package:PiliPlus/services/source_subscription/selector_engine.dart';
import 'package:PiliPlus/services/source_subscription/store.dart';
import 'package:PiliPlus/services/source_subscription/video_sniffer.dart';

/// animeko 风格的「备用源」服务：按番剧标题在订阅源中搜索匹配条目，
/// 嗅探出对应剧集的直链，然后切换 PiliPlus 的三内核播放器播放。
class BackupSourceService {
  BackupSourceService._();

  /// 把匹配结果抽象为（源实例，番剧条目，匹配剧集）。
  static Future<List<BackupEpisodeCandidate>> search({
    required String title,
    required int? seasonNumber,
    int maxPerInstance = 5,
  }) async {
    final kw = title.trim();
    if (kw.isEmpty) return const [];
    final instances = SourceSubscriptionStore.instance.enabledInstances
        .where((i) => i.factoryId == 'web-selector')
        .toList();
    if (instances.isEmpty) return const [];

    final out = <BackupEpisodeCandidate>[];
    final perInstance = await Future.wait(
      instances.map(
        (inst) => _searchOne(inst, kw, seasonNumber, maxPerInstance),
      ),
    );
    for (final list in perInstance) {
      out.addAll(list);
    }
    return out;
  }

  static Future<List<BackupEpisodeCandidate>> _searchOne(
    SourceInstance inst,
    String keyword,
    int? seasonNumber,
    int maxPerInstance,
  ) async {
    try {
      final engine = SelectorEngine(inst);
      final subjects = await engine.search(keyword);
      final list = <BackupEpisodeCandidate>[];
      for (final s in subjects.take(maxPerInstance)) {
        try {
          final channels = await engine.fetchChannels(s.url);
          for (final ch in channels) {
            for (final ep in ch.episodes) {
              list.add(
                BackupEpisodeCandidate(
                  instance: inst,
                  subject: s,
                  channel: ch,
                  episode: ep,
                ),
              );
            }
          }
        } catch (_) {
          continue;
        }
      }
      return list;
    } catch (_) {
      return const [];
    }
  }

  /// 嗅探匹配剧的直链并跳转到三内核播放页。
  static Future<bool> playEpisode(BackupEpisodeCandidate cand) async {
    final engine = SelectorEngine(cand.instance);
    final headers = engine.videoHeaders;
    SmartDialog.showLoading(msg: '备用源解析中…');
    String? url;
    try {
      final html = await engine.fetchPageHtml(cand.episode.pageUrl);
      if (html != null && engine.matchVideoUrl case final pattern?) {
        final m = RegExp(pattern).firstMatch(html);
        if (m != null) url = m.group(0) ?? m.group(1);
      }
      url ??= await VideoUrlSniffer.sniff(
        pageUrl: cand.episode.pageUrl,
        matchVideoUrl: engine.matchVideoUrl,
        matchNestedUrl: engine.matchNestedUrl,
        headers: headers,
      );
    } finally {
      SmartDialog.dismiss(status: SmartStatus.loading);
    }
    if (url == null) {
      SmartDialog.showToast('备用源解析失败');
      return false;
    }
    Get.put(
      CoreVideoController(
        source: CoreMediaSource(videoUrl: url, headers: headers),
        title:
            '${cand.episode.name} · ${cand.subject.name} · ${cand.channel.name}',
      ),
    );
    Get.to(() => const CoreVideoPage());
    return true;
  }
}

class BackupEpisodeCandidate {
  final SourceInstance instance;
  final SourceSubject subject;
  final SourceChannel channel;
  final SourceEpisode episode;

  const BackupEpisodeCandidate({
    required this.instance,
    required this.subject,
    required this.channel,
    required this.episode,
  });
}

/// 番剧介绍页：附带的 animeko 风格"该番剧订阅源"入口。
/// 标题相同时优先显示当前 episode 的 sort（集数）匹配。
class BackupSourceLauncher {
  BackupSourceLauncher._();

  static Future<void> launchForPgc({
    required PgcInfoModel pgcItem,
    EpisodeItem? episode,
  }) async {
    final title = pgcItem.title.trim();
    if (title.isEmpty) return;
    final seasonNumber = episode?.showTitle == null
        ? null
        : int.tryParse(RegExp(r'(\d+)').firstMatch(episode!.showTitle!)?.group(1) ?? '');

    SmartDialog.showLoading(msg: '正在跨源搜索「$title」…');
    final candidates = await BackupSourceService.search(
      title: title,
      seasonNumber: seasonNumber,
    );
    SmartDialog.dismiss(status: SmartStatus.loading);
    if (candidates.isEmpty) {
      SmartDialog.showToast('订阅源中未找到「$title」');
      return;
    }
    _showSheet(pgcItem, episode, candidates);
  }

  static void _showSheet(
    PgcInfoModel pgcItem,
    EpisodeItem? episode,
    List<BackupEpisodeCandidate> candidates,
  ) {
    final ctx = Get.context;
    if (ctx == null) return;
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.85,
        builder: (_, scrollCtr) {
          // 按源分组
          final groups = <SourceInstance, List<BackupEpisodeCandidate>>{};
          for (final c in candidates) {
            groups.putIfAbsent(c.instance, () => []).add(c);
          }
          return ListView(
            controller: scrollCtr,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '${pgcItem.title} 的备用源（${candidates.length} 个候选）',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              for (final entry in groups.entries) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text(
                    entry.key.name,
                    style: TextStyle(
                      color: Get.theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                for (final c in entry.value.take(6))
                  ListTile(
                    dense: true,
                    title: Text(
                      '${c.channel.name} · ${c.episode.sort}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      c.episode.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: const Icon(Icons.play_circle_outline),
                    onTap: () async {
                      Get.back();
                      await BackupSourceService.playEpisode(c);
                    },
                  ),
              ],
              const SizedBox(height: 16),
            ],
          );
        },
      ),
    );
  }
}