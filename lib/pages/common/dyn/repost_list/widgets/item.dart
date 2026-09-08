import 'package:PiliMax/common/widgets/gesture/tap_gesture_recognizer.dart';
import 'package:PiliMax/common/widgets/image/network_img_layer.dart';
import 'package:PiliMax/common/widgets/image_grid/image_grid_view.dart';
import 'package:PiliMax/common/widgets/pendant_avatar.dart';
import 'package:PiliMax/grpc/bilibili/app/dynamic/v2.pb.dart'
    show
        DynamicItem,
        ModuleAuthor,
        ModuleDesc,
        Description,
        ModuleOpusSummary,
        TextNode;
import 'package:PiliMax/pages/dynamics/widgets/vote.dart';
import 'package:PiliMax/utils/app_scheme.dart';
import 'package:PiliMax/utils/bili_utils.dart';
import 'package:PiliMax/utils/extension/theme_ext.dart';
import 'package:PiliMax/utils/page_utils.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:get/get_navigation/src/extension_navigation.dart';
import 'package:material_ui/material_ui.dart';

class DynRepostItem extends StatelessWidget {
  const DynRepostItem({super.key, required this.item});

  final DynamicItem item;

  @override
  Widget build(BuildContext context) {
    ModuleAuthor? moduleAuthor;
    ModuleOpusSummary? moduleOpusSummary = item.extend.hasOpusSummary()
        ? item.extend.opusSummary
        : null;
    ModuleDesc? moduleDesc;

    for (final module in item.modules) {
      switch (module.moduleType) {
        case .module_author:
          moduleAuthor = module.moduleAuthor;
        case .module_opus_summary:
          moduleOpusSummary ??= module.moduleOpusSummary;
        case .module_desc:
          moduleDesc = module.moduleDesc;
        default:
      }
    }

    if (moduleAuthor == null) {
      return const SizedBox.shrink();
    }

    final colorScheme = ColorScheme.of(context);
    final author = moduleAuthor.author;

    return Material(
      type: .transparency,
      child: InkWell(
        onTap: () => PageUtils.pushDynFromId(id: item.extend.dynIdStr),
        child: Column(
          crossAxisAlignment: .start,
          children: [
            Padding(
              padding: const .symmetric(horizontal: 12, vertical: 10),
              child: Row(
                spacing: 12,
                crossAxisAlignment: .start,
                children: [
                  PendantAvatar(
                    author.face,
                    size: 34,
                    badgeSize: 14,
                    pendantImage: author.hasPendant()
                        ? author.pendant.image
                        : null,
                    vipStatus: author.hasVip() ? author.vip.status : null,
                    officialType: author.hasOfficial()
                        ? author.official.type
                        : null,
                    onTap: () => Get.toNamed('/member?mid=${author.mid}'),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: .start,
                      children: [
                        Row(
                          spacing: 6,
                          children: [
                            Flexible(
                              child: Text(
                                author.name,
                                maxLines: 1,
                                overflow: .ellipsis,
                                style: TextStyle(
                                  color:
                                      (author.vip.status > 0 &&
                                          author.vip.type == 2)
                                      ? colorScheme.vipColor
                                      : colorScheme.outline,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            BiliUtils.levelPicture(
                              author.level,
                              isSeniorMember: author.isSeniorMember == 1,
                              height: 11,
                            ),
                          ],
                        ),
                        Text(
                          moduleAuthor.ptimeLabelText,
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.outline,
                          ),
                        ),
                        if (moduleOpusSummary != null) ...[
                          const SizedBox(height: 6),
                          Text.rich(
                            style: const TextStyle(height: 1.75),
                            TextSpan(
                              children: _parseSummary(
                                context,
                                colorScheme,
                                moduleOpusSummary.summary.text.nodes,
                              ),
                            ),
                          ),
                        ] else if (moduleDesc != null) ...[
                          const SizedBox(height: 6),
                          Text.rich(
                            style: const TextStyle(height: 1.75),
                            TextSpan(
                              children: _parseDesc(
                                colorScheme,
                                moduleDesc.desc,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Divider(
              indent: 60,
              endIndent: 15,
              height: 0.3,
              color: colorScheme.outline.withValues(alpha: 0.08),
            ),
          ],
        ),
      ),
    );
  }
}

List<InlineSpan> _parseSummary(
  BuildContext context,
  ColorScheme colorScheme,
  List<TextNode> nodes,
) {
  final children = <InlineSpan>[];
  for (final e in nodes) {
    switch (e.nodeType) {
      case .EMOTE:
        final emote = e.emote;
        final emoteSize = emote.emoteWidth;
        final size =
            (emoteSize.hasEmojiSize() ? emoteSize.emojiSize : 1) * 20.0;
        children.add(
          WidgetSpan(
            child: NetworkImgLayer(
              src: emote.emoteUrl,
              width: size,
              height: size,
              type: .emote,
            ),
          ),
        );
      default:
        final link = e.hasLink() ? e.link : null;
        if (link != null) {
          switch (link.linkTypeEnum) {
            case .REPOST_PIC_DYN_URL || .REPOST_PIC_URL when link.hasLinkPics():
              final pics = link.linkPics;
              children
                ..add(const TextSpan(text: '\n'))
                ..add(
                  WidgetSpan(
                    child: ImageGridView(
                      picArr: pics.items
                          .map(
                            (e) => ImageModel(
                              url: e.src,
                              width: e.width.toInt(),
                              height: e.height.toInt(),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                );
              continue;
            case .VOTE when link.hasBizId():
              children.add(
                TextSpan(
                  text: e.rawText,
                  style: TextStyle(color: colorScheme.primary),
                  recognizer: (NoDeadlineTapGestureRecognizer()
                    ..onTap = () => showVoteDialog(
                      context,
                      int.tryParse(link.bizId) ?? -1,
                    )),
                ),
              );
              continue;
            default:
          }
        }
        final hasUri = link?.hasLink() ?? false;
        children.add(
          TextSpan(
            text: e.rawText,
            style: hasUri ? TextStyle(color: colorScheme.primary) : null,
            recognizer: hasUri
                ? (NoDeadlineTapGestureRecognizer()
                    ..onTap = () => PiliScheme.routePushFromUrl(link!.link))
                : null,
          ),
        );
    }
  }
  return children;
}

List<InlineSpan> _parseDesc(ColorScheme colorScheme, List<Description> desc) {
  final children = <InlineSpan>[];
  for (final e in desc) {
    switch (e.type) {
      case .desc_type_emoji:
        final size = (e.hasEmojiSize() ? e.emojiSize : 1) * 20.0;
        children.add(
          WidgetSpan(
            child: NetworkImgLayer(
              src: e.uri,
              width: size,
              height: size,
              type: .emote,
            ),
          ),
        );
      default:
        final hasUri = e.hasUri();
        children.add(
          TextSpan(
            text: e.text,
            style: hasUri ? TextStyle(color: colorScheme.primary) : null,
            recognizer: hasUri
                ? (NoDeadlineTapGestureRecognizer()
                    ..onTap = () => PiliScheme.routePushFromUrl(e.uri))
                : null,
          ),
        );
    }
  }
  return children;
}
