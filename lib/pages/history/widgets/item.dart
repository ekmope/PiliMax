import 'package:PiliMax/common/style.dart';
import 'package:PiliMax/common/widgets/badge.dart';
import 'package:PiliMax/common/widgets/flutter/popup_menu.dart';
import 'package:PiliMax/common/widgets/image/network_img_layer.dart';
import 'package:PiliMax/common/widgets/progress_bar/video_progress_indicator.dart';
import 'package:PiliMax/common/widgets/select_mask.dart';
import 'package:PiliMax/common/widgets/video_card/video_cover_hero.dart';
import 'package:PiliMax/http/search.dart';
import 'package:PiliMax/http/user.dart';
import 'package:PiliMax/models/common/badge_type.dart';
import 'package:PiliMax/models_new/history/list.dart';
import 'package:PiliMax/models_new/video/video_detail/dimension.dart';
import 'package:PiliMax/pages/common/multi_select/base.dart';
import 'package:PiliMax/utils/date_utils.dart';
import 'package:PiliMax/utils/duration_utils.dart';
import 'package:PiliMax/utils/download_dialog_utils.dart';
import 'package:PiliMax/utils/id_utils.dart';
import 'package:PiliMax/utils/page_utils.dart';
import 'package:PiliMax/utils/platform_utils.dart';
import 'package:PiliMax/utils/storage_pref.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';

class HistoryItem extends StatelessWidget {
  final HistoryItemModel item;
  final MultiSelectBase ctr;
  final void Function(int kid, String business) onDelete;
  final String heroScope;

  String get _heroTag =>
      '$heroScope-${item.history.business}-${item.history.oid}-'
      '${item.history.cid}-${item.history.page}-${item.kid ?? 'unknown'}';

