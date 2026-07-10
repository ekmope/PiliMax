import 'package:PiliMax/common/style.dart';
import 'package:PiliMax/common/widgets/badge.dart';
import 'package:PiliMax/common/widgets/image/image_save.dart';
import 'package:PiliMax/common/widgets/image/network_img_layer.dart';
import 'package:PiliMax/common/widgets/stat/stat.dart';
import 'package:PiliMax/common/widgets/video_card/video_cover_hero.dart';
import 'package:PiliMax/common/widgets/video_card/watch_later_button.dart';
import 'package:PiliMax/common/widgets/video_popup_menu.dart';
import 'package:PiliMax/http/search.dart';
import 'package:PiliMax/models/common/stat_type.dart';
import 'package:PiliMax/models/home/rcmd/result.dart';
import 'package:PiliMax/models/model_rec_video_item.dart';
import 'package:PiliMax/models_new/video/video_detail/dimension.dart';
import 'package:PiliMax/utils/app_scheme.dart';
import 'package:PiliMax/utils/date_utils.dart';
import 'package:PiliMax/utils/duration_utils.dart';
import 'package:PiliMax/utils/extension/dimension_ext.dart';
import 'package:PiliMax/utils/id_utils.dart';
import 'package:PiliMax/utils/page_utils.dart';
import 'package:PiliMax/utils/platform_utils.dart';
import 'package:PiliMax/utils/storage_pref.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:intl/intl.dart';

// 视频卡片 - 垂直布局
class VideoCardV extends StatefulWidget {
  final BaseRcmdVideoItemModel videoItem;
  final VoidCallback? onRemove;
  final String? heroTag;
  static final _pubdateTextPattern = RegExp(
    r'刚刚|昨天|今天|前|\d{1,4}[-/.年]\d{1,2}|周[一二三四五六日天]',
  );
  static final shortFormat = DateFormat('M-d');
  static final longFormat = DateFormat('yy-M-d');

  const VideoCardV({
    super.key,
    required this.videoItem,
    this.onRemove,
    this.heroTag,
  });

  @override
  State<VideoCardV> createState() => _VideoCardVState();
}

class _VideoCardVState extends State<VideoCardV> {
  bool _isHovering = false;
  String? _cachedHeroTag;

  BaseRcmdVideoItemModel get videoItem => widget.videoItem;
  Object? get _heroKey => videoItem.bvid ?? videoItem.aid ?? videoItem.cid;
  Object? get _widgetHeroKey {
    final key = widget.key;
    return key is ValueKey<Object?> ? key.value : key;
  }

  Object? _widgetHeroKeyOf(Widget widget) {
    final key = widget.key;
    return key is ValueKey<Object?> ? key.value : key;
  }

  String get _heroTag {
    if (widget.heroTag case final heroTag?) {
      return heroTag;
    }
    return _cachedHeroTag ??=
        'video-card-v-$_heroKey-${_widgetHeroKey ?? identityHashCode(this)}';
  }
  VoidCallback? get onRemove => widget.onRemove;

  @override
  void didUpdateWidget(covariant VideoCardV oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldItem = oldWidget.videoItem;
    final oldKey = oldItem.bvid ?? oldItem.aid ?? oldItem.cid;
    if (oldKey != _heroKey ||
        oldWidget.heroTag != widget.heroTag ||
        _widgetHeroKeyOf(oldWidget) != _widgetHeroKey) {
      _cachedHeroTag = null;
    }
  }

  String? get _previewPubdateText {
    if (videoItem.pubdate != null) {
      return null;
    }
    final desc = videoItem.desc?.trim();
    if (desc == null || desc.isEmpty) {
      return null;
    }
    final text = desc.split(' · ').last.trim();
    if (text.isEmpty || !VideoCardV._pubdateTextPattern.hasMatch(text)) {
      return null;
    }
    return text;
  }

