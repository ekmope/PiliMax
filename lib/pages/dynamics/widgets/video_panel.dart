// 视频 or 合集
import 'package:PiliMax/common/style.dart';
import 'package:PiliMax/common/widgets/badge.dart';
import 'package:PiliMax/common/widgets/image/network_img_layer.dart';
import 'package:PiliMax/common/widgets/svg/play_icon.dart';
import 'package:PiliMax/common/widgets/video_card/video_detail_hero.dart';
import 'package:PiliMax/common/widgets/video_card/watch_later_button.dart';
import 'package:PiliMax/models/common/badge_type.dart';
import 'package:PiliMax/models/dynamics/result.dart';
import 'package:PiliMax/utils/num_utils.dart';
import 'package:PiliMax/utils/platform_utils.dart';
import 'package:flutter/material.dart';

Widget videoSeasonWidget(
  BuildContext context, {
  required int floor,
  required ThemeData theme,
  required DynamicItemModel item,
  required bool isSave,
  required bool isDetail,
  String? heroTag,
}) {
  return _VideoSeasonWidget(
    floor: floor,
    theme: theme,
    item: item,
    isDetail: isDetail,
    heroTag: heroTag,
  );
}

class _VideoSeasonWidget extends StatefulWidget {
  const _VideoSeasonWidget({
    required this.floor,
    required this.theme,
    required this.item,
    required this.isDetail,
    required this.heroTag,
  });

  final int floor;
  final ThemeData theme;
  final DynamicItemModel item;
  final bool isDetail;
  final String? heroTag;

  @override
  State<_VideoSeasonWidget> createState() => _VideoSeasonWidgetState();
}

class _VideoSeasonWidgetState extends State<_VideoSeasonWidget> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final floor = widget.floor;
    final theme = widget.theme;
    final item = widget.item;
    final isDetail = widget.isDetail;
    final heroTag = widget.heroTag;

    // type archive / ugcSeason
    // archive: 视频，显示发布人；ugcSeason: 合集，不显示发布人
    final DynamicArchiveModel? video = switch (item.type) {
      'DYNAMIC_TYPE_AV' => item.modules.moduleDynamic?.major?.archive,
      'DYNAMIC_TYPE_UGC_SEASON' => item.modules.moduleDynamic?.major?.ugcSeason,
      'DYNAMIC_TYPE_PGC' ||
      'DYNAMIC_TYPE_PGC_UNION' => item.modules.moduleDynamic?.major?.pgc,
      'DYNAMIC_TYPE_COURSES_SEASON' =>
        item.modules.moduleDynamic?.major?.courses,
      _ => null,
    };

    if (video == null) {
      return const SizedBox.shrink();
    }

    final padding = floor == 1
        ? const EdgeInsets.symmetric(horizontal: 12)
        : EdgeInsets.zero;
    final card = Padding(
      padding: padding,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovering = true),
        onExit: (_) => setState(() => _isHovering = false),
        child: Column(
          spacing: 6,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (video.cover case final cover?)
              Stack(
                clipBehavior: Clip.none,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      return NetworkImgLayer(
                        clip: false,
                        width: constraints.maxWidth,
                        height: constraints.maxWidth / Style.aspectRatio,
                        src: cover,
                        quality: 40,
                      );
                    },
                  ),
                  if (video.badge?.text case final badge?)
                    PBadge(
                      text: badge,
                      top: 8.0,
                      right: 10.0,
                      bottom: null,
                      left: null,
                      type: switch (badge) {
                        '充电专属' => PBadgeType.error,
                        _ => PBadgeType.primary,
                      },
                    ),
                  if (_showQuickWatchLater(video, item))
                    Positioned(
                      top: 8,
                      right: 10,
                      child: Visibility(
                        visible: _isHovering,
                        maintainState: true,
                        child: QuickWatchLaterButton(
                          target: WatchLaterTarget.from(
                            bvid: video.bvid,
                            aid: video.aid,
                            fallback: item.idStr ?? item,
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      height: 70,
                      alignment: Alignment.bottomLeft,
                      padding: const EdgeInsets.fromLTRB(10, 0, 8, 8),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black54],
                        ),
                        borderRadius: .vertical(bottom: Style.imgRadius),
                      ),
                      child: DefaultTextStyle.merge(
                        style: TextStyle(
                          fontSize: theme.textTheme.labelMedium!.fontSize,
                          color: Colors.white,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (video.durationText
                                case final durationText?) ...[
                              DecoratedBox(
                                decoration: const BoxDecoration(
                                  color: Colors.black45,
                                  borderRadius: .all(.circular(4)),
                                ),
                                child: Text(' $durationText '),
                              ),
                              const SizedBox(width: 6),
                            ],
                            if (video.stat case final stat?) ...[
                              Text('${NumUtils.numFormat(stat.play)}播放'),
                              const SizedBox(width: 6),
                              Text('${NumUtils.numFormat(stat.danmu)}弹幕'),
                            ],
                            const Spacer(),
                            const PlayIcon(size: 50),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            if (video.title case final title?)
              Text(
                title,
                maxLines: isDetail ? null : 1,
                style: const TextStyle(fontWeight: FontWeight.bold),
                overflow: isDetail ? null : TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
    );
    if (heroTag == null) {
      return card;
    }
    return VideoDetailHero.source(tag: heroTag, child: card);
  }

  bool _showQuickWatchLater(DynamicArchiveModel video, DynamicItemModel item) {
    return !PlatformUtils.isMobile &&
        video.bvid?.isNotEmpty == true &&
        item.type != 'DYNAMIC_TYPE_PGC' &&
        item.type != 'DYNAMIC_TYPE_PGC_UNION';
  }
}
