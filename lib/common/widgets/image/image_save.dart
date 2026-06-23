import 'package:PiliMax/common/style.dart';
import 'package:PiliMax/common/widgets/button/icon_button.dart';
import 'package:PiliMax/common/widgets/image/network_img_layer.dart';
import 'package:PiliMax/http/user.dart';
import 'package:PiliMax/utils/date_utils.dart';
import 'package:PiliMax/utils/image_utils.dart';
import 'package:PiliMax/utils/num_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
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
  SmartDialog.show(
    animationType: SmartAnimationType.centerScale_otherSlide,
    backType: SmartBackType.normal,
    useSystem: true,
    builder: (context) {
      const iconSize = 20.0;
      final theme = Theme.of(context);
      final coverUrl = cover;
      final publishTimeText = pubdateText?.trim();
      final metaItems = <String>[
        if (publishTimeText?.isNotEmpty == true)
          '发布 $publishTimeText'
        else if (pubdate != null && pubdate > 0)
          '发布 ${DateFormatUtils.format(pubdate)}',
        if (view != null) '播放 ${NumUtils.numFormat(view)}',
        if (danmaku != null) '弹幕 ${NumUtils.numFormat(danmaku)}',
        if (like != null) '点赞 ${NumUtils.numFormat(like)}',
        if (favorite != null) '收藏 ${NumUtils.numFormat(favorite)}',
        if (ownerName?.isNotEmpty == true) 'UP $ownerName',
      ];
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
                  onTap: SmartDialog.dismiss,
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
                        backgroundColor: Colors.black.withValues(alpha: 0.3),
                      ),
                      onPressed: () async {
                        final saveStatus = await ImageUtils.downloadImg([
                          coverUrl,
                        ]);
                        if (saveStatus) {
                          SmartDialog.dismiss();
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
                    onPressed: SmartDialog.dismiss,
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
                            SmartDialog.dismiss(),
                            UserHttp.toViewLater(aid: aid, bvid: bvid),
                          },
                          icon: const Icon(Icons.watch_later_outlined),
                        ),
                    ],
                  ),
                  if (metaItems.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      children: metaItems
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
  );
}
