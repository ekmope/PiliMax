import 'package:PiliMax/common/widgets/image/image_save.dart';
import 'package:PiliMax/models/dynamics/result.dart';
import 'package:PiliMax/pages/dynamics/widgets/dyn_content.dart';
import 'package:PiliMax/pages/dynamics/widgets/dynamic_video_hero_tag.dart';
import 'package:PiliMax/pages/dynamics/widgets/module_panel.dart';
import 'package:PiliMax/utils/date_utils.dart';
import 'package:PiliMax/utils/page_utils.dart';
import 'package:PiliMax/utils/platform_utils.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

Widget forwardPanel(
  BuildContext context, {
  required int floor,
  required ThemeData theme,
  required DynamicItemModel orig,
  required bool isSave,
  required bool isDetail,
}) {
  return _ForwardPanel(
    floor: floor,
    theme: theme,
    orig: orig,
    isSave: isSave,
    isDetail: isDetail,
  );
}

class _ForwardPanel extends StatefulWidget {
  const _ForwardPanel({
    required this.floor,
    required this.theme,
    required this.orig,
    required this.isSave,
    required this.isDetail,
  });

  final int floor;
  final ThemeData theme;
  final DynamicItemModel orig;
  final bool isSave;
  final bool isDetail;

  @override
  State<_ForwardPanel> createState() => _ForwardPanelState();
}

class _ForwardPanelState extends State<_ForwardPanel> {
  String? _cachedVideoHeroTag;

  String? get _videoHeroTag =>
      _cachedVideoHeroTag ??=
          makeDynamicVideoHeroTag(widget.orig, identityHashCode(this));

  @override
  void didUpdateWidget(covariant _ForwardPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.orig != widget.orig) {
      _cachedVideoHeroTag = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return _forwardPanel(
      context,
      floor: widget.floor,
      theme: widget.theme,
      orig: widget.orig,
      isSave: widget.isSave,
      isDetail: widget.isDetail,
      videoHeroTag: _videoHeroTag,
    );
  }
}

Widget _forwardPanel(
  BuildContext context, {
  required int floor,
  required ThemeData theme,
  required DynamicItemModel orig,
  required bool isSave,
  required bool isDetail,
  String? videoHeroTag,
}) {
  final moduleDynamic = orig.modules.moduleDynamic;
  final major = moduleDynamic?.major;
  final isNoneMajor = major?.type == 'MAJOR_TYPE_NONE';

  Widget child;

  if (isNoneMajor) {
    child = noneWidget(theme, major?.none?.tips);
  } else {
    child = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _forwardAuthor(
          theme: theme,
          moduleAuthor: orig.modules.moduleAuthor!,
          isSave: isSave,
        ),
        const SizedBox(height: 5),
        ...dynContent(
          context,
          theme: theme,
          isSave: isSave,
          isDetail: isDetail,
          item: orig,
          floor: floor + 1,
          videoHeroTag: videoHeroTag,
        ),
      ],
    );
  }

  child = Container(
    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
    color: theme.dividerColor.withValues(alpha: 0.08),
    child: child,
  );

  if (isNoneMajor) {
    return child;
  }

  void showMore() {
    String? title, cover, bvid;
    dynamic view;
    dynamic danmaku;
    final moduleAuthor = orig.modules.moduleAuthor;
    void setArchive(
      DynamicArchiveModel archive, {
      bool includeBvid = true,
    }) {
      title = archive.title;
      cover = archive.cover;
      if (includeBvid) {
        bvid = archive.bvid;
      }
      view = archive.stat?.play;
      danmaku = archive.stat?.danmu;
    }

    switch (orig.type) {
      case 'DYNAMIC_TYPE_AV':
        if (major?.archive case final archive?) {
          setArchive(archive);
        }
        break;
      case 'DYNAMIC_TYPE_UGC_SEASON':
        if (major?.ugcSeason case final ugcSeason?) {
          setArchive(ugcSeason);
        }
        break;
      case 'DYNAMIC_TYPE_PGC' || 'DYNAMIC_TYPE_PGC_UNION':
        if (major?.pgc case final pgc?) {
          setArchive(pgc, includeBvid: false);
        }
        break;
      case 'DYNAMIC_TYPE_LIVE_RCMD':
        title = major?.liveRcmd?.title;
        cover = major?.liveRcmd?.cover;
        break;
      case 'DYNAMIC_TYPE_LIVE':
        title = major?.live?.title;
        cover = major?.live?.cover;
        break;
      default:
        return;
    }
    if (cover != null) {
      imageSaveDialog(
        title: title,
        cover: cover,
        bvid: bvid,
        pubdate: moduleAuthor?.pubTs,
        view: view,
        danmaku: danmaku,
        ownerName: moduleAuthor?.name,
      );
    }
  }

  return InkWell(
    onTap: () => PageUtils.pushDynDetail(orig, heroTag: videoHeroTag),
    onLongPress: showMore,
    onSecondaryTap: PlatformUtils.isMobile ? null : showMore,
    child: child,
  );
}

Widget _forwardAuthor({
  required ThemeData theme,
  required ModuleAuthorModel moduleAuthor,
  required bool isSave,
}) {
  final isNormalAuth = moduleAuthor.type == 'AUTHOR_TYPE_NORMAL';
  return Row(
    children: [
      GestureDetector(
        onTap: isNormalAuth
            ? () => Get.toNamed('/member?mid=${moduleAuthor.mid}')
            : null,
        child: Text(
          '${isNormalAuth ? '@' : ''}${moduleAuthor.name}',
          style: TextStyle(color: theme.colorScheme.primary),
        ),
      ),
      const SizedBox(width: 6),
      Text(
        isSave
            ? DateFormatUtils.format(
                moduleAuthor.pubTs,
                format: DateFormatUtils.longFormatDs,
              )
            : DateFormatUtils.dateFormat(moduleAuthor.pubTs),
        style: TextStyle(
          color: theme.colorScheme.outline,
          fontSize: theme.textTheme.labelSmall!.fontSize,
        ),
      ),
    ],
  );
}
