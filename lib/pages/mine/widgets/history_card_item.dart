import 'package:PiliMax/common/widgets/badge.dart';
import 'package:PiliMax/common/widgets/image/network_img_layer.dart';
import 'package:PiliMax/common/widgets/video_card/video_detail_hero.dart';
import 'package:PiliMax/common/widgets/video_card/video_hero_tag.dart';
import 'package:PiliMax/models/common/badge_type.dart';
import 'package:PiliMax/models_new/history/list.dart';
import 'package:PiliMax/utils/duration_utils.dart';
import 'package:PiliMax/utils/id_utils.dart';
import 'package:PiliMax/utils/page_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

/// 观看记录快捷卡片（我的页面横向列表）
class HistoryCardItem extends StatelessWidget {
  const HistoryCardItem({super.key, required this.item});

  final HistoryItemModel item;

  static const BorderRadius _cardRadius = BorderRadius.all(
    Radius.circular(12),
  );

  String get _cover => item.cover?.isNotEmpty == true
      ? item.cover!
      : item.covers?.firstOrNull ?? '';

  String get _heroTag => VideoHeroTag.forItem(
    scope: 'mine-history',
    item: item,
    contentId:
        '${item.history.business}-${item.history.oid}-'
        '${item.history.cid}-${item.history.page}',
  );

  // 宽高比与 HistoryItem 大图区一致（16:10）
  static const double _cardWidth = 180.0;
  static const double _cardHeight = 110.0;

  bool get _isArticle => item.history.business?.contains('article') == true;

  bool get _isLive => item.history.business == 'live';

  bool get _isPgc => item.history.business == 'pgc';

  bool get _isCheese => item.history.business == 'cheese';

  bool get _isVideo => !_isArticle && !_isLive && !_isPgc && !_isCheese;

  void _onTap() {
    final business = item.history.business;
    if (_isArticle) {
      PageUtils.toDupNamed(
        '/articlePage',
        parameters: {
          'id': business == 'article-list'
              ? '${item.history.cid}'
              : '${item.history.oid}',
          'type': 'read',
        },
      );
    } else if (_isLive) {
      if (item.liveStatus == 1) {
        PageUtils.toLiveRoom(item.history.oid);
      } else {
        SmartDialog.showToast('直播未开播');
      }
    } else if (_isPgc) {
      PageUtils.viewPgc(epId: item.history.epid, heroTag: _heroTag);
    } else if (_isCheese) {
      if (item.uri?.isNotEmpty == true) {
        PageUtils.viewPgcFromUri(
          item.uri!,
          isPgc: false,
          aid: item.history.oid,
          heroTag: _heroTag,
        );
      }
    } else {
      final int aid = item.history.oid!;
      final String bvid = item.history.bvid ?? IdUtils.av2bv(aid);
      PageUtils.toVideoPage(
        aid: aid,
        bvid: bvid,
        cid: item.history.cid,
        cover: _cover,
        title: item.title,
        part: item.history.page,
        heroTag: _heroTag,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasDuration = item.duration != null && item.duration != 0;
    final coverSrc = _cover;

    return GestureDetector(
      onTap: _onTap,
      behavior: HitTestBehavior.opaque,
      child: VideoDetailHero.source(
        tag: _heroTag,
        borderRadius: _cardRadius,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 封面区域
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: _cardRadius,
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.onInverseSurface.withValues(
                      alpha: 0.4,
                    ),
                    offset: const Offset(6, -8),
                    blurRadius: 0.0,
                    spreadRadius: 0.0,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: _cardRadius,
                child: SizedBox(
                  width: _cardWidth,
                  height: _cardHeight,
                  child: Stack(
                    clipBehavior: Clip.hardEdge,
                    children: [
                      NetworkImgLayer(
                        clip: false,
                        src: coverSrc,
                        width: _cardWidth,
                        height: _cardHeight,
                      ),
                      // 右上角：直播状态 / 专栏标记 / pgc badge
                      if (_isLive)
                        PBadge(
                          text: item.liveStatus == 1 ? '直播中' : '未开播',
                          top: 6.0,
                          right: 6.0,
                          type: item.liveStatus == 1
                              ? PBadgeType.primary
                              : PBadgeType.gray,
                        )
                      else if (_isArticle)
                        const PBadge(
                          text: '专栏',
                          top: 6.0,
                          right: 6.0,
                          type: PBadgeType.secondary,
                        )
                      else if (item.badge?.isNotEmpty == true)
                        PBadge(
                          text: item.badge,
                          top: 6.0,
                          right: 6.0,
                          type: PBadgeType.primary,
                        ),
                      // 右下角：视频进度（只显示角标文字，无进度条）
                      if (_isVideo && hasDuration)
                        PBadge(
                          text: item.progress == -1
                              ? '已看完'
                              : DurationUtils.formatDuration(item.progress),
                          right: 6.0,
                          bottom: 6.0,
                          type: PBadgeType.gray,
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // 标题
            SizedBox(
              width: _cardWidth,
              child: Text(
                ' ${item.title ?? ''}',
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: theme.textTheme.bodySmall,
              ),
            ),
            // 副标题（作者名 / showTitle）
            SizedBox(
              width: _cardWidth,
              child: Text(
                ' ${item.authorName ?? item.showTitle ?? ''}',
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: theme.textTheme.labelSmall!.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
