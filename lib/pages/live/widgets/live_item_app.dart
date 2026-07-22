import 'package:PiliMax/common/style.dart';
import 'package:PiliMax/common/widgets/image/image_save.dart';
import 'package:PiliMax/common/widgets/image/network_img_layer.dart';
import 'package:PiliMax/http/live.dart';
import 'package:PiliMax/models_new/live/live_feed_index/card_data_list_item.dart';
import 'package:PiliMax/models_new/live/live_feed_index/feedback.dart'
    as live_feedback;
import 'package:PiliMax/pages/search/widgets/search_text.dart';
import 'package:PiliMax/utils/page_utils.dart';
import 'package:PiliMax/utils/platform_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

// 视频卡片 - 垂直布局
class LiveCardVApp extends StatelessWidget {
  final CardLiveItem item;
  final bool showFirstFrame;

  const LiveCardVApp({
    super.key,
    required this.item,
    this.showFirstFrame = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roomId = item.roomid;
    final feedbackGroups =
        item.feedback
            ?.where(
              (group) =>
                  group.reasons?.any(_isValidFeedbackReason) == true,
            )
            .toList(growable: false) ??
        const <live_feedback.Feedback>[];
    void onLongPress() => imageSaveDialog(
      title: item.title,
      cover: showFirstFrame ? item.systemCover : item.cover,
    );
    return Stack(
      children: [
        Card(
          clipBehavior: Clip.hardEdge,
          child: InkWell(
            onTap: () => PageUtils.toLiveRoom(item.roomid),
            onLongPress: onLongPress,
            onSecondaryTap: PlatformUtils.isMobile ? null : onLongPress,
            child: Column(
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
                            src: showFirstFrame
                                ? item.systemCover
                                : item.cover,
                            width: maxWidth,
                            height: maxHeight,
                            type: .emote,
                          ),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: AnimatedOpacity(
                              opacity: 1,
                              duration: const Duration(milliseconds: 200),
                              child: videoStat(context),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                liveContent(context),
              ],
            ),
          ),
        ),
        if (roomId != null && feedbackGroups.isNotEmpty)
          Positioned(
            right: -5,
            bottom: -2,
            width: 29,
            height: 29,
            child: IconButton(
              padding: .zero,
              onPressed: () {
                Widget actionButton(live_feedback.Reason reason) {
                  final id = reason.id;
                  final name = reason.name?.trim();
                  final idType = reason.idType?.trim();
                  if (id == null ||
                      name == null ||
                      name.isEmpty ||
                      idType == null ||
                      idType.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return SearchText(
                    text: name,
                    onTap: (_) async {
                      Get.back();
                      SmartDialog.showLoading(msg: '正在提交');
                      final res = await LiveHttp.liveFeedback(
                        roomId,
                        id,
                        idType,
                      );
                      SmartDialog.dismiss();
                      if (res.isSuccess) {
                        SmartDialog.showToast('提交成功');
                      } else {
                        res.toast();
                      }
                    },
                  );
                }

                showDialog(
                  context: context,
                  builder: (context) {
                    return SimpleDialog(
                      contentPadding: const .fromLTRB(24, 16, 24, 19),
                      children: [
                        for (final group in feedbackGroups) ...[
                          const SizedBox(height: 5),
                          _feedbackHeader(theme, group),
                          const SizedBox(height: 5),
                          Wrap(
                            spacing: 8.0,
                            runSpacing: 8.0,
                            children:
                                (group.reasons ??
                                    const <live_feedback.Reason>[])
                                .where(_isValidFeedbackReason)
                                .map(actionButton)
                                .toList(),
                          ),
                        ],
                        const Divider(),
                        Center(
                          child: FilledButton.tonal(
                            onPressed: Get.back,
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                            ),
                            child: const Text('取消'),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
              icon: Icon(
                Icons.more_vert_outlined,
                size: 17,
                color: theme.colorScheme.outline,
              ),
            ),
          ),
      ],
    );
  }

  static bool _isValidFeedbackReason(live_feedback.Reason reason) =>
      reason.id != null &&
      reason.name?.trim().isNotEmpty == true &&
      reason.idType?.trim().isNotEmpty == true;

  static Widget _feedbackHeader(
    ThemeData theme,
    live_feedback.Feedback feedback,
  ) {
    final title = feedback.title?.trim() ?? '';
    final subtitle = feedback.subtitle?.trim() ?? '';
    if (title.isEmpty && subtitle.isEmpty) {
      return const SizedBox.shrink();
    }
    return Text.rich(
      TextSpan(
        children: [
          if (title.isNotEmpty)
            TextSpan(text: title, style: theme.textTheme.titleMedium),
          if (subtitle.isNotEmpty)
            TextSpan(
              text: '${title.isNotEmpty ? '\n' : ''}$subtitle',
              style: TextStyle(color: theme.colorScheme.outline),
            ),
        ],
      ),
    );
  }

  Widget liveContent(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      flex: 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(5, 8, 5, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${item.title}',
              textAlign: TextAlign.start,
              style: const TextStyle(
                letterSpacing: 0.3,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${item.uname}',
                    textAlign: TextAlign.start,
                    style: TextStyle(
                      fontSize: theme.textTheme.labelMedium!.fontSize,
                      color: theme.colorScheme.outline,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget videoStat(BuildContext context) {
    return Container(
      height: 50,
      padding: const EdgeInsets.only(top: 26, left: 10, right: 10),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Colors.transparent,
            Colors.black54,
          ],
          tileMode: TileMode.mirror,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '${item.areaName}',
            style: const TextStyle(fontSize: 11, color: Colors.white),
          ),
          if (item.watchedShow?.textLarge case final textLarge?)
            Text(
              textLarge,
              style: const TextStyle(fontSize: 11, color: Colors.white),
            ),
        ],
      ),
    );
  }
}
