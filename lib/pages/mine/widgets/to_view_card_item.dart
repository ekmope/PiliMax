import 'package:PiliMax/common/widgets/badge.dart';
import 'package:PiliMax/common/widgets/image/network_img_layer.dart';
import 'package:PiliMax/common/widgets/video_card/video_cover_hero.dart';
import 'package:PiliMax/http/search.dart';
import 'package:PiliMax/models/common/badge_type.dart';
import 'package:PiliMax/models_new/later/list.dart';
import 'package:PiliMax/utils/duration_utils.dart';
import 'package:PiliMax/utils/page_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

class ToViewCardItem extends StatelessWidget {
  const ToViewCardItem({super.key, required this.item});

  final LaterItemModel item;

  static const double _cardWidth = 180.0;
  static const double _cardHeight = 110.0;
  static const BorderRadius _cardRadius = BorderRadius.all(
    Radius.circular(12),
  );

  String get _heroTag =>
      'mine-later-${item.bvid ?? item.aid}-${item.cid}';

  Future<void> _onTap() async {
    if (item.isPugv ?? false) {
      PageUtils.viewPugv(seasonId: item.aid, heroTag: _heroTag);
      return;
    }
    if (item.isPgc ?? false) {
      if (item.bangumi?.epId != null) {
        PageUtils.viewPgc(epId: item.bangumi!.epId, heroTag: _heroTag);
      } else if (item.redirectUrl?.isNotEmpty == true) {
        PageUtils.viewPgcFromUri(item.redirectUrl!, heroTag: _heroTag);
      }
      return;
    }
    try {
      final cid =
          item.cid ?? await SearchHttp.ab2c(aid: item.aid, bvid: item.bvid);
      if (cid != null) {
        PageUtils.toVideoPage(
          aid: item.aid,
          bvid: item.bvid,
          cid: cid,
          cover: item.pic,
          title: item.title,
          heroTag: _heroTag,
        );
      }
    } catch (err) {
      SmartDialog.showToast(err.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasDuration = item.duration != null && item.duration != 0;

    return GestureDetector(
      onTap: _onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                    VideoCoverHero(
                      tag: _heroTag,
                      borderRadius: _cardRadius,
                      child: NetworkImgLayer(
                        src: item.pic,
                        width: _cardWidth,
                        height: _cardHeight,
                      ),
                    ),
                    if (item.pgcLabel?.isNotEmpty == true)
                      PBadge(
                        text: item.pgcLabel,
                        top: 6.0,
                        right: 6.0,
                        type: PBadgeType.primary,
                      ),
                    if (hasDuration)
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
          SizedBox(
            width: _cardWidth,
            child: Text(
              ' ${item.title ?? ''}',
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: theme.textTheme.bodySmall,
            ),
          ),
          SizedBox(
            width: _cardWidth,
            child: Text(
              ' ${item.owner?.name ?? ''}',
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: theme.textTheme.labelSmall!.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
