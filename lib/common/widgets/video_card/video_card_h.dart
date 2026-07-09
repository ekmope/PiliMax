import 'package:PiliMax/common/style.dart';
import 'package:PiliMax/common/widgets/badge.dart';
import 'package:PiliMax/common/widgets/image/image_save.dart';
import 'package:PiliMax/common/widgets/image/network_img_layer.dart';
import 'package:PiliMax/common/widgets/progress_bar/video_progress_indicator.dart';
import 'package:PiliMax/common/widgets/stat/stat.dart';
import 'package:PiliMax/common/widgets/video_card/video_cover_hero.dart';
import 'package:PiliMax/common/widgets/video_card/watch_later_button.dart';
import 'package:PiliMax/common/widgets/video_popup_menu.dart';
import 'package:PiliMax/http/search.dart';
import 'package:PiliMax/models/horizontal_video_model.dart';
import 'package:PiliMax/models_new/video/video_detail/dimension.dart';
import 'package:PiliMax/utils/date_utils.dart';
import 'package:PiliMax/utils/duration_utils.dart';
import 'package:PiliMax/utils/page_utils.dart';
import 'package:PiliMax/utils/platform_utils.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

// 视频卡片 - 水平布局
class VideoCardH extends StatefulWidget {
  static final RxSet<String> clickedBvids = <String>{}.obs;

  const VideoCardH({
    super.key,
    required this.videoItem,
    this.onTap,
    this.onTapWithHeroTag,
    this.onViewLater,
    this.onRemove,
    this.heroTag,
  });
  final HorizontalVideoModel videoItem;
  final VoidCallback? onTap;
  final ValueChanged<String>? onTapWithHeroTag;
  final ValueChanged<int>? onViewLater;
  final VoidCallback? onRemove;
  final String? heroTag;

  @override
  State<VideoCardH> createState() => _VideoCardHState();
}

class _VideoCardHState extends State<VideoCardH> {
  bool _isHovering = false;
  String? _cachedHeroTag;

  HorizontalVideoModel get videoItem => widget.videoItem;
  Object? get _heroKey => videoItem.bvid ?? videoItem.aid ?? videoItem.cid;
  String get _heroTag =>
      widget.heroTag ??
      _cachedHeroTag ??=
          'video-card-h-$_heroKey-${identityHashCode(this)}';
  VoidCallback? get onTap => widget.onTap;
  ValueChanged<String>? get onTapWithHeroTag => widget.onTapWithHeroTag;
  VoidCallback? get onRemove => widget.onRemove;

