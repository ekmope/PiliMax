import 'package:PiliMax/common/style.dart';
import 'package:PiliMax/common/widgets/badge.dart';
import 'package:PiliMax/common/widgets/button/icon_button.dart';
import 'package:PiliMax/common/widgets/image/network_img_layer.dart';
import 'package:PiliMax/common/widgets/select_mask.dart';
import 'package:PiliMax/common/widgets/video_card/video_detail_hero.dart';
import 'package:PiliMax/common/widgets/video_card/video_hero_tag.dart';
import 'package:PiliMax/models/common/badge_type.dart';
import 'package:PiliMax/models_new/fav/fav_pgc/list.dart';
import 'package:PiliMax/pages/common/multi_select/base.dart';
import 'package:PiliMax/utils/page_utils.dart';
import 'package:PiliMax/utils/platform_utils.dart';
import 'package:flutter/material.dart';

class FavPgcItem extends StatelessWidget {
  const FavPgcItem({
    super.key,
    required this.item,
    required this.index,
    required this.ctr,
    required this.onSelect,
    required this.onUpdateStatus,
    this.heroScope = 'fav-pgc',
  });

  final FavPgcItemModel item;
  final int index;
  final MultiSelectBase ctr;
  final VoidCallback onSelect;
  final VoidCallback onUpdateStatus;
  final String heroScope;

  String get _heroTag => VideoHeroTag.forItem(
    scope: heroScope,
    item: item,
    contentId: item.seasonId ?? item.cover ?? 'unknown',
  );

  void onLongPress() {
    if (!ctr.enableMultiSelect.value) {
      ctr.enableMultiSelect.value = true;
      onSelect();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          VideoDetailHero.source(
            tag: _heroTag,
            child: InkWell(
              onTap: () {
                if (ctr.enableMultiSelect.value) {
                  onSelect();
                  return;
                }
                PageUtils.viewPgc(
                  seasonId: item.seasonId,
                  heroTag: _heroTag,
                );
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
                      aspectRatio: 3 / 4,
                      child: LayoutBuilder(
                        builder: (context, boxConstraints) {
                          return Stack(
                            clipBehavior: Clip.none,
                            children: [
                              NetworkImgLayer(
                                clip: false,
                                src: item.cover,
                                width: boxConstraints.maxWidth,
                                height: boxConstraints.maxHeight,
                                borderRadius: const BorderRadius.all(
                                  Radius.circular(4),
                                ),
                              ),
                              PBadge(
                                right: 4,
                                top: 4,
                                text: item.badge,
                                size: PBadgeSize.small,
                                fontSize: 10,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                  vertical: 1,
                                ),
                              ),
                              Positioned.fill(
                                child: selectMask(
                                  colorScheme,
                                  item.checked,
                                  borderRadius: const BorderRadius.all(
                                    Radius.circular(4),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.title!),
                          if (item.newEp?.indexShow != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              '${item.newEp!.indexShow}${item.isFinish == 0 && item.renewalTime?.isNotEmpty == true ? '，${item.renewalTime}' : ''}',
                              style: TextStyle(
                                fontSize: 13,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                          if (item.progress != null) ...[
                            SizedBox(
                              height: item.newEp?.indexShow != null ? 2 : 6,
                            ),
                            Text(
                              item.progress!,
                              style: TextStyle(
                                fontSize: 13,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: 12,
            bottom: 0,
            child: iconButton(
              iconSize: 18,
              onPressed: onUpdateStatus,
              icon: const Icon(Icons.more_vert),
              iconColor: colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}
