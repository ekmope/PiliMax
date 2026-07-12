import 'package:PiliMax/common/style.dart';
import 'package:PiliMax/common/widgets/badge.dart';
import 'package:PiliMax/common/widgets/image/image_save.dart';
import 'package:PiliMax/common/widgets/image/network_img_layer.dart';
import 'package:PiliMax/common/widgets/stat/stat.dart';
import 'package:PiliMax/common/widgets/video_card/video_card_v.dart';
import 'package:PiliMax/common/widgets/video_card/video_detail_hero.dart';
import 'package:PiliMax/common/widgets/video_card/video_hero_tag.dart';
import 'package:PiliMax/models/common/badge_type.dart';
import 'package:PiliMax/models/common/stat_type.dart';
import 'package:PiliMax/models_new/member/coin_like_arc/item.dart';
import 'package:PiliMax/utils/date_utils.dart';
import 'package:PiliMax/utils/duration_utils.dart';
import 'package:PiliMax/utils/page_utils.dart';
import 'package:PiliMax/utils/platform_utils.dart';
import 'package:flutter/material.dart';

class MemberCoinLikeItem extends StatefulWidget {
  final CoinLikeArcItem item;
  final String heroScope;
  final int index;

  const MemberCoinLikeItem({
    super.key,
    required this.item,
    required this.heroScope,
    required this.index,
  });

  @override
  State<MemberCoinLikeItem> createState() => _MemberCoinLikeItemState();
}

class _MemberCoinLikeItemState extends State<MemberCoinLikeItem> {
  CoinLikeArcItem get item => widget.item;
  Object? get _heroKey => item.param ?? item.uri ?? item.cover;
  String get _heroTag => VideoHeroTag.forItem(
    scope: 'member-${widget.heroScope}',
    item: item,
    contentId: _heroKey ?? 'unknown',
  );

  @override
  Widget build(BuildContext context) {
    void onLongPress() => imageSaveDialog(
      title: item.title,
      cover: item.cover,
      aid: item.param,
    );
    return VideoDetailHero.source(
      tag: _heroTag,
      child: Card(
        clipBehavior: Clip.hardEdge,
        child: InkWell(
          onTap: () {
            if (item.isPgc == true) {
              if (item.uri?.isNotEmpty == true) {
                PageUtils.viewPgcFromUri(item.uri!, heroTag: _heroTag);
              }
              return;
            }

            if (item.param != null) {
              PageUtils.toVideoPage(
                aid: int.parse(item.param!),
                cid: null,
                cover: item.cover,
                title: item.title,
                heroTag: _heroTag,
              );
            }
          },
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
                          src: item.cover,
                          width: maxWidth,
                          height: maxHeight,
                        ),
                        if (item.isCooperation == true)
                          const PBadge(
                            text: '合作',
                            top: 6,
                            right: 6,
                          )
                        else if (item.isSteins == true)
                          const PBadge(
                            text: '互动',
                            top: 6,
                            right: 6,
                          ),
                        if (item.duration != null && item.duration! > 0)
                          PBadge(
                            bottom: 6,
                            right: 6,
                            type: PBadgeType.gray,
                            text: DurationUtils.formatDuration(item.duration),
                          ),
                      ],
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(5, 6, 0, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${item.title}\n',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        StatWidget(
                          type: StatType.play,
                          value: item.play,
                        ),
                        const SizedBox(width: 8),
                        StatWidget(
                          type: StatType.danmaku,
                          value: item.danmaku,
                        ),
                        const Spacer(),
                        Text(
                          DateFormatUtils.dateFormat(
                            item.ctime,
                            short: VideoCardV.shortFormat,
                            long: VideoCardV.longFormat,
                          ),
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