  @override
  void didUpdateWidget(covariant VideoCardH oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldItem = oldWidget.videoItem;
    final oldKey = oldItem.bvid ?? oldItem.aid ?? oldItem.cid;
    if (oldKey != _heroKey || oldWidget.heroTag != widget.heroTag) {
      _cachedHeroTag = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    void onLongPress() => imageSaveDialog(
      bvid: videoItem.bvid,
      title: videoItem.title,
      cover: videoItem.cover,
      pubdate: videoItem.pubdate,
      view: videoItem.stat.view,
      danmaku: videoItem.stat.danmu,
      like: videoItem.stat.like,
      favorite: videoItem.stat.favorite,
      ownerName: videoItem.owner.name,
    );
    final theme = Theme.of(context);

    Future<void> onPushDetail() async {
      if (videoItem.isPugv ?? false) {
        PageUtils.viewPugv(
          seasonId: videoItem.seasonId,
          heroTag: _heroTag,
        );
        return;
      }

      if (videoItem.isLive ?? false) {
        if (videoItem.roomId case final roomId?) {
          PageUtils.toLiveRoom(roomId);
        }
        return;
      }

      if (videoItem.redirectUrl?.isNotEmpty == true &&
          PageUtils.viewPgcFromUri(
            videoItem.redirectUrl!,
            heroTag: _heroTag,
          )) {
        return;
      }

      int? cid = videoItem.cid;
      Dimension? dimension = videoItem.dimension;
      if (cid == null) {
        if (await SearchHttp.ab2cWithDimension(
              aid: videoItem.aid,
              bvid: videoItem.bvid,
            )
            case final res?) {
          cid = res.cid;
          dimension = res.dimension;
        }
      }
      if (cid != null) {
        PageUtils.toVideoPage(
          bvid: videoItem.bvid,
          cid: cid,
          cover: videoItem.cover,
          title: videoItem.title,
          dimension: dimension,
          heroTag: _heroTag,
        );
        final String? key = videoItem.bvid ?? videoItem.aid?.toString();
        if (key != null && key.isNotEmpty) {
          VideoCardH.clickedBvids.add(key);
        }
      }
    }

    return Material(
      type: .transparency,
      child: MouseRegion(
        onEnter: PlatformUtils.isMobile
            ? null
            : (_) => setState(() => _isHovering = true),
        onExit: PlatformUtils.isMobile
            ? null
            : (_) => setState(() => _isHovering = false),
        child: Stack(
          clipBehavior: .none,
          children: [
            InkWell(
              onLongPress: onLongPress,
              onSecondaryTap: PlatformUtils.isMobile ? null : onLongPress,
              onTap: onTapWithHeroTag != null
                  ? () => onTapWithHeroTag!(_heroTag)
                  : onTap ?? onPushDetail,
              child: Padding(
                padding: const .symmetric(
                  horizontal: Style.safeSpace,
                  vertical: 5,
                ),
                child: Row(
                  crossAxisAlignment: .start,
                  children: [
                    AspectRatio(
                      aspectRatio: Style.aspectRatio,
                      child: LayoutBuilder(
                        builder: (context, boxConstraints) {
                          final double maxWidth = boxConstraints.maxWidth;
                          final double maxHeight = boxConstraints.maxHeight;

                          final progress = videoItem.progress;

                          return Stack(
                            clipBehavior: .none,
                            children: [
                              VideoCoverHero(
                                tag: _heroTag,
                                child: NetworkImgLayer(
                                  src: videoItem.cover,
                                  width: maxWidth,
                                  height: maxHeight,
                                ),
                              ),
                              if (videoItem.badge case final badge?)
                                PBadge(
                                  text: badge,
                                  top: 6.0,
                                  right: 6.0,
                                  type: switch (badge) {
                                    '充电专属' => .error,
                                    _ => .primary,
                                  },
                                ),
                              if (progress != null && progress != 0) ...[
                                PBadge(
                                  text: progress == -1
                                      ? '已看完'
                                      : '${DurationUtils.formatDuration(progress)}/${DurationUtils.formatDuration(videoItem.duration)}',
                                  right: 6,
                                  bottom: 8,
                                  type: .gray,
                                ),
                                Positioned(
                                  left: 0,
                                  bottom: 0,
                                  right: 0,
                                  child: VideoProgressIndicator(
                                    color: theme.colorScheme.primary,
                                    backgroundColor:
                                        theme.colorScheme.secondaryContainer,
                                    progress: progress == -1
                                        ? 1
                                        : progress / videoItem.duration,
                                  ),
                                ),
                              ] else if (videoItem.duration > 0)
                                PBadge(
                                  text: DurationUtils.formatDuration(
                                    videoItem.duration,
                                  ),
                                  right: 6.0,
                                  bottom: 6.0,
                                  type: .gray,
                                ),
                              if (!PlatformUtils.isMobile &&
                                  videoItem.bvid != null)
                                Positioned(
                                  top: 4,
                                  right: 4,
                                  child: Visibility(
                                    visible: _isHovering,
                                    maintainState: true,
                                    child: QuickWatchLaterButton(
                                      target: WatchLaterTarget.from(
                                        bvid: videoItem.bvid,
                                        aid: videoItem.aid,
                                        fallback: videoItem,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    content(theme),
                  ],
                ),
              ),
            ),
            Positioned(
              bottom: -5.5,
              right: 0,
              width: VideoPopupMenu.defaultTapTargetSize,
              height: VideoPopupMenu.defaultTapTargetSize,
              child: VideoPopupMenu(
                iconSize: 17,
                videoItem: videoItem,
                onRemove: onRemove,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget content(ThemeData theme) {
    String pubdate = DateFormatUtils.dateFormat(videoItem.pubdate!);
    if (pubdate != '') pubdate += '  ';
    return Expanded(
      child: Column(
        crossAxisAlignment: .start,
        children: [
          if (videoItem.titleList?.isNotEmpty == true)
            Expanded(
              child: Obx(() {
                final key = videoItem.bvid ?? videoItem.aid?.toString();
                final isClicked =
                    key != null && VideoCardH.clickedBvids.contains(key);
                return Text.rich(
                  overflow: .ellipsis,
                  maxLines: 2,
                  TextSpan(
                    children: videoItem.titleList!
                        .map(
                          (e) => TextSpan(
                            text: e.text,
                            style: TextStyle(
                              fontSize: theme.textTheme.bodyMedium!.fontSize,
                              height: 1.42,
                              letterSpacing: 0.3,
                              color: isClicked
                                  ? theme.colorScheme.outline
                                  : e.isEm
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurface,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                );
              }),
            )
          else
            Expanded(
              child: Obx(() {
                final key = videoItem.bvid ?? videoItem.aid?.toString();
                final isClicked =
                    key != null && VideoCardH.clickedBvids.contains(key);
                return Text(
                  videoItem.title,
                  textAlign: .start,
                  style: TextStyle(
                    fontSize: theme.textTheme.bodyMedium!.fontSize,
                    height: 1.42,
                    letterSpacing: 0.3,
                    color: isClicked ? theme.colorScheme.outline : null,
                  ),
                  maxLines: 2,
                  overflow: .ellipsis,
                );
              }),
            ),
          Text(
            "$pubdate${videoItem.owner.name}",
            maxLines: 1,
            style: TextStyle(
              fontSize: 12,
              height: 1,
              color: theme.colorScheme.outline,
              overflow: .clip,
            ),
          ),
          const SizedBox(height: 3),
          Row(
            spacing: 8,
            children: [
              StatWidget(type: .play, value: videoItem.stat.view),
              StatWidget(type: .danmaku, value: videoItem.stat.danmu),
            ],
          ),
        ],
      ),
    );
  }
}
