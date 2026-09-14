import 'package:PiliPlus/pages/common/common_controller.dart';
import 'package:PiliPlus/pages/core_video/controller.dart';
import 'package:PiliPlus/player_core/core_player.dart';
import 'package:PiliPlus/services/source_subscription/models.dart';
import 'package:PiliPlus/services/source_subscription/selector_engine.dart';
import 'package:PiliPlus/services/source_subscription/store.dart';
import 'package:PiliPlus/services/source_subscription/video_sniffer.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// 订阅源搜索页：跨所有启用源搜索 → 条目 → 线路/集数 → 播放。
class SourceSearchController extends GetxController
    with ScrollOrRefreshMixin {
  @override
  final scrollController = ScrollController();

  @override
  Future<void> onRefresh() async {
    if (keyword.value.isNotEmpty) {
      await search(keyword.value);
    }
  }
  final RxList<(SourceInstance, List<SourceSubject>)> results =
      <(SourceInstance, List<SourceSubject>)>[].obs;
  final RxBool searching = false.obs;
  final keyword = ''.obs;

  final RxMap<String, List<SourceChannel>> channelCache =
      <String, List<SourceChannel>>{}.obs;
  final RxString loadingChannels = ''.obs;

  Future<void> search(String kw) async {
    keyword.value = kw.trim();
    if (keyword.value.isEmpty) return;
    final instances = SourceSubscriptionStore.instance.enabledInstances
        .where((i) => i.factoryId == 'web-selector')
        .toList();
    if (instances.isEmpty) {
      SmartDialog.showToast('没有可用的数据源，先在设置-源订阅中添加');
      return;
    }
    searching.value = true;
    results.value = [];
    try {
      final all = await Future.wait(
        instances.map((inst) async {
          final engine = SelectorEngine(inst);
          final subjects = await engine.search(keyword.value);
          return (inst, subjects);
        }),
      );
      results.value = all.where((e) => e.$2.isNotEmpty).toList();
      if (results.isEmpty) {
        SmartDialog.showToast('没有找到相关内容');
      }
    } finally {
      searching.value = false;
    }
  }

  Future<List<SourceChannel>> loadChannels(
    SourceInstance instance,
    SourceSubject subject,
  ) async {
    final key = '${instance.instanceId}:${subject.url}';
    if (channelCache[key] case final cached?) return cached;
    loadingChannels.value = subject.url;
    try {
      final channels = await SelectorEngine(instance).fetchChannels(
        subject.url,
      );
      channelCache[key] = channels;
      return channels;
    } finally {
      loadingChannels.value = '';
    }
  }

  @override
  void onClose() {
    scrollController.dispose();
    super.onClose();
  }

  /// 嗅探剧集直链并进入三内核播放页。
  Future<void> playEpisode(
    SourceInstance instance,
    SourceChannel channel,
    SourceEpisode episode,
  ) async {
    final engine = SelectorEngine(instance);
    final headers = engine.videoHeaders;

    SmartDialog.showLoading(msg: '正在解析播放地址…');
    String? url;
    try {
      // 先尝试页面源码正则直接匹配，失败再走 WebView 嗅探
      final html = await engine.fetchPageHtml(episode.pageUrl);
      if (html != null && engine.matchVideoUrl case final pattern?) {
        final m = RegExp(pattern).firstMatch(html);
        if (m != null) {
          url = m.group(0) ?? m.group(1);
        }
      }
      url ??= await VideoUrlSniffer.sniff(
        pageUrl: episode.pageUrl,
        matchVideoUrl: engine.matchVideoUrl,
        matchNestedUrl: engine.matchNestedUrl,
        headers: headers,
      );
    } finally {
      SmartDialog.dismiss(status: SmartStatus.loading);
    }

    if (url == null) {
      SmartDialog.showToast('未能解析出播放地址');
      return;
    }

    Get.put(
      CoreVideoController(
        source: CoreMediaSource(videoUrl: url, headers: headers),
        title: '${episode.name} · ${channel.name}',
      ),
    );
    Get.to(() => const CoreVideoPage());
  }
}

class SourceSearchPage extends StatefulWidget {
  const SourceSearchPage({super.key});

  @override
  State<SourceSearchPage> createState() => _SourceSearchPageState();
}

class _SourceSearchPageState extends State<SourceSearchPage> {
  final controller = Get.put(SourceSearchController());
  final editController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: editController,
          textInputAction: TextInputAction.search,
          onSubmitted: controller.search,
          decoration: const InputDecoration(
            hintText: '搜索订阅源内容…',
            border: InputBorder.none,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => controller.search(editController.text),
          ),
          IconButton(
            tooltip: '源订阅设置',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Get.toNamed('/sourceSubscription'),
          ),
        ],
      ),
      body: Obx(() {
        if (controller.searching.value) {
          return const Center(child: CircularProgressIndicator());
        }
        if (controller.results.isEmpty) {
          return _buildEmpty(colorScheme);
        }
        return ListView(
          controller: controller.scrollController,
          children: [
            for (final (instance, subjects) in controller.results) ...[
              Padding(
                padding: const .only(left: 16, top: 12, bottom: 4),
                child: Text(
                  instance.name,
                  style: TextStyle(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              for (final subject in subjects)
                ListTile(
                  leading: const Icon(Icons.play_circle_outline),
                  title: Text(
                    subject.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    Uri.tryParse(subject.url)?.host ?? subject.url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                  onTap: () => _showEpisodes(instance, subject),
                ),
              const Divider(height: 1),
            ],
          ],
        );
      }),
    );
  }

  Widget _buildEmpty(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: .center,
        children: [
          Icon(Icons.subscriptions_outlined, size: 56, color: colorScheme.outline),
          const SizedBox(height: 16),
          const Text('搜索订阅源中的影视内容'),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Get.toNamed('/sourceSubscription'),
            child: const Text('先去添加源订阅 →'),
          ),
        ],
      ),
    );
  }

  void _showEpisodes(SourceInstance instance, SourceSubject subject) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (context, scrollController) => FutureBuilder(
          future: controller.loadChannels(instance, subject),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final channels = snapshot.data!;
            if (channels.isEmpty) {
              return const Center(child: Text('未解析到播放线路'));
            }
            return ListView(
              controller: scrollController,
              children: [
                Padding(
                  padding: const .all(16),
                  child: Text(
                    subject.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                for (final channel in channels) ...[
                  Padding(
                    padding: const .only(left: 16, top: 8, bottom: 4),
                    child: Text(
                      '${channel.name}（${channel.episodes.length}）',
                      style: TextStyle(
                        color: ColorScheme.of(context).primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final episode in channel.episodes)
                        ActionChip(
                          label: Text(episode.sort),
                          onPressed: () {
                            Get.back();
                            controller.playEpisode(instance, channel, episode);
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
