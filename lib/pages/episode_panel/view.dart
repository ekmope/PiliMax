import 'dart:async' show StreamSubscription;

import 'package:PiliMax/common/assets.dart';
import 'package:PiliMax/common/style.dart';
import 'package:PiliMax/common/widgets/badge.dart';
import 'package:PiliMax/common/widgets/button/icon_button.dart';
import 'package:PiliMax/common/widgets/image/image_save.dart';
import 'package:PiliMax/common/widgets/image/network_img_layer.dart';
import 'package:PiliMax/common/widgets/keep_alive_wrapper.dart';
import 'package:PiliMax/pilimax/common/widgets/flutter/page/tabs.dart';
import 'package:PiliMax/common/widgets/scroll_physics.dart'
    show clampingScrollPhysics;
import 'package:PiliMax/common/widgets/stat/stat.dart';
import 'package:PiliMax/http/fav.dart';
import 'package:PiliMax/http/loading_state.dart';
import 'package:PiliMax/http/video.dart';
import 'package:PiliMax/models/common/badge_type.dart';
import 'package:PiliMax/models/common/episode_panel_type.dart';
import 'package:PiliMax/pilimax/models/common/list_order.dart';
import 'package:PiliMax/models_new/pgc/pgc_info_model/episode.dart' as pgc;
import 'package:PiliMax/models_new/pgc/pgc_info_model/result.dart';
import 'package:PiliMax/models_new/video/video_detail/data.dart';
import 'package:PiliMax/models_new/video/video_detail/episode.dart' as ugc;
import 'package:PiliMax/models_new/video/video_detail/page.dart';
import 'package:PiliMax/models_new/video/video_detail/section.dart';
import 'package:PiliMax/pages/common/common_intro_controller.dart';
import 'package:PiliMax/pages/common/slide/common_slide_page.dart';
import 'package:PiliMax/pages/video/introduction/pgc/controller.dart';
import 'package:PiliMax/pages/video/introduction/ugc/controller.dart';
import 'package:PiliMax/pages/video/introduction/ugc/widgets/page.dart';
import 'package:PiliMax/pilimax/forks/utils/accounts.dart';
import 'package:PiliMax/utils/date_utils.dart';
import 'package:PiliMax/utils/duration_utils.dart';
import 'package:PiliMax/utils/extension/num_ext.dart';
import 'package:PiliMax/utils/id_utils.dart';
import 'package:PiliMax/utils/platform_utils.dart';
import 'package:PiliMax/utils/storage_pref.dart';
import 'package:collection/collection.dart';
import 'package:easy_debounce/easy_debounce.dart';
import 'package:extended_nested_scroll_view/extended_nested_scroll_view.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:material_ui/material_ui.dart' hide TabBarView;

class EpisodePanel extends CommonSlidePage {
  const EpisodePanel({
    super.key,
    super.enableSlide,
    this.onReverse,
    required this.type,
    required this.isSidePanel,
    required this.introController,
  });

  final EpisodeType type;
  final bool isSidePanel;
  final VoidCallback? onReverse;
  final CommonIntroController introController;

  @override
  State<EpisodePanel> createState() => _EpisodePanelState();
}

