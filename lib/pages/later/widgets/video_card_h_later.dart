import 'package:PiliMax/common/style.dart';
import 'package:PiliMax/common/widgets/badge.dart';
import 'package:PiliMax/common/widgets/button/icon_button.dart';
import 'package:PiliMax/common/widgets/image/network_img_layer.dart';
import 'package:PiliMax/common/widgets/progress_bar/video_progress_indicator.dart';
import 'package:PiliMax/common/widgets/select_mask.dart';
import 'package:PiliMax/common/widgets/stat/stat.dart';
import 'package:PiliMax/common/widgets/video_card/video_detail_hero.dart';
import 'package:PiliMax/common/widgets/video_card/video_hero_tag.dart';
import 'package:PiliMax/models/common/badge_type.dart';
import 'package:PiliMax/models/common/stat_type.dart';
import 'package:PiliMax/models_new/later/list.dart';
import 'package:PiliMax/pages/later/controller.dart';
import 'package:PiliMax/utils/duration_utils.dart';
import 'package:PiliMax/utils/page_utils.dart';
import 'package:PiliMax/utils/platform_utils.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

// 视频卡片 - 水平布局
class VideoCardHLater extends StatelessWidget {
  const VideoCardHLater({
    super.key,
    required this.ctr,
    required this.index,
    required this.videoItem,
    required this.onViewLater,
    required this.heroScope,
  });
  final int index;
  final BaseLaterController ctr;
  final LaterItemModel videoItem;
  final void Function(int? cid, String heroTag) onViewLater;
  final String heroScope;

  String get _heroTag => VideoHeroTag.forItem(
    scope: heroScope,
    item: videoItem,
    contentId: videoItem.bvid ?? videoItem.aid ?? 'unknown',
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enableMultiSelect = ctr.enableMultiSelect.value;

    final onLongPress = enableMultiSelect
        ? null
        : () => ctr
            ..enableMultiSelect.value = true
            ..onSelect(videoItem);

    return Material(
      type: MaterialType.transparency,
      child: VideoDetailTransitionSource(
        tag: _heroTag,
        layout: VideoTransitionSourceLayout.horizontalRow,
        child: InkWell(
          onLongPress: onLongPress,
          onSecondaryTap: PlatformUtils.isMobile ? null : onLongPress,
          onTap: enableMultiSelect
              ? () => ctr.onSelect(videoItem)
              : () {
                  if (videoItem.isPugv ?? false) {
                    PageUtils.viewPugv(
                      seasonId: videoItem.aid,
                      heroTag: _heroTag,
                      cover: videoItem.pic,
                      title: videoItem.title,
                    );
                    return;
                  }
                  if (videoItem.isPgc ?? false) {
                    if (videoItem.bangumi?.epId != null) {
                      PageUtils.viewPgc(
                        epId: videoItem.bangumi!.epId,
                        heroTag: _heroTag,
                        cover: videoItem.pic,
                        title: videoItem.title,
                      );
                    } else if (videoItem.redirectUrl?.isNotEmpty == true) {
                      PageUtils.viewPgcFromUri(
                        videoItem.redirectUrl!,
                        heroTag: _heroTag,
                        cover: videoItem.pic,
                        title: videoItem.title,
                      );
                    }
                    return;
                  }
                  onViewLater(videoItem.cid, _heroTag);
                },
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Style.safeSpace,
              vertical: 5,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                VideoDetailHero.source(
                  child: AspectRatio(
                    aspectRatio: Style.aspectRatio,
                    child: LayoutBuilder(
                      builder: (context, boxConstraints) {
                        final double maxWidth = boxConstraints.maxWidth;
                        final double maxHeight = boxConstraints.maxHeight;
                        num? progress = videoItem.progress;
                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
                            NetworkImgLayer(
                              clip: false,
                              src: videoItem.pic,
                              width: maxWidth,
                              height: maxHeight,
                              cacheWidth: videoItem.dimension?.cacheWidth,
                            ),
                            if (videoItem.isCharging == true)
                              const PBadge(
                                text: '充电专属',
                                top: 6.0,
                                right: 6.0,
                                type: PBadgeType.error,
                              )
                            else if (videoItem.rights?.isCooperation == 1)
                              const PBadge(text: '合作', top: 6.0, right: 6.0)
                            else if (videoItem.pgcLabel != null)
                              PBadge(
                                text: videoItem.pgcLabel,
                                top: 6.0,
                                right: 6.0,
                              )
                            else if (videoItem.isPugv ?? false)
                              const PBadge(text: '课堂', top: 6.0, right: 6.0),
                            if (progress != null && progress != 0) ...[
                              PBadge(
                                text: progress == -1
                                    ? '已看完'
                                    : '${DurationUtils.formatDuration(progress)}/${DurationUtils.formatDuration(videoItem.duration)}',
                                right: 6,
                                bottom: 8,
                                type: PBadgeType.gray,
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
                                      : progress / videoItem.duration!,
                                ),
                              ),
                            ] else if (videoItem.duration! > 0)
                              PBadge(
                                text: DurationUtils.formatDuration(
                                  videoItem.duration,
                                ),
                                right: 6.0,
                                bottom: 6.0,
                                type: PBadgeType.gray,
                              ),
                            Positioned.fill(
                              child: selectMask(
                                theme.colorScheme,
                                videoItem.checked,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                content(context, theme),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget content(BuildContext context, ThemeData theme) {
    final isPgc = videoItem.isPgc == true && videoItem.bangumi != null;
    Widget stat = StatWidget(type: StatType.play, value: videoItem.stat?.view);
    final title = isPgc ? videoItem.bangumi!.season!.title! : videoItem.title!;
    final titleStyle = TextStyle(
      fontSize: theme.textTheme.bodyMedium!.fontSize,
      height: 1.42,
      letterSpacing: 0.3,
    );
    final titleWidget = VideoDetailTransitionTitle(
      text: title,
      style: titleStyle,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      child: Text(
        title,
        style: titleStyle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
    return Expanded(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: isPgc
                ? [
                    titleWidget,
                    const SizedBox(height: 3),
                    Text(
                      videoItem.subtitle!,
                      textAlign: TextAlign.start,
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.outline,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Spacer(),
                    stat,
                  ]
                : [
                    Expanded(child: titleWidget),
                    Text(
                      videoItem.owner!.name!,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1,
                        color: theme.colorScheme.outline,
                        overflow: TextOverflow.clip,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      spacing: 8,
                      children: [
                        stat,
                        StatWidget(
                          type: StatType.danmaku,
                          value: videoItem.stat?.danmaku,
                        ),
                      ],
                    ),
                  ],
          ),
          Positioned(
            right: -Style.safeSpace,
            bottom: -4,
            child: Row(
              spacing: 2,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (index > 0)
                  Obx(() {
                    final isLoading = ctr.isPromotingToTop(videoItem);
                    return iconButton(
                      tooltip: '置顶',
                      size: 40,
                      onPressed: isLoading
                          ? null
                          : () => ctr.promoteToTop(index, videoItem),
                      icon: isLoading
                          ? SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: theme.colorScheme.outline,
                              ),
                            )
                          : const Icon(Icons.vertical_align_top, size: 16),
                      iconColor: theme.colorScheme.outline,
                    );
                  }),
                iconButton(
                  tooltip: '移除',
                  size: 40,
                  onPressed: () => ctr.toViewDel(context, index, videoItem.aid),
                  icon: const Icon(Icons.clear),
                  iconColor: theme.colorScheme.outline,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
