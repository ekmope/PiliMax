import 'package:PiliMax/common/style.dart';
import 'package:PiliMax/common/widgets/image/image_save.dart';
import 'package:PiliMax/common/widgets/image/network_img_layer.dart';
import 'package:PiliMax/common/widgets/video_card/video_detail_hero.dart';
import 'package:PiliMax/common/widgets/video_card/video_hero_tag.dart';
import 'package:PiliMax/models_new/space/space_archive/item.dart';
import 'package:PiliMax/utils/page_utils.dart';
import 'package:PiliMax/utils/platform_utils.dart';
import 'package:flutter/material.dart';

// 视频卡片 - 垂直布局
class PgcCardVMemberPgc extends StatelessWidget {
  const PgcCardVMemberPgc({
    super.key,
    required this.item,
    required this.index,
    required this.heroScope,
  });

  final SpaceArchiveItem item;
  final int index;
  final String heroScope;

  String get _heroTag => VideoHeroTag.forItem(
    scope: heroScope,
    item: item,
    contentId: item.param ?? item.cover ?? 'unknown',
  );

  @override
  Widget build(BuildContext context) {
    void onLongPress() => imageSaveDialog(
      title: item.title,
      cover: item.cover,
    );
    return VideoDetailTransitionSource(
      tag: _heroTag,
      layout: VideoTransitionSourceLayout.verticalCard,
      child: Card(
        shape: const RoundedRectangleBorder(borderRadius: Style.mdRadius),
        child: InkWell(
          borderRadius: Style.mdRadius,
          onTap: () => PageUtils.viewPgc(
            seasonId: item.param,
            cover: item.cover,
            title: item.title,
            heroTag: _heroTag,
          ),
          onLongPress: onLongPress,
          onSecondaryTap: PlatformUtils.isMobile ? null : onLongPress,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              VideoDetailHero.source(
                child: AspectRatio(
                  aspectRatio: 0.75,
                  child: LayoutBuilder(
                    builder: (context, boxConstraints) {
                      return NetworkImgLayer(
                        clip: false,
                        src: item.cover,
                        width: boxConstraints.maxWidth,
                        height: boxConstraints.maxHeight,
                      );
                    },
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 5, 0, 3),
                child: VideoDetailTransitionTitle(
                  text: item.title,
                  textAlign: TextAlign.start,
                  style: const TextStyle(letterSpacing: 0.3),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  child: Text(
                    item.title,
                    textAlign: TextAlign.start,
                    style: const TextStyle(
                      letterSpacing: 0.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
