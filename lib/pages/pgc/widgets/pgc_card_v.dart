import 'package:PiliMax/common/style.dart';
import 'package:PiliMax/common/widgets/badge.dart';
import 'package:PiliMax/common/widgets/image/image_save.dart';
import 'package:PiliMax/common/widgets/image/network_img_layer.dart';
import 'package:PiliMax/common/widgets/video_card/video_cover_hero.dart';
import 'package:PiliMax/models/common/badge_type.dart';
import 'package:PiliMax/models_new/fav/fav_pgc/list.dart';
import 'package:PiliMax/utils/page_utils.dart';
import 'package:PiliMax/utils/platform_utils.dart';
import 'package:flutter/material.dart';

// 视频卡片 - 垂直布局
class PgcCardV extends StatelessWidget {
  const PgcCardV({
    super.key,
    required this.item,
    required this.index,
    required this.heroScope,
  });

  final FavPgcItemModel item;
  final int index;
  final String heroScope;

  String get _heroTag =>
      '$heroScope-${item.seasonId ?? item.cover}-$index';

  @override
  Widget build(BuildContext context) {
    void onLongPress() => imageSaveDialog(
      title: item.title,
      cover: item.cover,
    );
    return Card(
      shape: const RoundedRectangleBorder(borderRadius: Style.mdRadius),
      child: InkWell(
        borderRadius: Style.mdRadius,
        onLongPress: onLongPress,
        onSecondaryTap: PlatformUtils.isMobile ? null : onLongPress,
        onTap: () => PageUtils.viewPgc(
          seasonId: item.seasonId,
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
                      VideoCoverHero(
                        tag: _heroTag,
                        child: NetworkImgLayer(
                          type: .emote,
                          src: item.cover,
                          width: maxWidth,
                          height: maxHeight,
                        ),
                      ),
                      PBadge(
                        text: item.badge,
                        top: 6,
                        right: 6,
                        bottom: null,
                        left: null,
                      ),
                      if (item.isFinish == 0 &&
                          item.renewalTime?.isNotEmpty == true)
                        PBadge(
                          text: item.renewalTime,
                          bottom: 6,
                          left: 6,
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
    );
  }

  Widget content(BuildContext context) {
    final theme = Theme.of(context);
    final style = TextStyle(
      fontSize: theme.textTheme.labelMedium!.fontSize,
      color: theme.colorScheme.outline,
    );
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 5, 0, 3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.title!,
              textAlign: TextAlign.start,
              style: const TextStyle(
                letterSpacing: 0.3,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 1),
            if (item.progress != null)
              Text(
                item.progress!,
                maxLines: 1,
                style: style,
              )
            else if (item.newEp?.indexShow != null)
              Text(
                item.newEp!.indexShow!,
                maxLines: 1,
                style: style,
              ),
          ],
        ),
      ),
    );
  }
}
