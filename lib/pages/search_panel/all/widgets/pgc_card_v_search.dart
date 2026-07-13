import 'package:PiliMax/common/style.dart';
import 'package:PiliMax/common/widgets/badge.dart';
import 'package:PiliMax/common/widgets/image/image_save.dart';
import 'package:PiliMax/common/widgets/image/network_img_layer.dart';
import 'package:PiliMax/common/widgets/video_card/video_detail_hero.dart';
import 'package:PiliMax/common/widgets/video_card/video_hero_tag.dart';
import 'package:PiliMax/models/search/result.dart';
import 'package:PiliMax/utils/page_utils.dart';
import 'package:PiliMax/utils/platform_utils.dart';
import 'package:flutter/material.dart';

// 视频卡片 - 垂直布局
class PgcCardVSearch extends StatelessWidget {
  const PgcCardVSearch({
    super.key,
    required this.item,
    this.heroTagPrefix = 'search-pgc-v',
    this.index,
  });

  final SearchPgcItemModel item;
  final String heroTagPrefix;
  final int? index;

  String get _heroTag => VideoHeroTag.forItem(
    scope: heroTagPrefix,
    item: item,
    contentId: item.seasonId ?? item.mediaId ?? item.cover ?? 'unknown',
  );

  @override
  Widget build(BuildContext context) {
    void onLongPress() => imageSaveDialog(
      title: item.title.map((e) => e.text).join(),
      cover: item.cover,
    );
    return VideoDetailTransitionSource(
      tag: _heroTag,
      child: Card(
        shape: const RoundedRectangleBorder(borderRadius: Style.mdRadius),
        child: InkWell(
          borderRadius: Style.mdRadius,
          onLongPress: onLongPress,
          onSecondaryTap: PlatformUtils.isMobile ? null : onLongPress,
          onTap: () => PageUtils.viewPgc(
            seasonId: item.seasonId,
            cover: item.cover,
            title: item.title.map((item) => item.text).join(),
            heroTag: _heroTag,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              VideoDetailHero.source(
                child: AspectRatio(
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
                          PBadge(
                            text: item.seasonTypeName,
                            right: 6,
                            top: 6,
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 5, 0, 3),
                child: Text(
                  item.title.map((e) => e.text).join(),
                  textAlign: TextAlign.start,
                  style: const TextStyle(
                    letterSpacing: 0.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
