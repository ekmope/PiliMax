import 'package:PiliMax/common/widgets/avatars.dart';
import 'package:PiliMax/common/widgets/image/image_save.dart';
import 'package:PiliMax/http/loading_state.dart';
import 'package:PiliMax/models/dynamics/result.dart';
import 'package:PiliMax/pages/dynamics/widgets/action_panel.dart';
import 'package:PiliMax/pages/dynamics/widgets/author_panel.dart';
import 'package:PiliMax/pages/dynamics/widgets/dyn_content.dart';
import 'package:PiliMax/pages/dynamics/widgets/dynamic_video_hero_tag.dart';
import 'package:PiliMax/pages/dynamics/widgets/interaction.dart';
import 'package:PiliMax/utils/extension/theme_ext.dart';
import 'package:PiliMax/utils/page_utils.dart';
import 'package:PiliMax/utils/platform_utils.dart';
import 'package:flutter/material.dart';

class DynamicPanel extends StatefulWidget {
  final DynamicItemModel item;
  final bool isDetail;
  final ValueChanged<Object>? onRemove;
  final bool isSave;
  final void Function(bool isTop, Object dynId)? onSetTop;
  final VoidCallback? onBlock;
  final VoidCallback? onUnfold;
  final bool isDetailPortraitW;
  final Future<LoadingState> Function(bool isPrivate, Object dynId)?
  onSetPubSetting;
  final VoidCallback? onEdit;
  final ValueChanged<int>? onSetReplySubject;
  final ValueChanged<DynamicItemModel>? onUpdate;
  final int? index;
  final String heroScope;

  const DynamicPanel({
    super.key,
    required this.item,
    this.isDetail = false,
    this.onRemove,
    this.isSave = false,
    this.onSetTop,
    this.onBlock,
    this.onUnfold,
    this.isDetailPortraitW = true,
    this.onSetPubSetting,
    this.onEdit,
    this.onSetReplySubject,
    this.onUpdate,
    this.index,
    this.heroScope = 'dynamic',
  });

  @override
  State<DynamicPanel> createState() => _DynamicPanelState();
}

class _DynamicPanelState extends State<DynamicPanel> {
  String? _cachedVideoHeroTag;

  DynamicItemModel get item => widget.item;
  bool get isDetail => widget.isDetail;
  ValueChanged<Object>? get onRemove => widget.onRemove;
  bool get isSave => widget.isSave;
  void Function(bool isTop, Object dynId)? get onSetTop => widget.onSetTop;
  VoidCallback? get onBlock => widget.onBlock;
  VoidCallback? get onUnfold => widget.onUnfold;
  bool get isDetailPortraitW => widget.isDetailPortraitW;
  VoidCallback? get onEdit => widget.onEdit;
  ValueChanged<int>? get onSetReplySubject => widget.onSetReplySubject;
  ValueChanged<DynamicItemModel>? get onUpdate => widget.onUpdate;
  Object get _videoHeroOwnerKey =>
      '${widget.heroScope}-${widget.index ?? identityHashCode(this)}';

  String? get _videoHeroTag =>
      _cachedVideoHeroTag ??= makeDynamicVideoHeroTag(
        item,
        _videoHeroOwnerKey,
      );
  Object? get _videoHeroKey => dynamicVideoHeroKey(item);