  Future<void> onPushDetail() async {
    switch (videoItem.goto) {
      case 'bangumi':
        PageUtils.viewPgc(epId: videoItem.param!, heroTag: _heroTag);
        break;
      case 'av':
        var bvid = videoItem.bvid ?? IdUtils.av2bv(videoItem.aid!);
        var cid = videoItem.cid;
        bool isVertical = false;
        Dimension? dimension;
        if (videoItem is RcmdVideoItemAppModel) {
          if (videoItem.uri case final uri?) {
            isVertical = uri.isVerticalFromUri;
          }
        }
        if (cid == null) {
          if (await SearchHttp.ab2cWithDimension(aid: videoItem.aid, bvid: bvid)
              case final res?) {
            cid = res.cid;
            dimension = res.dimension;
          }
        }
        if (cid != null) {
          PageUtils.toVideoPage(
            aid: videoItem.aid,
            bvid: bvid,
            cid: cid,
            cover: videoItem.cover,
            title: videoItem.title,
            isVertical: isVertical,
            dimension: dimension,
            heroTag: _heroTag,
          );
        }
        break;
      // 动态
      case 'picture':
        try {
          PiliScheme.routePushFromUrl(videoItem.uri!);
        } catch (err) {
          SmartDialog.showToast(err.toString());
        }
        break;
      default:
        if (videoItem.uri?.isNotEmpty == true) {
          PiliScheme.routePushFromUrl(videoItem.uri!);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    void onLongPress() => imageSaveDialog(
      title: videoItem.title,
      cover: videoItem.cover,
      bvid: videoItem.bvid,
      pubdate: videoItem.pubdate,
      pubdateText: _previewPubdateText,
      view: videoItem.stat.view,
      danmaku: videoItem.stat.danmu,
      like: videoItem.stat.like,
      favorite: videoItem.stat.favorite,
      ownerName: videoItem.owner.name,
    );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Card(
          clipBehavior: Clip.hardEdge,
          child: MouseRegion(
            onEnter: PlatformUtils.isMobile
                ? null
                : (_) => setState(() => _isHovering = true),
            onExit: PlatformUtils.isMobile
                ? null
                : (_) => setState(() => _isHovering = false),
            child: InkWell(
              onTap: onPushDetail,
              onLongPress: onLongPress,
              onSecondaryTap: PlatformUtils.isMobile ? null : onLongPress,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AspectRatio(
                    aspectRatio: Style.aspectRatio,
                    child: LayoutBuilder(
                      builder: (context, boxConstraints) {
                        double maxWidth = boxConstraints.maxWidth;
                        double maxHeight = boxConstraints.maxHeight;
                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
                            VideoCoverHero(
                              tag: _heroTag,
                              child: NetworkImgLayer(
                                clip: false,
                                src: videoItem.cover,
                                width: maxWidth,
                                height: maxHeight,
                              ),
                            ),
                            if (videoItem.duration > 0)
                              PBadge(
                                bottom: 6,
                                right: 7,
                                size: .small,
                                type: .gray,
                                text: DurationUtils.formatDuration(
                                  videoItem.duration,
                                ),
                              ),
                            if (videoItem case RcmdVideoItemAppModel(
                              :final canPlay,
                            ) when canPlay != 1)
                              const PBadge(
                                text: '充电专属',
                                top: 6,
                                right: 6,
                                size: .small,
                                type: .error,
                                fontSize: 10,
                              ),
                            if (!PlatformUtils.isMobile &&
                                videoItem.goto == 'av' &&
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
                  content(context),
                ],
              ),
            ),
          ),
        ),
        if (videoItem.goto == 'av')
          Positioned(
            right: -2,
            bottom: -3,
            width: VideoPopupMenu.defaultTapTargetSize,
            height: VideoPopupMenu.defaultTapTargetSize,
            child: VideoPopupMenu(
              iconSize: 17,
              videoItem: videoItem,
              onRemove: onRemove,
            ),
          ),
      ],
    );
  }

  Widget content(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 5, 6, 5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                "${videoItem.title}\n",
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(height: 1.38),
              ),
            ),
            videoStat(context, theme),
            Row(
              spacing: 2,
              children: [
                if (videoItem.goto == 'bangumi')
                  PBadge(
                    text: videoItem.pgcBadge,
                    isStack: false,
                    size: .small,
                    type: .line_primary,
                    fontSize: 9,
                  ),
                if (Pref.showRcmdReason && videoItem.rcmdReason != null)
                  PBadge(
                    text: videoItem.rcmdReason,
                    isStack: false,
                    size: .small,
                    type: .secondary,
                  ),
                if (videoItem.goto == 'picture')
                  const PBadge(
                    text: '动态',
                    isStack: false,
                    size: .small,
                    type: .line_primary,
                    fontSize: 9,
                  ),
                if (Pref.showRcmdReason && videoItem.isFollowed)
                  const PBadge(
                    text: '已关注',
                    isStack: false,
                    size: .small,
                    type: .secondary,
                  ),
                Expanded(
                  flex: 1,
                  child: Text(
                    videoItem.owner.name.toString(),
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    semanticsLabel: 'UP：${videoItem.owner.name}',
                    style: TextStyle(
                      height: 1.5,
                      fontSize: theme.textTheme.labelMedium!.fontSize,
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ),
                if (videoItem.goto == 'av') const SizedBox(width: 10),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget videoStat(BuildContext context, ThemeData theme) {
    return Row(
      children: [
        StatWidget(type: StatType.play, value: videoItem.stat.view),
        if (videoItem.goto != 'picture') ...[
          const SizedBox(width: 4),
          StatWidget(type: StatType.danmaku, value: videoItem.stat.danmu),
        ],
        if (videoItem is RcmdVideoItemModel) ...[
          const Spacer(),
          Text.rich(
            maxLines: 1,
            TextSpan(
              style: TextStyle(
                fontSize: theme.textTheme.labelSmall!.fontSize,
                color: theme.colorScheme.outline.withValues(alpha: 0.8),
              ),
              text: DateFormatUtils.dateFormat(
                videoItem.pubdate,
                short: VideoCardV.shortFormat,
                long: VideoCardV.longFormat,
              ),
            ),
          ),
          const SizedBox(width: 2),
        ],
        // deprecated
        //  else if (videoItem is RcmdVideoItemAppModel &&
        //     videoItem.desc != null &&
        //     videoItem.desc!.contains(' · ')) ...[
        //   const Spacer(),
        //   Text.rich(
        //     maxLines: 1,
        //     TextSpan(
        //         style: TextStyle(
        //           fontSize: theme.textTheme.labelSmall!.fontSize,
        //           color: theme.colorScheme.outline.withValues(alpha: 0.8),
        //         ),
        //         text: Utils.shortenChineseDateString(
        //             videoItem.desc!.split(' · ').last)),
        //   ),
        //   const SizedBox(width: 2),
        // ]
      ],
    );
  }
}
