import 'dart:convert';
import 'dart:math' as math;

import 'package:PiliMax/common/constants.dart';
import 'package:PiliMax/common/style.dart';
import 'package:PiliMax/common/widgets/badge.dart';
import 'package:PiliMax/common/widgets/gesture/tap_gesture_recognizer.dart';
import 'package:PiliMax/common/widgets/image/network_img_layer.dart';
import 'package:PiliMax/common/widgets/image_viewer/hero.dart';
import 'package:PiliMax/common/widgets/video_card/video_detail_hero.dart';
import 'package:PiliMax/grpc/bilibili/im/interfaces/v1.pb.dart'
    show EmotionInfo;
import 'package:PiliMax/grpc/bilibili/im/type.pb.dart' show Msg, MsgType;
import 'package:PiliMax/models/common/badge_type.dart';
import 'package:PiliMax/models/common/image_preview_type.dart';
import 'package:PiliMax/models/common/image_type.dart';
import 'package:PiliMax/utils/app_scheme.dart';
import 'package:PiliMax/utils/date_utils.dart';
import 'package:PiliMax/utils/duration_utils.dart';
import 'package:PiliMax/utils/extension/num_ext.dart';
import 'package:PiliMax/utils/id_utils.dart';
import 'package:PiliMax/utils/image_utils.dart';
import 'package:PiliMax/utils/page_utils.dart';
import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

class ChatItem extends StatelessWidget {
  static MsgType msgTypeFromValue(int value) {
    return MsgType.valueOf(value) ?? MsgType.EN_INVALID_MSG_TYPE;
  }

  const ChatItem({
    super.key,
    required this.item,
    required this.index,
    required this.eInfos,
    required this.onLongPress,
    required this.onSecondaryTapUp,
    required this.isOwner,
  });

  final Msg item;
  final int index;
  final List<EmotionInfo>? eInfos;
  final VoidCallback onLongPress;
  final GestureTapUpCallback? onSecondaryTapUp;
  final bool isOwner;

  String get _messageHeroKey {
    if (item.hasMsgKey()) {
      return item.msgKey.toString();
    }
    if (item.hasMsgSeqno()) {
      return '${item.receiverId}-${item.msgSeqno}';
    }
    if (item.hasCliMsgId()) {
      return item.cliMsgId.toString();
    }
    return '${item.senderUid}-${item.receiverId}-${item.timestamp}-'
        '${item.msgType}-${_stableContentHash(item.content)}-$index';
  }

  String _videoHeroTag(Object? source, Object? suffix) =>
      'chat-video-$_messageHeroKey-${source ?? item.msgType}-$suffix';

  static String _stableContentHash(String value) {
    var hash = 0;
    for (final codeUnit in value.codeUnits) {
      hash = 0x3fffffff & ((hash * 31) + codeUnit);
    }
    return hash.toRadixString(16);
  }