  const HistoryItem({
    super.key,
    required this.item,
    required this.ctr,
    required this.onDelete,
    this.heroScope = 'history',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasDuration = item.duration != null && item.duration != 0;
    int aid = item.history.oid!;
    String bvid = item.history.bvid ?? IdUtils.av2bv(aid);
    final business = item.history.business;
    final cover = item.cover?.isNotEmpty == true
        ? item.cover
        : item.covers?.firstOrNull ?? '';
    final enableMultiSelect = ctr.enableMultiSelect.value;
    final isDownloadableVideo =
        business != 'pgc' &&
        item.badge != '番剧' &&
        item.tagName?.contains('动画') != true &&
        business != 'live' &&
        business?.contains('article') != true;

    final onLongPress = enableMultiSelect
        ? null
        : () => ctr
            ..enableMultiSelect.value = true
            ..onSelect(item);

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: enableMultiSelect
            ? () => ctr.onSelect(item)
            : () async {
                if (business?.contains('article') == true) {
                  PageUtils.toDupNamed(
                    '/articlePage',
                    parameters: {
                      'id': business == 'article-list'
                          ? '${item.history.cid}'
                          : '${item.history.oid}',
                      'type': 'read',
                    },
                  );
                } else if (business == 'live') {
                  if (item.liveStatus == 1) {
                    PageUtils.toLiveRoom(item.history.oid);
                  } else {
                    SmartDialog.showToast('直播未开播');
                  }
                } else if (business == 'pgc') {
                  PageUtils.viewPgc(
                    epId: item.history.epid,
                    heroTag: _heroTag,
                  );
                } else if (business == 'cheese') {
                  if (item.uri?.isNotEmpty == true) {
                    PageUtils.viewPgcFromUri(
                      item.uri!,
                      isPgc: false,
                      aid: item.history.oid,
                      heroTag: _heroTag,
                    );
                  }
                } else {
                  int? cid = item.history.cid;
                  Dimension? dimension;
                  if (cid == null) {
                    if (await SearchHttp.ab2cWithDimension(
                          aid: aid,
                          bvid: bvid,
                          part: item.history.page,
                        )
                        case final res?) {
                      cid = res.cid;
                      dimension = res.dimension;
                    }
                  }
                  if (cid != null) {
                    // TODO: dimension
                    PageUtils.toVideoPage(
                      aid: aid,
                      bvid: bvid,
                      cid: cid,
                      cover: cover,
                      title: item.title,
                      dimension: dimension,
                      heroTag: _heroTag,
                    );
                  }
                }
              },
        onLongPress: onLongPress,
        onSecondaryTap: PlatformUtils.isMobile ? null : onLongPress,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Padding(
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
                                clip: false,
                                src: cover,
                                width: maxWidth,
                                height: maxHeight,
                              ),
                            ),
                            if (hasDuration)
                              PBadge(
                                text: item.progress == -1
                                    ? '已看完'
                                    : '${DurationUtils.formatDuration(item.progress)}/${DurationUtils.formatDuration(item.duration)}',
                                right: 6.0,
                                bottom: 8.0,
                                type: PBadgeType.gray,
                              ),
                            if (item.isFav == 1)
                              const PBadge(
                                text: '已收藏',
                                top: 6.0,
                                right: 6.0,
                                type: PBadgeType.gray,
                              )
                            else if (item.badge?.isNotEmpty == true)
                              PBadge(
                                text: item.badge,
                                top: 6.0,
                                right: 6.0,
                                type: business == 'live' && item.liveStatus != 1
                                    ? PBadgeType.gray
                                    : PBadgeType.primary,
                              ),
                            if (hasDuration &&
                                item.progress != null &&
                                item.progress != 0)
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 0,
                                child: VideoProgressIndicator(
                                  color: theme.colorScheme.primary,
                                  backgroundColor:
                                      theme.colorScheme.secondaryContainer,
                                  progress: item.progress == -1
                                      ? 1
                                      : item.progress! / item.duration!,
                                ),
                              ),
                            Positioned.fill(
                              child: selectMask(
                                theme.colorScheme,
                                item.checked,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  content(theme),
                ],
              ),
            ),
            Positioned(
              right: 0,
              bottom: -1.5,
              width: 40,
              height: 40,
              child: StaticPopupMenuButton(
                padding: EdgeInsets.zero,
                tooltip: '功能菜单',
                icon: Icon(
                  Icons.more_vert_outlined,
                  color: theme.colorScheme.outline,
                  size: 18,
                ),
                style: IconButton.styleFrom(
                  fixedSize: const Size.square(40),
                  minimumSize: const Size.square(40),
                  padding: EdgeInsets.zero,
                ),
                itemBuilder: (_) => [
                  if (item.authorMid != null &&
                      item.authorName?.isNotEmpty == true)
                    PopupMenuItem(
                      onTap: () => Get.toNamed('/member?mid=${item.authorMid}'),
                      height: 38,
                      child: Row(
                        children: [
                          const Icon(MdiIcons.accountCircleOutline, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            '访问：${item.authorName}',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  if (isDownloadableVideo)
                    PopupMenuItem(
                      onTap: () =>
                          UserHttp.toViewLater(bvid: item.history.bvid),
                      height: 38,
                      child: const Row(
                        children: [
                          Icon(Icons.watch_later_outlined, size: 16),
                          SizedBox(width: 6),
                          Text('稍后再看', style: TextStyle(fontSize: 13)),
                        ],
                      ),
                    ),
                  if (Pref.showMoreDownloadButtons && isDownloadableVideo)
                    PopupMenuItem(
                      onTap: () =>
                          DownloadDialogUtils.confirmAndDownloadByIdentifiers(
                            context,
                            cid: item.history.cid,
                            aid: aid,
                            bvid: bvid,
                            part: item.history.page,
                            totalTimeMilli: (item.duration ?? 0) * 1000,
                            title: item.title,
                            cover: cover,
                            ownerId: item.authorMid,
                            ownerName: item.authorName,
                          ),
                      height: 38,
                      child: const Row(
                        children: [
                          Icon(MdiIcons.folderDownloadOutline, size: 16),
                          SizedBox(width: 6),
                          Text('离线缓存', style: TextStyle(fontSize: 13)),
                        ],
                      ),
                    ),
                  PopupMenuItem(
                    onTap: () => onDelete(item.kid!, business!),
                    height: 38,
                    child: const Row(
                      children: [
                        Icon(Icons.close_outlined, size: 16),
                        SizedBox(width: 6),
                        Text('删除记录', style: TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget content(ThemeData theme) {
    return Expanded(
      child: Column(
        spacing: 2,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.title!,
            style: TextStyle(
              fontSize: theme.textTheme.bodyMedium!.fontSize,
              height: 1.42,
              letterSpacing: 0.3,
            ),
            maxLines: item.videos! > 1 ? 1 : 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (item.history.business == 'pgc' &&
              item.showTitle?.isNotEmpty == true)
            Text(
              item.showTitle!,
              style: TextStyle(fontSize: 13, color: theme.colorScheme.outline),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          const Spacer(),
          if (item.authorName?.isNotEmpty == true)
            Text(
              item.authorName!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: theme.textTheme.labelMedium!.fontSize,
                color: theme.colorScheme.outline,
              ),
            ),
          Text(
            DateFormatUtils.chatFormat(item.viewAt!, isHistory: true),
            style: TextStyle(
              fontSize: theme.textTheme.labelMedium!.fontSize,
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}
