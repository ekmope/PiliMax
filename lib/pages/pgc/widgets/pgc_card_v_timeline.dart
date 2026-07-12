import 'package:PiliMax/common/style.dart';
import 'package:PiliMax/common/widgets/badge.dart';
import 'package:PiliMax/common/widgets/image/image_save.dart';
import 'package:PiliMax/common/widgets/image/network_img_layer.dart';
import 'package:PiliMax/common/widgets/video_card/video_detail_hero.dart';
import 'package:PiliMax/common/widgets/video_card/video_hero_tag.dart';
import 'package:PiliMax/models/common/badge_type.dart';
import 'package:PiliMax/models_new/pgc/pgc_timeline/episode.dart';
import 'package:PiliMax/utils/page_utils.dart';
import 'package:PiliMax/utils/platform_utils.dart';
import 'package:flutter/material.dart';

// 视频卡片 - 垂直布局
class PgcCardVTimeline extends StatelessWidget {
  const PgcCardVTimeline({
    super.key,
    required this.item,
    required this.index,
    required this.heroScope,
  });

  final Episode item;
  final int index;
  final String heroScope;

  String get _heroTag => VideoHeroTag.forItem(
    scope: heroScope,
    item: item,
    contentId: '${item.seasonId}-${item.episodeId}',
  );

  @override
  Widget build(BuildContext context) {
    void onLongPress() => imageSaveDialog(
      title: item.title,
      cover: item.cover,
    );
    return VideoDetailHero.source(
      tag: _heroTag,
      child: Card(
        shape: const RoundedRectangleBorder(borderRadius: Style.mdRadius),
        child: InkWell(
          borderRadius: Style.mdRadius,
          onLongPress: onLongPress,
          onSecondaryTap: PlatformUtils.isMobile ? null : onLongPress,
          onTap: () => PageUtils.viewPgc(
            seasonId: item.seasonId,
            epId: item.episodeId,
            heroTag: _heroTag,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 0.75,
                child: LayoutBuilder(
                  builder: (context, boxConstraints) {
                    final double maxWidth = boxConstraints.maxWidth;
                    final double maxHeight = boxConstraints.maxHeight;
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        NetworkImgLayer(
                          clip: false,
                          src: item.cover,
                          width: maxWidth,
                          height: maxHeight,
                        ),
                        if (item.follow == 1)
                          const PBadge(
                            text: '已追番',
                            right: 6,
                            top: 6,
                          ),
                        PBadge(
                          text: '${item.pubTime}',
                          left: 6,
                          bottom: 6,
                          type: PBadgeType.gray,
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
    );
  }

  Widget content(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 5, 0, 3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.title ?? '',
              textAlign: TextAlign.start,
              style: const TextStyle(
                letterSpacing: 0.3,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              item.pubIndex ?? '',
              maxLines: 1,
              style: TextStyle(
                fontSize: theme.textTheme.labelMedium!.fontSize,
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