  // 消息来源
  // enum MsgSource {
  //     EN_MSG_SOURCE_AUTOREPLY_BY_FOLLOWED    = 8;  //
  //     EN_MSG_SOURCE_AUTOREPLY_BY_RECEIVE_MSG = 9;  //
  //     EN_MSG_SOURCE_AUTOREPLY_BY_KEYWORDS    = 10; //
  //     EN_MSG_SOURCE_AUTOREPLY_BY_VOYAGE      = 11; //
  // };
  @override
  Widget build(BuildContext context) {
    final msgType = item.msgType;
    // final isRevoke = msgType == MsgType.EN_MSG_TYPE_DRAW_BACK.value; // 撤回消息
    // if (isRevoke) {
    //   return const SizedBox.shrink();
    // }

    late final ThemeData theme = Theme.of(context);
    late final Color textColor = isOwner
        ? theme.colorScheme.onSecondaryContainer
        : theme.colorScheme.onSurfaceVariant;
    late final dynamic content = jsonDecode(item.content);

    Widget child = messageContent(
      context: context,
      theme: theme,
      content: content,
      textColor: textColor,
    );

    final isSystem =
        msgType == MsgType.EN_MSG_TYPE_VIDEO_CARD.value ||
        msgType == MsgType.EN_MSG_TYPE_TIP_MESSAGE.value ||
        msgType == MsgType.EN_MSG_TYPE_NOTIFY_MSG.value ||
        msgType == MsgType.EN_MSG_TYPE_PICTURE_CARD.value ||
        msgType == 16;

    if (!isSystem) {
      final isPic = msgType == MsgType.EN_MSG_TYPE_PIC.value; // 图片
      child = Row(
        mainAxisAlignment: isOwner ? .end : .start,
        children: [
          Container(
            constraints: const BoxConstraints(maxWidth: 300.0),
            decoration: BoxDecoration(
              color: isOwner
                  ? theme.colorScheme.secondaryContainer
                  : theme.colorScheme.onInverseSurface,
              borderRadius: isOwner
                  ? const .only(
                      topLeft: .circular(16),
                      topRight: .circular(16),
                      bottomLeft: .circular(16),
                      bottomRight: .circular(6),
                    )
                  : const .only(
                      topLeft: .circular(16),
                      topRight: .circular(16),
                      bottomLeft: .circular(6),
                      bottomRight: .circular(16),
                    ),
            ),
            padding: isPic
                ? const .only(top: 8, bottom: 6, left: 8, right: 8)
                : const .only(top: 8, bottom: 6, left: 12, right: 12),
            child: Column(
              crossAxisAlignment: isOwner ? .end : .start,
              children: [
                child,
                isPic ? const SizedBox(height: 7) : const SizedBox(height: 2),
                if (item.msgStatus == 1)
                  Text(
                    '  已撤回',
                    style: theme.textTheme.labelSmall!.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                if (item.msgSource >= 8 && item.msgSource <= 11) ...[
                  Divider(
                    height: 10,
                    thickness: 1,
                    color: theme.colorScheme.outline.withValues(alpha: 0.2),
                  ),
                  Text(
                    '此条消息为自动回复',
                    style: theme.textTheme.labelMedium!.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 18),
          child: Text(
            DateFormatUtils.chatFormat(item.timestamp.toInt()),
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.colorScheme.outline),
          ),
        ),
        GestureDetector(
          behavior: .opaque,
          onLongPress: onLongPress,
          onSecondaryTapUp: onSecondaryTapUp,
          child: child,
        ),
      ],
    );
  }

  Widget messageContent({
    required BuildContext context,
    required ThemeData theme,
    required dynamic content,
    required Color textColor,
  }) {
    try {
      switch (msgTypeFromValue(item.msgType)) {
        case MsgType.EN_MSG_TYPE_NOTIFY_MSG:
          return msgTypeNotifyMsg_10(theme, content);
        case MsgType.EN_MSG_TYPE_PICTURE_CARD:
          return msgTypePictureCard_13(content);
        case MsgType.EN_MSG_TYPE_TIP_MESSAGE:
          return msgTypeTipMessage_18(theme, content);
        case MsgType.EN_MSG_TYPE_TEXT:
          return msgTypeText_1(theme, content: content, textColor: textColor);
        case MsgType.EN_MSG_TYPE_PIC || MsgType.EN_MSG_TYPE_CUSTOM_FACE:
          return msgTypePic_2(content);
        case MsgType.EN_MSG_TYPE_SHARE_V2:
          return msgTypeShareV2_7(content, textColor);
        case MsgType.EN_MSG_TYPE_VIDEO_CARD:
          return msgTypeVideoCard_11(theme, content, textColor);
        case MsgType.EN_MSG_TYPE_ARTICLE_CARD:
          return msgTypeArticleCard_12(content, textColor);
        case MsgType.EN_MSG_TYPE_COMMON_SHARE_CARD:
          return msgTypeCommonShareCard_14(content, textColor);
        default:
          if (item.msgType == 16) {
            return msgType_16(theme, content, textColor);
          }
          return def(textColor);
      }
    } catch (err) {
      return def(textColor, err: err);
    }
  }

  Widget msgTypeCommonShareCard_14(dynamic content, Color textColor) {
    if (content['source'] == '直播') {
      return GestureDetector(
        behavior: .opaque,
        onTap: () {
          dynamic roomId = content['sourceID'];
          if (roomId is String) {
            roomId = int.parse(roomId);
          }
          PageUtils.toLiveRoom(roomId);
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NetworkImgLayer(
              width: 220,
              height: 123.75,
              src: content['cover'],
            ),
            const SizedBox(height: 6),
            Text(
              content['title'] ?? "",
              style: TextStyle(
                letterSpacing: 0.6,
                height: 1.5,
                color: textColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              '${content['author']} · 直播',
              style: TextStyle(
                letterSpacing: 0.6,
                height: 1.5,
                color: textColor.withValues(alpha: 0.6),
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    } else {
      return def(textColor);
    }
  }

  Widget msgTypeArticleCard_12(dynamic content, Color textColor) {
    return GestureDetector(
      behavior: .opaque,
      onTap: () => Get.toNamed(
        '/articlePage',
        parameters: {
          'id': '${content['rid']}',
          'type': "read",
        },
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (final i in content['image_urls'])
                NetworkImgLayer(
                  width: 130,
                  height: 73.125,
                  src: i,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            content['title'] ?? "",
            style: TextStyle(
              letterSpacing: 0.6,
              height: 1.5,
              color: textColor,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (content['summary'] != null && content['summary'] != '') ...[
            const SizedBox(height: 1),
            Text(
              content['summary'],
              style: TextStyle(
                letterSpacing: 0.6,
                height: 1.5,
                color: textColor.withValues(alpha: 0.6),
                fontSize: 12,
                overflow: TextOverflow.ellipsis,
              ),
              maxLines: 2,
            ),
          ],
        ],
      ),
    );
  }

  Widget msgType_16(ThemeData theme, content, Color textColor) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        decoration: BoxDecoration(
          color: theme.colorScheme.onInverseSurface,
          borderRadius: const BorderRadius.all(Radius.circular(16)),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 6,
          children: [
            Text(
              content['main_title'],
              style: TextStyle(
                letterSpacing: 0.6,
                height: 1.5,
                color: textColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            for (final (subCardIndex, i)
                in (content['sub_cards'] as Iterable).indexed)
              _msgType16SubCard(theme, i, subCardIndex, textColor),
          ],
        ),
      ),
    );
  }

  Widget _msgType16SubCard(
    ThemeData theme,
    dynamic content,
    int subCardIndex,
    Color textColor,
  ) {
    final jumpUrl = content['jump_url'];
    final bvid = jumpUrl is String
        ? IdUtils.bvRegex.firstMatch(jumpUrl)?.group(0)
        : null;
    final heroTag = _videoHeroTag(
      jumpUrl ?? content['cover_url'],
      subCardIndex,
    );
    final cover = NetworkImgLayer(
      clip: false,
      width: 130,
      height: 73.125,
      src: content['cover_url'],
    );
    final card = ColoredBox(
      color: theme.colorScheme.onInverseSurface,
      child: Row(
        spacing: 6,
        children: [
          bvid == null
              ? cover
              : VideoDetailHero.source(
                  borderRadius: BorderRadius.zero,
                  child: cover,
                ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (bvid == null)
                  Text(
                    content['field1'],
                    maxLines: 2,
                    style: TextStyle(
                      letterSpacing: 0.6,
                      height: 1.5,
                      color: textColor,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                else
                  VideoDetailTransitionTitle(
                    text: '${content['field1'] ?? ''}',
                    style: TextStyle(
                      letterSpacing: 0.6,
                      height: 1.5,
                      color: textColor,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 2,
                    child: Text(
                      content['field1'],
                      maxLines: 2,
                      style: TextStyle(
                        letterSpacing: 0.6,
                        height: 1.5,
                        color: textColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                Text(
                  content['field2'],
                  style: TextStyle(
                    letterSpacing: 0.6,
                    height: 1.5,
                    color: textColor.withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                ),
                Text(
                  content['field3'],
                  style: TextStyle(
                    letterSpacing: 0.6,
                    height: 1.5,
                    color: textColor.withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    final tappable = GestureDetector(
      onTap: () {
        if (bvid != null) {
          PageUtils.toVideoPage(
            bvid: bvid,
            cid: null,
            cover: content['cover_url'],
            heroTag: heroTag,
          );
          return;
        }
        SmartDialog.showToast('未匹配到 BV 号');
        if (jumpUrl is String) {
          PageUtils.handleWebview(jumpUrl);
        }
      },
      child: card,
    );
    return bvid == null
        ? tappable
        : VideoDetailTransitionSource(
            tag: heroTag,
            layout: VideoTransitionSourceLayout.embedded,
            borderRadius: BorderRadius.zero,
            child: tappable,
          );
  }

  Widget msgTypeVideoCard_11(ThemeData theme, content, Color textColor) {
    String? attachMsg;
    try {
      attachMsg = content['attach_msg']?['content'];
    } catch (_) {}
    final heroTag = _videoHeroTag(content['bvid'] ?? content['cover'], 'card');

    return Center(
      child: VideoDetailTransitionSource(
        tag: heroTag,
        layout: VideoTransitionSourceLayout.embedded,
        child: Container(
          clipBehavior: Clip.hardEdge,
          constraints: const BoxConstraints(maxWidth: 400.0),
          decoration: BoxDecoration(
            borderRadius: Style.mdRadius,
            color: theme.colorScheme.onInverseSurface,
          ),
          child: LayoutBuilder(
            builder: (_, constrains) {
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  final bvid = content['bvid'];
                  if (bvid is! String || bvid.isEmpty) {
                    SmartDialog.showToast('未匹配到 BV 号');
                    return;
                  }
                  PageUtils.toVideoPage(
                    bvid: bvid,
                    cid: null,
                    cover: content['cover'],
                    heroTag: heroTag,
                  );
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    VideoDetailHero.source(
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          NetworkImgLayer(
                            clip: false,
                            width: constrains.maxWidth,
                            height: constrains.maxWidth / Style.aspectRatio16x9,
                            src: content['cover'],
                          ),
                          PBadge(
                            left: 6,
                            bottom: 6,
                            type: PBadgeType.gray,
                            text: content['times'] == 0
                                ? '--:--'
                                : DurationUtils.formatDuration(
                                    content['times'],
                                  ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: VideoDetailTransitionTitle(
                        text:
                            '${content['times'] == 0 ? '内容已失效' : content['title'] ?? ''}',
                        style: TextStyle(
                          letterSpacing: 0.6,
                          height: 1.5,
                          color: textColor,
                          fontWeight: FontWeight.bold,
                        ),
                        child: Text(
                          content['times'] == 0 ? '内容已失效' : content['title'],
                          style: TextStyle(
                            letterSpacing: 0.6,
                            height: 1.5,
                            color: textColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    if (attachMsg?.isNotEmpty ?? false)
                      Container(
                        margin: const .fromLTRB(12, 0, 12, 8),
                        padding: const .symmetric(
                          horizontal: 11,
                          vertical: 3.5,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius: const .all(.circular(6)),
                        ),
                        child: msgTypeText_1(
                          theme,
                          content: content['attach_msg'],
                          textColor: textColor,
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget msgTypeShareV2_7(dynamic content, Color textColor) {
    String? type;
    String? heroTag;
    GestureTapCallback onTap;
    switch (content['source']) {
      // album
      case 2:
        type = '相簿';
        onTap = () => PageUtils.pushDynFromId(rid: content['id']);
        break;

      // video
      case 5:
        heroTag = _videoHeroTag(
          content['bvid'] ?? content['id'] ?? content['thumb'],
          'share',
        );
        type = '视频';
        onTap = () {
          final rawAid = content['id'];
          final aid = rawAid is int ? rawAid : int.tryParse('$rawAid');
          final rawBvid = content['bvid'];
          final bvid = rawBvid is String && rawBvid.isNotEmpty ? rawBvid : null;
          if (aid == null && bvid == null) {
            SmartDialog.showToast('null');
            return;
          }
          PageUtils.toVideoPage(
            aid: aid,
            bvid: bvid,
            cid: null,
            cover: content['thumb'],
            heroTag: heroTag,
          );
        };
        break;

      // article
      case 6:
        type = '专栏';
        onTap = () => Get.toNamed(
          '/articlePage',
          parameters: {
            'id': '${content['id']}',
            'type': 'read',
          },
        );
        break;

      // dynamic
      case 11:
        type = '动态';
        onTap = () => PageUtils.pushDynFromId(id: content['id']);
        break;

      // pgc
      case 16:
        heroTag = _videoHeroTag(
          content['id'] ?? content['season_id'] ?? content['thumb'],
          'pgc-share',
        );
        onTap = () => PageUtils.viewPgc(
          epId: content['id'],
          heroTag: heroTag,
          cover: content['thumb'],
          title: content['title'],
        );
        break;

      default:
        onTap = () => SmartDialog.showToast(
          'unsupported source type: ${content['source']}',
        );
    }
    final activeHeroTag = heroTag;
    final cover = NetworkImgLayer(
      clip: false,
      width: 220,
      height: 123.75,
      src: content['thumb'],
    );
    final card = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        activeHeroTag == null ? cover : VideoDetailHero.source(child: cover),
        const SizedBox(height: 6),
        activeHeroTag == null
            ? Text(
                content['title'] ?? "",
                style: TextStyle(
                  letterSpacing: 0.6,
                  height: 1.5,
                  color: textColor,
                  fontWeight: FontWeight.bold,
                ),
              )
            : VideoDetailTransitionTitle(
                text: '${content['title'] ?? ''}',
                style: TextStyle(
                  letterSpacing: 0.6,
                  height: 1.5,
                  color: textColor,
                  fontWeight: FontWeight.bold,
                ),
                child: Text(
                  content['title'] ?? "",
                  style: TextStyle(
                    letterSpacing: 0.6,
                    height: 1.5,
                    color: textColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
        if (content['source'] == 6 &&
            (content['headline'] as String?)?.isNotEmpty == true) ...[
          const SizedBox(height: 1),
          Text(
            content['headline'],
            style: TextStyle(
              letterSpacing: 0.6,
              height: 1.5,
              color: textColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
        if (content['author'] != null) ...[
          const SizedBox(height: 1),
          Text(
            '${content['author']}${type != null ? ' · $type' : ''}',
            style: TextStyle(
              letterSpacing: 0.6,
              height: 1.5,
              color: textColor.withValues(alpha: 0.6),
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
    return GestureDetector(
      onTap: onTap,
      behavior: .opaque,
      child: activeHeroTag == null
          ? card
          : VideoDetailTransitionSource(
              tag: activeHeroTag,
              layout: VideoTransitionSourceLayout.embedded,
              child: card,
            ),
    );
  }

  Widget msgTypePic_2(Map content) {
    final url = content['url'];
    final imgWidth = (content['width'] as num).toDouble();
    final imgHeight = (content['height'] as num).toDouble();
    final width = math.min(220.0, imgWidth);
    final ratio = imgHeight / imgWidth;
    Widget child = NetworkImgLayer(
      width: width,
      height: width * ratio,
      src: url,
    );
    if (ratio <= Style.imgMaxRatio) {
      child = fromHero(
        tag: url,
        child: child,
      );
    }
    return GestureDetector(
      onTap: () => PageUtils.imageView(imgList: [SourceModel(url: url)]),
      child: child,
    );
  }

  Widget msgTypeTipMessage_18(ThemeData theme, content) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Text(
        jsonDecode(content['content']).map((e) => e['text']).join("\n"),
        textAlign: TextAlign.center,
        style: TextStyle(
          height: 1.5,
          letterSpacing: 0.6,
          color: theme.colorScheme.outline.withValues(alpha: 0.8),
        ),
      ),
    );
  }

  Widget msgTypeText_1(
    ThemeData theme, {
    required dynamic content,
    required Color textColor,
  }) {
    final style = TextStyle(color: textColor, letterSpacing: 0.6, height: 1.5);
    final List<InlineSpan> children = [];
    late final Map<String, Map> emojiMap = {};
    final List<String> patterns = [Constants.urlRegex.pattern];
    if (eInfos != null) {
      for (final e in eInfos!) {
        emojiMap[e.text] ??= {
          'url': e.hasGifUrl() ? e.gifUrl : e.url,
          'size': e.size * 22.0,
        };
      }
      patterns.addAll(emojiMap.keys.map(RegExp.escape));
    }
    final regex = RegExp(patterns.join('|'));
    content['content'].splitMapJoin(
      regex,
      onMatch: (Match match) {
        final matchStr = match[0]!;
        if (matchStr.startsWith('[')) {
          final emoji = emojiMap[matchStr];
          if (emoji != null) {
            final size = emoji['size'];
            children.add(
              WidgetSpan(
                child: NetworkImgLayer(
                  width: size,
                  height: size,
                  src: emoji['url'],
                  type: ImageType.emote,
                ),
              ),
            );
          } else {
            children.add(TextSpan(text: matchStr, style: style));
          }
        } else {
          children.add(
            TextSpan(
              text: matchStr,
              style: style.copyWith(color: theme.colorScheme.primary),
              recognizer: NoDeadlineTapGestureRecognizer()
                ..onTap = () => PiliScheme.routePushFromUrl(matchStr),
            ),
          );
        }
        return '';
      },
      onNonMatch: (String text) {
        children.add(TextSpan(text: text, style: style));
        return '';
      },
    );
    return SelectableText.rich(TextSpan(children: children));
  }

  Widget msgTypeNotifyMsg_10(ThemeData theme, content) {
    List? modules = content['modules'] as List?;
    List<Widget>? jumpItem([String index = '']) {
      final String? uri = content['jump_uri$index'];
      if (uri != null && uri.isNotEmpty) {
        final String? text = content['jump_text$index'];
        return [
          Divider(color: theme.colorScheme.primary.withValues(alpha: 0.05)),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => PiliScheme.routePushFromUrl(uri),
            child: Text(
              text != null && text.isNotEmpty ? text : '查看详情',
            ),
          ),
        ];
      }
      return null;
    }

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        decoration: BoxDecoration(
          color: theme.colorScheme.onInverseSurface,
          borderRadius: const BorderRadius.all(Radius.circular(16)),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              content['title'],
              style: theme.textTheme.titleMedium!.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            Divider(color: theme.colorScheme.primary.withValues(alpha: 0.05)),
            if ((content['text'] as String?)?.isNotEmpty == true)
              SelectableText(content['text']),
            if (modules != null && modules.isNotEmpty) ...[
              const SizedBox(height: 4),
              ...modules.map(
                (e) => Row(
                  spacing: 10,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 80,
                      child: Text(
                        e['title'],
                        style: TextStyle(color: theme.colorScheme.outline),
                      ),
                    ),
                    Expanded(child: Text(e['detail'])),
                  ],
                ),
              ),
            ],
            ...?jumpItem(),
            ...?jumpItem('_2'),
            ...?jumpItem('_3'),
          ],
        ),
      ),
    );
  }

  Widget msgTypePictureCard_13(dynamic content) {
    final String? url = content['jump_url'];
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = math.max(400.0, constraints.maxWidth);
        Widget child = ClipRRect(
          borderRadius: Style.mdRadius,
          child: CachedNetworkImage(
            width: maxWidth,
            memCacheWidth: maxWidth.cacheSize(context),
            imageUrl: ImageUtils.thumbnailUrl(content['pic_url']),
            placeholder: (_, _) => const SizedBox.shrink(),
          ),
        );
        if (url != null && url.isNotEmpty) {
          child = GestureDetector(
            onTap: () => PiliScheme.routePushFromUrl(url),
            child: child,
          );
        }
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: maxWidth,
            child: child,
          ),
        );
      },
    );
  }

  Widget def(Color textColor, {err}) {
    return Text(
      '${item.content}${err != null ? '\n\ntype: ${msgTypeFromValue(item.msgType)}\nerr: $err' : ''}',
      style: TextStyle(
        letterSpacing: 0.6,
        height: 1.5,
        color: textColor,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}
