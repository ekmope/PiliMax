import 'package:PiliMax/common/style.dart';
import 'package:PiliMax/pilimax/forks/common/widgets/video_card/video_card_h.dart';
import 'package:PiliMax/pilimax/common/widgets/video_card/video_card_h_layout_metrics.dart';
import 'package:PiliMax/pilimax/common/widgets/video_card/video_hero_tag.dart';
import 'package:PiliMax/models/search/result.dart';
import 'package:PiliMax/models/search/search_esports.dart';
import 'package:PiliMax/pages/search_panel/all/controller.dart';
import 'package:PiliMax/pages/search_panel/video/view.dart';
import 'package:PiliMax/pilimax/forks/pages/search_panel/pgc/widgets/item.dart';
import 'package:PiliMax/pilimax/forks/pages/search_panel/view.dart';
import 'package:PiliMax/utils/grid.dart';
import 'package:PiliMax/utils/waterfall.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:material_ui/material_ui.dart'
    hide SliverGridDelegateWithMaxCrossAxisExtent;
import 'package:get/get.dart';
import 'package:PiliMax/pages/search_panel/all/widgets/activity.dart';
import 'package:PiliMax/pages/search_panel/all/widgets/user.dart';
import 'package:PiliMax/pages/search_panel/all/widgets/esports.dart';

class SearchAllPanel extends SearchVideoPanel {
  const SearchAllPanel({
    super.key,
    required super.keyword,
    required super.tag,
    required super.searchType,
  });

  @override
  State<SearchAllPanel> createState() => _SearchAllPanelState();
}

class _SearchAllPanelState
    extends
        CommonSearchPanelState<
          SearchAllPanel,
          SearchVideoData,
          SearchVideoItemModel
        >
    with GridMixin, SearchVideoPanelMixin<SearchAllPanel> {
  @override
  late final SearchAllController controller;

  @override
  void initState() {
    super.initState();
    controller = Get.put(
      SearchAllController(
        keyword: widget.keyword,
        searchType: widget.searchType,
        tag: widget.tag,
      ),
      tag: widget.searchType.name + widget.tag,
    );
  }

  @override
  Widget buildSuccess(ThemeData theme, List<SearchVideoItemModel>? response) {
    final activities = controller.searchActivity ?? const <SearchActivity>[];
    final users = controller.searchUser ?? const <SearchUser>[];
    final media = controller.searchMedia ?? const <SearchPgcItemModel>[];
    final esports = controller.searchEsports;
    final hasEsports = esports != null && esports.contest.isNotEmpty;
    if (activities.isEmpty && users.isEmpty && media.isEmpty && !hasEsports) {
      return super.buildSuccess(theme, response);
    }

    final filteredVideos = controller.filterKeywords(
      response ?? const <SearchVideoItemModel>[],
      getTitle,
    );
    final filteredActivities = controller.filterKeywords(
      activities,
      (item) => item.title,
    );
    final filteredUsers = controller.filterKeywords(
      users,
      (item) => item.uname,
    );
    final filteredMedia = controller.filterKeywords(
      media,
      (item) => item.title.map((e) => e.text).join(),
    );
    final filteredEsports = controller.filterKeywords(
      [if (hasEsports) esports],
      (item) => item.contest.first.title,
    );

    return buildResults(
      theme,
      filteredVideos,
      leading: [
        if (filteredEsports.isNotEmpty) ...[
          _buildEsports(filteredEsports.first),
          SliverToBoxAdapter(
            child: Divider(
              height: 14,
              color: theme.colorScheme.outline.withValues(alpha: 0.1),
            ),
          ),
        ],
        for (final item in filteredActivities)
          SliverToBoxAdapter(child: SearchActivityItem(item: item)),
        for (final item in filteredUsers)
          SliverToBoxAdapter(child: SearchAllUserItem(item: item)),
        if (filteredMedia.isNotEmpty) ...[
          _buildPgc(filteredMedia),
          SliverToBoxAdapter(
            child: Divider(
              height: 14,
              color: theme.colorScheme.outline.withValues(alpha: 0.1),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget buildList(ThemeData theme, List<SearchVideoItemModel> list) {
    return _buildVideoResults(list);
  }

  static Widget _buildEsports(SearchEsports item) =>
      SliverToBoxAdapter(child: SearchEsportsItem(item: item));

  Widget _buildVideoResults(List<SearchVideoItemModel> list) {
    return SliverMasonryGrid(
      crossAxisSpacing: Style.safeSpace,
      gridDelegate: SliverSimpleGridDelegateWithMaxCrossAxisExtent_(
        maxCrossAxisExtent: Grid.smallCardWidth * 2,
      ),
      delegate: SliverChildBuilderDelegate((context, index) {
        if (index == list.length - 1) controller.onLoadMore();
        final item = list[index];
        final heroTag = VideoHeroTag.forItem(
          scope: 'search-all-video-${widget.tag}',
          item: item,
          contentId: item.bvid ?? item.aid ?? item.cid ?? 'unknown',
        );
        return SizedBox(
          height: VideoCardHLayoutMetrics.itemHeight,
          child: VideoCardH(
            key: ValueKey(heroTag),
            videoItem: item,
            heroTag: heroTag,
          ),
        );
      }, childCount: list.length),
    );
  }

  static Widget _buildPgc(List<SearchPgcItemModel> list) {
    final Widget child;
    if (list.length == 1) {
      child = SearchPgcItem(item: list.first);
    } else {
      child = ListView.builder(
        padding: .zero,
        itemExtent: 340,
        itemCount: list.length,
        scrollDirection: .horizontal,
        physics: const AlwaysScrollableScrollPhysics(),
        itemBuilder: (context, index) {
          return SearchPgcItem(item: list[index]);
        },
      );
    }
    return SliverToBoxAdapter(child: SizedBox(height: 158, child: child));
  }

  late final pgcGridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(
    maxCrossAxisExtent: Grid.smallCardWidth * 2,
    mainAxisExtent: 160,
  );
}
