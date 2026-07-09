import 'package:PiliMax/common/style.dart';
import 'package:PiliMax/common/widgets/badge.dart';
import 'package:PiliMax/common/widgets/image/image_save.dart';
import 'package:PiliMax/common/widgets/image/network_img_layer.dart';
import 'package:PiliMax/common/widgets/stat/stat.dart';
import 'package:PiliMax/common/widgets/video_card/video_cover_hero.dart';
import 'package:PiliMax/http/search.dart';
import 'package:PiliMax/models/common/badge_type.dart';
import 'package:PiliMax/models/common/stat_type.dart';
import 'package:PiliMax/models_new/sub/sub_detail/media.dart';
import 'package:PiliMax/utils/date_utils.dart';
import 'package:PiliMax/utils/duration_utils.dart';
import 'package:PiliMax/utils/page_utils.dart';
import 'package:PiliMax/utils/platform_utils.dart';
import 'package:flutter/material.dart';

// 收藏视频卡片 - 水平布局
class SubVideoCardH extends StatelessWidget {
  final SubDetailItemModel videoItem;
  final int? searchType;
  final int index;

  const SubVideoCardH({
    super.key,
    required this.videoItem,
    required this.index,
    this.searchType,
  });

  String get _heroTag => 'sub-video-${videoItem.bvid}-$index';

  @override
  Widget build(BuildContext context) {
    void onLongPress() => imageSaveDialog(
      title: videoItem.title,
      cover: videoItem.cover,
      bvid: videoItem.bvid,
      pubdate: videoItem.pubtime,
      view: videoItem.cntInfo?.play,
      danmaku: videoItem.cntInfo?.danmaku,
    );
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: () async {
          final res = await SearchHttp.ab2cWithDimension(bvid: videoItem.bvid);
          final cid = res?.cid;
          if (cid != null) {
            PageUtils.toVideoPage(
              bvid: videoItem.bvid,
              cid: cid,
              cover: videoItem.cover,
              title: videoItem.title,
              dimension: res!.dimension,
              heroTag: _heroTag,
            );
          }
        },
        onLongPress: onLongPress,
        onSecondaryTap: PlatformUtils.isMobile ? null : onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Style.safeSpace,
            vertical: 5,
          ),
          child: Row(
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
                            src: videoItem.cover,
                            width: maxWidth,
                            height: maxHeight,
                          ),
                        ),
                        PBadge(
                          text: DurationUtils.formatDuration(
                            videoItem.duration,
                          ),
                          right: 6.0,
                          bottom: 6.0,
                          type: PBadgeType.gray,
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(width: 10),
              content(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget content(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              videoItem.title!,
              textAlign: TextAlign.start,
              style: const TextStyle(
                letterSpacing: 0.3,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            DateFormatUtils.dateFormat(videoItem.pubtime),
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
          const SizedBox(height: 3),
          Row(
            spacing: 8,
            children: [
              StatWidget(
                type: StatType.play,
                value: videoItem.cntInfo?.play,
              ),
              StatWidget(
                type: StatType.danmaku,
                value: videoItem.cntInfo?.danmaku,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
