import 'package:PiliMax/common/style.dart';
import 'package:PiliMax/common/widgets/button/icon_button.dart';
import 'package:PiliMax/common/widgets/image/network_img_layer.dart';
import 'package:PiliMax/http/loading_state.dart';
import 'package:PiliMax/http/video.dart';
import 'package:PiliMax/models_new/video/video_detail/data.dart';
import 'package:PiliMax/http/user.dart';
import 'package:PiliMax/utils/date_utils.dart';
import 'package:PiliMax/utils/id_utils.dart';
import 'package:PiliMax/utils/image_utils.dart';
import 'package:PiliMax/utils/num_utils.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

void imageSaveDialog({
  required String? title,
  required String? cover,
  dynamic aid,
  String? bvid,
  int? pubdate,
  String? pubdateText,
  dynamic view,
  dynamic danmaku,
  dynamic like,
  dynamic favorite,
  String? ownerName,
}) {
  final double imgWidth = MediaQuery.sizeOf(Get.context!).shortestSide - 16;
  final previewMetaFuture = _resolvePreviewMeta(
    aid: aid,
    bvid: bvid,
    pubdate: pubdate,
    pubdateText: pubdateText,
    view: view,
    danmaku: danmaku,
    like: like,
    favorite: favorite,
    ownerName: ownerName,
  );
  showDialog(
    context: Get.context!,
    builder: (context) {
      const iconSize = 20.0;
      final theme = Theme.of(context);
      final coverUrl = cover;
      void dismissDialog() => Navigator.of(context).pop();

      return Center(
        child: Material(
          color: Colors.transparent,
          child: FutureBuilder<_PreviewMeta>(
            future: previewMetaFuture,
            builder: (context, snapshot) {
          final meta = snapshot.data ??
              _PreviewMeta.fromFallback(
                pubdate: pubdate,
                pubdateText: pubdateText,
                view: view,
                danmaku: danmaku,
                like: like,
                favorite: favorite,
                ownerName: ownerName,
              );
          return Container(
            width: imgWidth,
            margin: const .symmetric(horizontal: Style.safeSpace),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: Style.mdRadius,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    GestureDetector(
                      onTap: dismissDialog,
                      child: NetworkImgLayer(
                        src: cover,
                        quality: 100,
                        width: imgWidth,
                        height: imgWidth / Style.aspectRatio16x9,
                        borderRadius: const .vertical(top: Style.imgRadius),
                      ),
                    ),
                    if (coverUrl != null && coverUrl.isNotEmpty)
                      Positioned(
                        left: 8,
                        top: 8,
                        width: 30,
                        height: 30,
                        child: IconButton(
                          tooltip: '保存封面图',
                          style: IconButton.styleFrom(
                            padding: .zero,
                            backgroundColor: Colors.black.withValues(
                              alpha: 0.3,
                            ),
                          ),
                          onPressed: () async {
                            final saveStatus = await ImageUtils.downloadImg([
                              coverUrl,
                            ]);
                            if (saveStatus && context.mounted) {
                              dismissDialog();
                            }
                          },
                          icon: const Icon(
                            Icons.download,
                            size: 18,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    Positioned(
                      right: 8,
                      top: 8,
                      width: 30,
                      height: 30,
                      child: IconButton(
                        tooltip: '关闭',
                        style: IconButton.styleFrom(
                          padding: .zero,
                          backgroundColor: Colors.black.withValues(alpha: 0.3),
                        ),
                        onPressed: dismissDialog,
                        icon: const Icon(
                          Icons.close,
                          size: 18,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (title != null)
                            Expanded(
                              child: SelectableText(
                                title,
                                style: theme.textTheme.titleSmall,
                              ),
                            )
                          else
                            const Spacer(),
                          if (aid != null || bvid != null)
                            iconButton(
                              iconSize: iconSize,
                              tooltip: '稍后再看',
                              onPressed: () => {
                                dismissDialog(),
                                UserHttp.toViewLater(aid: aid, bvid: bvid),
                              },
                              icon: const Icon(Icons.watch_later_outlined),
                            ),
                        ],
                      ),
                      if (meta.items.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 10,
                          runSpacing: 4,
                          children: meta.items
                              .map(
                                (item) => Text(
                                  item,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: theme.colorScheme.outline,
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
            },
          ),
        ),
      );
    },
  );
}

Future<_PreviewMeta> _resolvePreviewMeta({
  dynamic aid,
  String? bvid,
  int? pubdate,
  String? pubdateText,
  dynamic view,
  dynamic danmaku,
  dynamic like,
  dynamic favorite,
  String? ownerName,
}) async {
  final fallback = _PreviewMeta.fromFallback(
    pubdate: pubdate,
    pubdateText: pubdateText,
    view: view,
    danmaku: danmaku,
    like: like,
    favorite: favorite,
    ownerName: ownerName,
  );
  final resolvedBvid = _resolveBvid(aid: aid, bvid: bvid);
  if (resolvedBvid == null || !fallback.needsRefresh) {
    return fallback;
  }
  final res = await VideoHttp.videoIntro(bvid: resolvedBvid);
  if (res case Success(:final response)) {
    final stat = response.stat;
    final resolvedOwner = response.owner?.name?.trim();
    return _PreviewMeta(
      pubdateText: response.pubdate == null
          ? fallback.pubdateText
          : DateFormatUtils.dateFormat(response.pubdate),
      view: stat?.view ?? fallback.view,
      danmaku: stat?.danmaku ?? fallback.danmaku,
      like: stat?.like ?? fallback.like,
      favorite: stat?.favorite ?? fallback.favorite,
      ownerName: resolvedOwner?.isNotEmpty == true
          ? resolvedOwner
          : fallback.ownerName,
    );
  }
  return fallback;
}

String? _resolveBvid({dynamic aid, String? bvid}) {
  final resolvedBvid = bvid?.trim();
  if (resolvedBvid?.isNotEmpty == true) {
    return resolvedBvid;
  }
  if (aid is int) {
    return IdUtils.av2bv(aid);
  }
  final resolvedAid = int.tryParse(aid?.toString() ?? '');
  if (resolvedAid != null) {
    return IdUtils.av2bv(resolvedAid);
  }
  return null;
}

class _PreviewMeta {
  final String? pubdateText;
  final dynamic view;
  final dynamic danmaku;
  final dynamic like;
  final dynamic favorite;
  final String? ownerName;

  const _PreviewMeta({
    this.pubdateText,
    this.view,
    this.danmaku,
    this.like,
    this.favorite,
    this.ownerName,
  });

  bool get needsRefresh =>
      pubdateText == null ||
      view == null ||
      danmaku == null ||
      like == null ||
      favorite == null ||
      ownerName == null;

  factory _PreviewMeta.fromFallback({
    int? pubdate,
    String? pubdateText,
    dynamic view,
    dynamic danmaku,
    dynamic like,
    dynamic favorite,
    String? ownerName,
  }) {
    final normalizedPubdateText = pubdateText?.trim();
    return _PreviewMeta(
      pubdateText: normalizedPubdateText?.isNotEmpty == true
          ? normalizedPubdateText
          : pubdate != null && pubdate > 0
          ? DateFormatUtils.format(pubdate)
          : null,
      view: view,
      danmaku: danmaku,
      like: like,
      favorite: favorite,
      ownerName: ownerName?.trim().isNotEmpty == true ? ownerName!.trim() : null,
    );
  }

  List<String> get items => [
    if (pubdateText?.isNotEmpty == true) '发布 $pubdateText',
    if (view != null) '播放 ${NumUtils.numFormat(view)}',
    if (danmaku != null) '弹幕 ${NumUtils.numFormat(danmaku)}',
    if (like != null) '点赞 ${NumUtils.numFormat(like)}',
    if (favorite != null) '收藏 ${NumUtils.numFormat(favorite)}',
    if (ownerName?.isNotEmpty == true) 'UP $ownerName',
  ];
}