  @override
  void didUpdateWidget(covariant DynamicPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (dynamicVideoHeroKey(oldWidget.item) != _videoHeroKey ||
        oldWidget.index != widget.index ||
        oldWidget.heroScope != widget.heroScope) {
      _cachedVideoHeroTag = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (item.visible == false) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final authorWidget = AuthorPanel(
      item: item,
      isDetail: isDetail,
      onRemove: onRemove,
      isSave: isSave,
      onSetTop: onSetTop,
      onBlock: onBlock,
      onSetPubSetting: widget.onSetPubSetting,
      onEdit: onEdit,
      onSetReplySubject: onSetReplySubject,
    );

    void showMore() => _imageSaveDialog(context, authorWidget.morePanel);

    final child = Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap:
            isDetail &&
                !const {
                  'DYNAMIC_TYPE_AV',
                  'DYNAMIC_TYPE_UGC_SEASON',
                  'DYNAMIC_TYPE_PGC_UNION',
                  'DYNAMIC_TYPE_PGC',
                  'DYNAMIC_TYPE_LIVE',
                  'DYNAMIC_TYPE_LIVE_RCMD',
                  'DYNAMIC_TYPE_MEDIALIST',
                  'DYNAMIC_TYPE_COURSES_SEASON',
                }.contains(item.type)
            ? null
            : () => PageUtils.pushDynDetail(
                item,
                onUpdate: onUpdate,
                heroTag: _videoHeroTag,
              ),
        onLongPress: showMore,
        onSecondaryTap: PlatformUtils.isMobile ? null : showMore,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
              child: authorWidget,
            ),
            if (item.modules.moduleDispute case final moduleDispute?)
              _buildDispute(theme, moduleDispute),
            ...dynContent(
              context,
              theme: theme,
              isSave: isSave,
              isDetail: isDetail,
              item: item,
              floor: 1,
              videoHeroTag: _videoHeroTag,
            ),
            const SizedBox(height: 2),
            if (!isDetail) ...[
              if (item.modules.moduleInteraction case ModuleInteraction(
                :final items,
              ))
                if (items != null && items.isNotEmpty)
                  dynInteraction(
                    theme: theme,
                    items: items,
                  ),
              ActionPanel(item: item),
              if (item.modules.moduleFold case final moduleFold?) ...[
                Divider(
                  height: 1,
                  color: theme.dividerColor.withValues(alpha: 0.1),
                ),
                _buildFoldItem(theme, moduleFold),
              ],
            ] else if (!isSave)
              const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (isSave || (isDetail && !isDetailPortraitW)) {
      return child;
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            width: 8,
            color: theme.dividerColor.withValues(alpha: 0.05),
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: child,
      ),
    );
  }

  void _imageSaveDialog(
    BuildContext context,
    Function(BuildContext) morePanel,
  ) {
    String? title;
    String? cover;
    String? bvid;
    dynamic view;
    dynamic danmaku;
    late final major = item.modules.moduleDynamic?.major;
    final moduleAuthor = item.modules.moduleAuthor;
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

    switch (item.type) {
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
        if (major?.liveRcmd case final liveRcmd?) {
          title = liveRcmd.title;
          cover = liveRcmd.cover;
        }
        break;
      case 'DYNAMIC_TYPE_LIVE':
        if (major?.live case final live?) {
          title = live.title;
          cover = live.cover;
        }
        break;
      case 'DYNAMIC_TYPE_COURSES_SEASON':
        if (major?.courses case final courses?) {
          setArchive(courses, includeBvid: false);
        }
        break;
      case 'DYNAMIC_TYPE_SUBSCRIPTION_NEW':
        if (major?.subscriptionNew?.liveRcmd?.content?.livePlayInfo
            case final livePlayInfo?) {
          title = livePlayInfo.title;
          cover = livePlayInfo.cover;
        }
        break;
      default:
        morePanel(context);
        return;
    }
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

  Widget _buildFoldItem(ThemeData theme, ModuleFold moduleFold) {
    Widget child = Text.rich(
      textAlign: TextAlign.center,
      style: TextStyle(
        height: 1,
        fontSize: 13,
        color: theme.colorScheme.outline,
      ),
      strutStyle: const StrutStyle(
        height: 1,
        leading: 0,
        fontSize: 13,
      ),
      TextSpan(
        children: [
          TextSpan(text: moduleFold.statement ?? '展开'),
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Icon(
              size: 19,
              Icons.keyboard_arrow_down,
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
    final users = moduleFold.users;
    if (users != null && users.isNotEmpty) {
      child = Row(
        spacing: 5,
        mainAxisAlignment: .center,
        children: [
          avatars(colorScheme: theme.colorScheme, users: users),
          child,
        ],
      );
    }
    return InkWell(
      onTap: onUnfold,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: child,
      ),
    );
  }

  Widget _buildDispute(ThemeData theme, ModuleDispute moduleDispute) {
    final child = Container(
      width: .infinity,
      margin: const .fromLTRB(12, 2, 12, 6),
      padding: const .symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(
          alpha: theme.isLight ? 0.5 : 0.7,
        ),
        borderRadius: const BorderRadius.all(Radius.circular(6)),
      ),
      child: Text.rich(
        style: TextStyle(
          height: 1,
          fontSize: 13,
          color: theme.colorScheme.onSecondaryContainer,
        ),
        strutStyle: const StrutStyle(
          leading: 0,
          height: 1,
          fontSize: 13,
        ),
        TextSpan(
          children: [
            WidgetSpan(
              alignment: .middle,
              child: Padding(
                padding: const .only(right: 4),
                child: Icon(
                  size: 15,
                  Icons.warning_rounded,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
            ),
            TextSpan(text: moduleDispute.title),
          ],
        ),
      ),
    );
    if (moduleDispute.jumpUrl?.isNotEmpty == true) {
      return GestureDetector(
        onTap: () => PageUtils.handleWebview(moduleDispute.jumpUrl!),
        child: child,
      );
    }
    return child;
  }
}