class _EpisodePanelState extends State<EpisodePanel>
    with TickerProviderStateMixin, CommonSlideMixin {
  ColorScheme get colorScheme => Theme.of(context).colorScheme;
  late final _type = widget.type;
  late final _isSidePanel = widget.isSidePanel;
  late final _introController = widget.introController;

  // ugc
  late final bool _isUgc;
  TabController? _tabController;
  List<SectionItem> get _sections =>
      _videoDetail.ugcSeason?.sections ?? const <SectionItem>[];
  VideoDetailData get _videoDetail => _ugcController.videoDetail.rawValue;
  late final _ugcController = _introController as UgcIntroController;

  // pgc
  late final _pgcController = _introController as PgcIntroController;
  PgcInfoModel get _pgcItem => _pgcController.pgcItem;

  // fav
  late final int _seasonId;
  RxnBool? _favState;

  // reverse
  late final _rxTabIndex = Rx(_tabIndex());
  late final List<bool> _isReversed;
  void _tabListener() {
    final index = _tabController!.index;
    if (index == _rxTabIndex.value) return;
    _rxTabIndex.value = index;
    if (_type == EpisodeType.season && _sections.isNotEmpty) {
      _syncTab(index.clamp(0, _sections.length - 1));
    }
    if (mounted) setState(() {});
  }

  late int _lastTabIndex;
  late int _lastItemIndex;
  late int _lastPgcSeasonIndex;
  late final int Function() _tabIndex;
  late final int Function() _itemIndex;
  late List<ugc.BaseEpisodeItem> _episodes;

  ScrollController? _scrollController;
  late final Map<int, int> _posMap = {};
  void setPosIndex(int tabIndex) {
    final scrollController = _scrollController;
    if (scrollController == null) return;
    _posMap[tabIndex] ??= scrollController.positions.length;
  }

  void _addUgcListener() {
    _ugcController.indexNotifier.addListener(_refresh);
  }

  void _removeUgcListener() {
    _ugcController.indexNotifier.removeListener(_refresh);
  }

  void _updateEpisodes() {
    switch (_type) {
      case EpisodeType.part:
        _episodes = _videoDetail.pages ?? const [];
      case EpisodeType.season:
        final section = _sections.elementAtOrNull(_tabIndex());
        _episodes = section?.episodes ?? const [];
      case EpisodeType.pgc:
        _episodes = _pgcItem.episodes ?? const [];
    }
  }

  void _refresh([_]) {
    if (!mounted) return;
    final tabIndexChanged = _syncTab(_tabIndex());
    setState(() {});
    _jumpToCurrIfNeeded(tabIndexChanged);
  }

  bool _syncTab(int tabIndex, {bool syncEpisodes = true}) {
    var tabIndexChanged = _lastTabIndex != tabIndex;
    if (syncEpisodes) {
      switch (_type) {
        case EpisodeType.part:
          _episodes = _videoDetail.pages ?? const [];
        case EpisodeType.season:
          if (tabIndex >= 0 && tabIndex < _sections.length) {
            _episodes = _sections[tabIndex].episodes ?? const [];
          } else {
            _episodes = const [];
          }
        case EpisodeType.pgc:
          final seasonChanged =
              _lastPgcSeasonIndex != _pgcController.seasonIndex;
          tabIndexChanged = tabIndexChanged || seasonChanged;
          _episodes = _pgcItem.episodes ?? const [];
          _lastPgcSeasonIndex = _pgcController.seasonIndex;
      }
    }
    _lastTabIndex = tabIndex;
    return tabIndexChanged;
  }

  void _jumpToCurrIfNeeded([Object? arg]) {
    final itemIndex = _itemIndex();
    final tabIndexChanged = arg is bool ? arg : _syncTab(_tabIndex());
    if (tabIndexChanged || _lastItemIndex != itemIndex) {
      _jumpToCurrent();
      _lastItemIndex = itemIndex;
    }
  }

  StreamSubscription? _pgcListener;

  void _addPgcListener() {
    _pgcListener = _pgcController.cid.listen(_onCidChanged);
  }

  void _removePgcListener() {
    _pgcListener?.cancel();
    _pgcListener = null;
  }

  void _onCidChanged([_]) {
    WidgetsBinding.instance.addPostFrameCallback(_refresh);
  }

  @override
  void didUpdateWidget(EpisodePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isUgc) {
      if (_type == EpisodeType.season) {
        final section = _sections.elementAtOrNull(_tabIndex());
        _episodes = section?.episodes ?? const [];
      } else {
        _updateEpisodes();
      }
      WidgetsBinding.instance.addPostFrameCallback(_jumpToCurrIfNeeded);
    } else {
      _updateEpisodes();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scrollController = PrimaryScrollController.of(context);
    if (_scrollController != scrollController) {
      _scrollController = scrollController;
      _posMap.clear();
    }
  }

  @override
  void initState() {
    super.initState();
    switch (_type) {
      case .part:
        _isUgc = true;
        _isReversed = [false];
        _tabIndex = () => 0;
        _itemIndex = () => _ugcController.partIndex;
        _episodes = _videoDetail.pages ?? const [];
        _addUgcListener();

      case .season:
        _isUgc = true;
        _tabIndex = () => _sections.isEmpty
            ? 0
            : _ugcController.sectionIndex.clamp(0, _sections.length - 1);
        _itemIndex = () => _ugcController.seasonIndex;
        final sections = _sections;
        if (sections.length > 1) {
          _tabController = TabController(
            vsync: this,
            length: sections.length,
            initialIndex: _ugcController.sectionIndex.clamp(
              0,
              sections.length - 1,
            ),
          )..addListener(_tabListener);
          _episodes = sections[_tabIndex()].episodes ?? const [];
          _isReversed = List.filled(sections.length, false);
        } else {
          _isReversed = [false];
          _episodes = sections.isEmpty
              ? const []
              : sections.first.episodes ?? const [];
        }
        _addUgcListener();

        final seasonId = _videoDetail.seasonId;
        if (Accounts.main.isLogin && seasonId != null) {
          _seasonId = seasonId;
          final favState = _ugcController.seasonFavState[_seasonId];
          if (favState != null) {
            _favState = RxnBool(favState);
          } else {
            _favState = RxnBool(null);
            VideoHttp.videoRelation(bvid: _ugcController.bvid).then(
              (result) {
                if (!mounted) return;
                if (result case Success(:final response)) {
                  final seasonFav = response.seasonFav ?? false;
                  _favState!.value = seasonFav;
                  _ugcController.seasonFavState[_seasonId] = seasonFav;
                }
              },
            );
          }
        }

      case .pgc:
        _isUgc = false;
        _isReversed = [false];
        _tabIndex = () => 0;
        _itemIndex = () => _pgcController.episodeIndex;
        _episodes = _pgcItem.episodes ?? const [];
        _lastPgcSeasonIndex = _pgcController.seasonIndex;
        _addPgcListener();
    }

    _lastTabIndex = _tabIndex();
    _lastItemIndex = _itemIndex();
    if (_lastItemIndex > 0) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _jumpToPos(offset: _calcItemOffset(_lastItemIndex)),
      );
    }
  }

  void _jumpToTop() => _jumpToPos(top: true);

  void _jumpToBottom() => _jumpToPos(top: false);

  Future<void> _jumpToCurrent() async {
    final tabIndex = _tabIndex();
    if (_tabController != null) {
      if (tabIndex < 0 || tabIndex >= _sections.length) return;
      if (_tabController!.index != tabIndex) {
        _tabController!.animateTo(tabIndex);
        await Future.pause(const Duration(milliseconds: 225));
        if (!mounted) return;
        _syncTab(tabIndex);
      }
    }
    final episodes = _episodes;
    if (episodes.isEmpty) return;
    final index = _itemIndex().clamp(0, episodes.length - 1);
    _jumpToPos(offset: _calcItemOffset(index));
  }

  void _jumpToPos({double? offset, bool? top}) {
    final scrollController = _scrollController;
    if (scrollController == null || !scrollController.hasClients) {
      return;
    }
    final tabIndex = _tabController?.index ?? 0;
    final posIndex = _posMap[tabIndex];
    if (posIndex == null) return;
    offset ??= (top == true) ^ _isReversed[tabIndex] ? 0 : null;
    if (scrollController is ExtendedNestedScrollController) {
      if (posIndex >= scrollController.nestedPositions.length) return;
      final position = scrollController.nestedPositions.elementAt(posIndex);
      position.localJumpTo(
        (offset ?? position.maxScrollExtent).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
      );
    } else {
      if (posIndex >= scrollController.positions.length) return;
      final position = scrollController.positions.elementAt(posIndex);
      position.jumpTo(
        (offset ?? position.maxScrollExtent).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
      );
    }
  }

  double _calcItemHeight(ugc.BaseEpisodeItem episode) {
    if (episode is ugc.EpisodeItem && episode.pages!.length > 1) {
      return 167; // 110 + 2 + 10 + 45
    }
    return 112;
  }

  double _calcItemOffset(int index) {
    double offset = 0;
    for (var i = 0; i < index; i++) {
      offset += _calcItemHeight(_episodes[i]);
    }
    return offset + 7;
  }

  @override
  void dispose() {
    _tabController
      ?..removeListener(_tabListener)
      ..dispose();
    _tabController = null;
    _removeListener();
    _favState?.close();
    super.dispose();
  }

  void _removeListener() {
    if (_isUgc) {
      _removeUgcListener();
    } else {
      _removePgcListener();
    }
  }

  /// Close a modal episode panel before executing an action. Side panels are
  /// owned by the video page and must stay mounted while the shared controller
  /// updates, so only the modal instance is popped here.
  bool _popIfNeeded() {
    if (_isSidePanel) return false;
    _removeListener();
    Get.back();
    return true;
  }

  @override
  Widget buildPage(ThemeData theme) {
    final child = Column(
      children: [
        _buildToolbar(),
        if (_tabController != null)
          TabBar(
            dividerHeight: 1,
            isScrollable: true,
            controller: _tabController,
            padding: const .only(right: 60),
            tabs: _sections.map((e) => Tab(text: e.title)).toList(),
            dividerColor: colorScheme.outline.withValues(alpha: 0.1),
          ),
        Expanded(
          child: enableSlide ? slideList(theme) : buildList(theme),
        ),
      ],
    );
    if (!_isSidePanel) {
      return ColoredBox(color: colorScheme.surface, child: child);
    }
    return child;
  }

  @override
  Widget buildList(ThemeData theme) {
    if (_tabController != null) {
      return TabBarView<TabBarDragGestureRecognizer>(
        controller: _tabController,
        physics: clampingScrollPhysics,
        horizontalDragGestureRecognizer: horizontalDragGestureRecognizer,
        children: _sections
            .mapIndexed(
              (i, e) => _buildBody(e.episodes ?? const [], tabIndex: i),
            )
            .toList(),
      );
    }
    return _buildBody(_episodes);
  }

  Widget _buildBody(List<ugc.BaseEpisodeItem> episodes, {int tabIndex = 0}) {
    final isCurrTab = tabIndex == _tabIndex();

    Widget child;
    child = SliverVariedExtentList.builder(
      itemCount: episodes.length,
      itemBuilder: (context, index) {
        final episode = episodes[index];
        final isCurrItem = isCurrTab && index == _itemIndex();
        Widget episodeItem = _buildEpisodeItem(
          episode: episode,
          tabIndex: tabIndex,
          index: index,
          length: episodes.length,
          isCurrItem: isCurrItem,
        );
        if (episode is ugc.EpisodeItem && episode.pages!.length > 1) {
          return Column(
            mainAxisSize: .min,
            crossAxisAlignment: .start,
            children: [
              episodeItem, // 110
              Padding(
                padding: const .symmetric(horizontal: 12, vertical: 5), // 10
                child: PagesPanel(
                  // 45
                  list: isCurrItem ? null : episode.pages,
                  cover: episode.arc?.pic,
                  bvid: episode.bvid ?? IdUtils.av2bv(episode.aid!),
                  heroTag: _ugcController.heroTag,
                  ugcIntroController: _ugcController,
                  onBack: _isSidePanel ? null : _popIfNeeded,
                ),
              ),
            ],
          );
        }
        return episodeItem;
      },
      itemExtentBuilder: (index, _) => _calcItemHeight(episodes[index]),
    );

    child = CustomScrollView(
      primary: true,
      reverse: _isReversed[tabIndex],
      key: ValueKey(_scrollController.hashCode),
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.only(
            top: 7,
            bottom: MediaQuery.viewPaddingOf(context).bottom + 100,
          ),
          sliver: child,
        ),
      ],
    );

    if (_tabController != null) {
      return KeepAliveWrapper(
        onBuild: () => setPosIndex(tabIndex),
        child: child,
      );
    } else {
      setPosIndex(tabIndex);
      return child;
    }
  }

  late final _isVip =
      !Accounts.mainEqVideo || Pref.userInfoCache?.vipStatus == 1;
  Future<void> _onChangeEpisode(
    int tabIndex,
    int index,
    ugc.BaseEpisodeItem episode,
    String title,
  ) async {
    if (!_popIfNeeded()) {
      _syncTab(tabIndex, syncEpisodes: false);
      _lastItemIndex = index;
    }

    if (episode.badge == "会员" && !_isVip) {
      SmartDialog.showToast('需要大会员');
      // return;
    }
    SmartDialog.showToast('切换到：$title');

    final changed = switch (_type) {
      EpisodeType.part || EpisodeType.season =>
        await _ugcController.onChangeEpisode(episode, manual: true),
      EpisodeType.pgc => await _pgcController.onChangeEpisode(
        episode,
        manual: true,
      ),
    };
    if (changed && _type == EpisodeType.season && episode.cid != null) {
      _ugcController.videoDetailCtr.seasonCid = episode.cid;
      _ugcController.updateIndex(force: true);
    }
  }

  Widget _buildEpisodeItem({
    required ugc.BaseEpisodeItem episode,
    required int tabIndex,
    required int index,
    required int length,
    required bool isCurrItem,
  }) {
    late String title;
    String? cover;
    String? bvid;
    num? duration;
    int? pubdate;
    int? view;
    int? danmaku;
    bool? isCharging;
    bool? cacheWidth;

    switch (episode) {
      case Part part:
        cover = part.firstFrame ?? _videoDetail.pic;
        title = part.part!;
        duration = part.duration;
        pubdate = part.ctime;
        cacheWidth = part.dimension?.cacheWidth;
        break;
      case ugc.EpisodeItem item:
        title = item.title!;
        bvid = item.bvid;
        if (item.arc case final arc?) {
          cover = arc.pic;
          duration = arc.duration;
          pubdate = arc.pubdate;
          if (arc.stat case final stat?) {
            view = stat.view;
            danmaku = stat.danmaku;
          }
          cacheWidth = arc.dimension?.cacheWidth;
        }
        if (item.attribute == 8) {
          isCharging = true;
        }
        break;
      case pgc.EpisodeItem item:
        bvid = item.bvid;
        title = item.showTitle ?? item.title!;
        cover = item.cover;
        if (item.from == 'pugv') {
          duration = item.duration;
          view = item.play;
        } else {
          duration = item.duration == null ? null : item.duration! ~/ 1000;
        }
        pubdate = item.pubTime;
        cacheWidth = item.dimension?.cacheWidth;
        break;
    }
    late final Color primary = colorScheme.primary;

    void onLongPress() {
      if (cover?.isNotEmpty == true) {
        imageSaveDialog(
          title: title,
          cover: cover,
          bvid: bvid,
          pubdate: pubdate,
          view: view,
          danmaku: danmaku,
        );
      }
    }

    return Padding(
      padding: const .only(bottom: 2),
      child: SizedBox(
        height: 110,
        child: Material(
          type: .transparency,
          child: InkWell(
            onTap: () {
              if (isCurrItem) return;
              EasyDebounce.debounce(
                'onChangeEpisode',
                const Duration(milliseconds: 200),
                () => _onChangeEpisode(tabIndex, index, episode, title),
              );
            },
            onLongPress: onLongPress,
            onSecondaryTap: PlatformUtils.isMobile ? null : onLongPress,
            child: Padding(
              padding: const .symmetric(
                horizontal: Style.safeSpace,
                vertical: 5,
              ),
              child: Row(
                spacing: 10,
                children: [
                  if (cover?.isNotEmpty == true)
                    Stack(
                      clipBehavior: .none,
                      children: [
                        NetworkImgLayer(
                          src: cover,
                          width: 160,
                          height: 100,
                          cacheWidth: cacheWidth,
                        ),
                        if (duration != null && duration > 0)
                          PBadge(
                            text: DurationUtils.formatDuration(duration),
                            right: 6.0,
                            bottom: 6.0,
                            type: .gray,
                          ),
                        if (_type == .part)
                          Positioned(
                            top: 0,
                            right: 0,
                            child: Container(
                              padding: const .symmetric(horizontal: 4),
                              decoration: BoxDecoration(
                                color: colorScheme.secondaryContainer,
                                borderRadius: const .only(
                                  bottomLeft: .circular(4),
                                  topRight: Style.imgRadius,
                                ),
                              ),
                              child: Text(
                                (index + 1).toString(),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colorScheme.onSecondaryContainer,
                                ),
                              ),
                            ),
                          )
                        else if (isCharging == true)
                          const PBadge(
                            text: '充电专属',
                            top: 6,
                            right: 6,
                            type: .error,
                          )
                        else if (episode.badge != null)
                          PBadge(
                            text: episode.badge,
                            top: 6,
                            right: 6,
                            type: switch (episode.badge) {
                              '预告' => PBadgeType.gray,
                              '限免' => PBadgeType.free,
                              _ => PBadgeType.primary,
                            },
                          ),
                      ],
                    )
                  else if (isCurrItem)
                    Image.asset(
                      Assets.livingStatic,
                      color: primary,
                      height: 12,
                      cacheHeight: 12.cacheSize(context),
                    ),
                  Expanded(
                    child: Column(
                      mainAxisSize: .min,
                      crossAxisAlignment: .start,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            textAlign: .start,
                            style: TextStyle(
                              height: 1.42,
                              letterSpacing: 0.3,
                              fontWeight: isCurrItem ? .bold : null,
                              color: isCurrItem ? primary : null,
                            ),
                            maxLines: 2,
                            overflow: .ellipsis,
                          ),
                        ),
                        if (pubdate != null)
                          Text(
                            DateFormatUtils.format(pubdate),
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1,
                              color: colorScheme.outline,
                              overflow: .clip,
                            ),
                          ),
                        if (view != null) ...[
                          const SizedBox(height: 2),
                          Row(
                            spacing: 8,
                            children: [
                              StatWidget(
                                value: view,
                                type: .play,
                              ),
                              if (danmaku != null)
                                StatWidget(
                                  value: danmaku,
                                  type: .danmaku,
                                ),
                            ],
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
      ),
    );
  }

  Future<void> _onFavSeason(bool isFav) async {
    final res = await FavHttp.seasonFav(
      isFav: isFav,
      seasonId: _seasonId,
    );
    if (!mounted) return;
    if (res.isSuccess) {
      _favState!.toggle();
      _ugcController.seasonFavState[_seasonId] = !isFav;
      SmartDialog.showToast('${isFav ? '取消' : ''}订阅成功');
    } else {
      res.toast();
    }
  }

  Widget _buildFavBtn(bool? isFav) {
    if (isFav == null) return const SizedBox.shrink();
    return iconButton(
      iconSize: 22,
      tooltip: isFav ? '取消订阅' : '订阅',
      icon: isFav
          ? const Icon(Icons.notifications_off_outlined)
          : const Icon(Icons.notifications_active_outlined),
      onPressed: () => _onFavSeason(isFav),
    );
  }

  ListOrder? _dataOrder(int tabIndex) => switch (_type) {
    EpisodeType.part => _videoDetail.listOrder,
    EpisodeType.season => _sections.elementAtOrNull(tabIndex)?.listOrder,
    EpisodeType.pgc => null,
  };

  Widget get _buildDataReverseBtn => Obx(() {
    final tabIndex = _rxTabIndex.value;
    if (_type == EpisodeType.pgc || tabIndex != _tabIndex()) {
      return const SizedBox.shrink();
    }
    final order = _dataOrder(tabIndex) ?? ListOrder.asc;
    return iconButton(
      iconSize: 22,
      tooltip: order.label,
      icon: switch (order) {
        ListOrder.asc => const Icon(MdiIcons.sortAscending),
        ListOrder.desc => const Icon(MdiIcons.sortDescending),
        ListOrder.shuffle => const Icon(Icons.shuffle),
      },
      onPressed: () {
        _popIfNeeded();
        widget.onReverse?.call();
      },
    );
  });

  Widget get _buildUiReverseBtn => Obx(
    () {
      final tabIndex = _rxTabIndex.value;
      final reversed = _isReversed[tabIndex];
      return iconButton(
        iconSize: 22,
        tooltip: reversed ? '顺序' : '倒序',
        icon: reversed
            ? const Icon(MdiIcons.sortNumericDescending)
            : const Icon(MdiIcons.sortNumericAscending),
        onPressed: () => setState(() => _isReversed[tabIndex] = !reversed),
      );
    },
  );

  Widget _buildToolbar() => Container(
    height: 45,
    padding: .symmetric(horizontal: !_isSidePanel ? 14 : 6),
    decoration: BoxDecoration(
      border: Border(
        bottom: BorderSide(color: colorScheme.outline.withValues(alpha: 0.1)),
      ),
    ),
    child: Row(
      children: [
        if (!_isSidePanel)
          Text(
            _type.title,
            style: const TextStyle(fontSize: 16),
          ),
        if (_favState != null) Obx(() => _buildFavBtn(_favState!.value)),
        iconButton(
          iconSize: 22,
          tooltip: '跳至顶部',
          icon: const Icon(Icons.vertical_align_top),
          onPressed: _jumpToTop,
        ),
        iconButton(
          iconSize: 22,
          tooltip: '跳至底部',
          icon: const Icon(Icons.vertical_align_bottom),
          onPressed: _jumpToBottom,
        ),
        iconButton(
          iconSize: 22,
          tooltip: '跳至当前',
          icon: const Icon(Icons.my_location),
          onPressed: _jumpToCurrent,
        ),
        if (_isUgc) _buildDataReverseBtn,
        const Spacer(),
        _buildUiReverseBtn,
        if (!_isSidePanel)
          iconButton(
            iconSize: 22,
            tooltip: '关闭',
            icon: const Icon(Icons.close),
            onPressed: Get.back,
          ),
      ],
    ),
  );
}
