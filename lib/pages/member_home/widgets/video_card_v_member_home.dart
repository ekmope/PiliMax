import 'package:PiliMax/common/style.dart';
import 'package:PiliMax/common/widgets/badge.dart';
import 'package:PiliMax/common/widgets/image/image_save.dart';
import 'package:PiliMax/common/widgets/image/network_img_layer.dart';
import 'package:PiliMax/common/widgets/video_card/video_detail_hero.dart';
import 'package:PiliMax/common/widgets/video_card/video_hero_tag.dart';
import 'package:PiliMax/models/common/badge_type.dart';
import 'package:PiliMax/models_new/space/space_archive/item.dart';
import 'package:PiliMax/utils/app_scheme.dart';
import 'package:PiliMax/utils/duration_utils.dart';
import 'package:PiliMax/utils/extension/dimension_ext.dart';
import 'package:PiliMax/utils/id_utils.dart';
import 'package:PiliMax/utils/page_utils.dart';
import 'package:PiliMax/utils/platform_utils.dart';
import 'package:flutter/material.dart';

// 视频卡片 - 垂直布局
class VideoCardVMemberHome extends StatelessWidget {
  final SpaceArchiveItem videoItem;
  final int index;
  final String heroScope;

  const VideoCardVMemberHome({
    super.key,
    required this.videoItem,
    required this.index,
    required this.heroScope,
  });

  String get _heroTag => VideoHeroTag.forItem(
    scope: heroScope,
    item: videoItem,
    contentId:
        videoItem.bvid ?? videoItem.param ?? videoItem.cover ?? 'unknown',
  );

  void onPushDetail() {
    String? goto = videoItem.goto;
    switch (goto) {
      case 'bangumi':
        PageUtils.viewPgc(
          epId: videoItem.param,
          heroTag: _heroTag,
          cover: videoItem.cover,
          title: videoItem.title,
        );
        break;

      case 'av':
        if (videoItem.isPgc == true) {
          if (videoItem.uri?.isNotEmpty == true) {
            PageUtils.viewPgcFromUri(
              videoItem.uri!,
              heroTag: _heroTag,
              cover: videoItem.cover,
              title: videoItem.title,
            );
          }
          return;
        }

        String? aid = videoItem.param;
        String? bvid = videoItem.bvid;
        if (aid == null && bvid == null) {
          return;
        }

        bvid ??= IdUtils.av2bv(int.parse(aid!));
        PageUtils.toVideoPage(
          bvid: bvid,
          cid: videoItem.cid,
          cover: videoItem.cover,
          title: videoItem.title,
          isVertical: videoItem.uri?.verticalFromUri,
          heroTag: _heroTag,
        );
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
      aid: videoItem.param,
      bvid: videoItem.bvid,
      pubdateText: videoItem.publishTimeText,
      view: videoItem.stat.view,
      danmaku: videoItem.stat.danmu,
      ownerName: videoItem.owner.name,
    );
    return VideoDetailHero.source(
      tag: _heroTag,
      child: Card(
        clipBehavior: Clip.hardEdge,
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
                        NetworkImgLayer(
                          clip: false,
                          src: videoItem.cover,
                          width: maxWidth,
                          height: maxHeight,
                        ),
                        if (videoItem.duration > 0)
                          PBadge(
                            bottom: 6,
                            right: 7,
                            size: PBadgeSize.small,
                            type: PBadgeType.gray,
                            text: DurationUtils.formatDuration(
                              videoItem.duration,
                            ),
                          ),
                        if (videoItem.badges?.isNotEmpty == true)
                          PBadge(
                            text: videoItem.badges!
                                .map((e) => e.text ?? '')
                                .join('|'),
                            top: 6,
                            right: 6,
                            type: videoItem.badges!.first.text == '充电专属'
                                ? PBadgeType.error
                                : PBadgeType.primary,
                          )
                        else if (videoItem.isCooperation == true)
                          const PBadge(
                            text: '合作',
                            top: 6,
                            right: 6,
                          )
                        else if (videoItem.isSteins == true)
                          const PBadge(
                            text: '互动',
                            top: 6,
                            right: 6,
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
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 5, 6, 5),
        child: Text(
          '${videoItem.title}\n',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            height: 1.38,
          ),
        ),
      ),
    );
  }
}
