import 'dart:async';

import 'package:PiliMax/common/assets.dart';
import 'package:PiliMax/models_new/video/video_detail/data.dart';
import 'package:PiliMax/models_new/video/video_detail/episode.dart';
import 'package:PiliMax/pages/video/controller.dart';
import 'package:PiliMax/pages/video/introduction/ugc/controller.dart';
import 'package:PiliMax/pilimax/pages/video/video_layout_metrics.dart';
import 'package:PiliMax/utils/extension/num_ext.dart';
import 'package:material_ui/material_ui.dart';
import 'package:get/get.dart';

// TODO refa
class SeasonPanel extends StatefulWidget {
  const SeasonPanel({
    super.key,
    required this.heroTag,
    required this.showEpisodes,
    this.canTap = true,
    required this.ugcIntroController,
  });
  final String heroTag;
  final Function showEpisodes;
  final bool canTap;
  final UgcIntroController ugcIntroController;

  @override
  State<SeasonPanel> createState() => _SeasonPanelState();
}

class _SeasonPanelState extends State<SeasonPanel> {
  RxInt currentIndex = 0.obs;
  late VideoDetailController _videoDetailController;
  StreamSubscription? _listener;
  List<EpisodeItem> episodes = <EpisodeItem>[];
  int? _pendingSeasonIndex;

  UgcIntroController get ugcIntroController => widget.ugcIntroController;
  VideoDetailData get videoDetail =>
      widget.ugcIntroController.videoDetail.value;

  @override
  void initState() {
    super.initState();
    _videoDetailController = Get.find<VideoDetailController>(
      tag: widget.heroTag,
    );

    _videoDetailController.seasonCid = ugcSeasonPanelInitialCid(
      videoDetail,
      ugcIntroController.cid.value,
    );

    /// 根据 cid 找到对应集，找到对应 episodes
    /// 有多个episodes时，只显示其中一个
    _findEpisode();
    if (episodes.isEmpty) {
      return;
    }

    /// 取对应 season_id 的 episodes
    _updateCurrentIndex();
    _listener = _videoDetailController.cid.listen((int cid) {
      if (_videoDetailController.seasonCid != cid) {
        bool isPart =
            videoDetail.pages?.indexWhere((item) => item.cid == cid) != -1;
        if (!isPart) {
          _videoDetailController.seasonCid = cid;
        }
      }
      _findEpisode();
      if (episodes.isNotEmpty) {
        _updateCurrentIndex();
      }
    });
  }

  @override
  void dispose() {
    _listener?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (episodes.isEmpty) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(
        top: VideoDetailLayoutMetrics.seasonPanelTopPadding,
        left: VideoDetailLayoutMetrics.seasonPanelHorizontalInset,
        right: VideoDetailLayoutMetrics.seasonPanelHorizontalInset,
      ),
      child: Material(
        color: theme.colorScheme.onInverseSurface,
        borderRadius: const BorderRadius.all(
          Radius.circular(VideoDetailLayoutMetrics.seasonPanelRadius),
        ),
        child: InkWell(
          borderRadius: const BorderRadius.all(
            Radius.circular(VideoDetailLayoutMetrics.seasonPanelRadius),
          ),
          onTap: widget.canTap
              ? () => widget.showEpisodes(
                  _videoDetailController.seasonIndex.value,
                  videoDetail.ugcSeason,
                  null,
                  _videoDetailController.bvid,
                  null,
                  _videoDetailController.seasonCid,
                )
              : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal:
                  VideoDetailLayoutMetrics.seasonPanelContentHorizontalPadding,
              vertical:
                  VideoDetailLayoutMetrics.seasonPanelContentVerticalPadding,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '合集：${videoDetail.ugcSeason!.title!}',
                    style: theme.textTheme.labelMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(
                  width: VideoDetailLayoutMetrics.seasonPanelLeadingGap,
                ),
                Image.asset(
                  Assets.livingStatic,
                  color: theme.colorScheme.primary,
                  height: VideoDetailLayoutMetrics.seasonPanelStatusIconExtent,
                  cacheHeight: VideoDetailLayoutMetrics
                      .seasonPanelStatusIconExtent
                      .cacheSize(context),
                  semanticLabel: "正在播放：",
                ),
                const SizedBox(
                  width: VideoDetailLayoutMetrics.seasonPanelStatusGap,
                ),
                Obx(
                  () => Text(
                    '${currentIndex.value + 1}/${episodes.length}',
                    style: theme.textTheme.labelMedium,
                    semanticsLabel:
                        '第${currentIndex.value + 1}集，共${episodes.length}集',
                  ),
                ),
                const SizedBox(
                  width: VideoDetailLayoutMetrics.seasonPanelArrowGap,
                ),
                const Icon(
                  Icons.arrow_forward_ios_outlined,
                  size: VideoDetailLayoutMetrics.seasonPanelArrowExtent,
                  semanticLabel: '查看',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _findEpisode() {
    final selection = resolveUgcSeasonPanel(
      videoDetail,
      _videoDetailController.seasonCid,
    );
    if (selection == null) {
      episodes = <EpisodeItem>[];
      return;
    }
    episodes = selection.episodes;
    _syncSeasonIndex(selection.sectionIndex);
  }

  void _updateCurrentIndex() {
    final int index = episodes.indexWhere(
      (EpisodeItem e) => e.cid == _videoDetailController.seasonCid,
    );
    currentIndex.value = index < 0 ? 0 : index;
  }

  void _syncSeasonIndex(int index) {
    if (_videoDetailController.seasonIndex.value == index) {
      _pendingSeasonIndex = null;
      return;
    }
    _pendingSeasonIndex = index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _pendingSeasonIndex != index) {
        return;
      }
      _pendingSeasonIndex = null;
      if (_videoDetailController.seasonIndex.value != index) {
        _videoDetailController.seasonIndex.value = index;
      }
    });
  }
}
