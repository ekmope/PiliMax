import 'package:PiliMax/common/skeleton/video_card_h.dart';
import 'package:PiliMax/common/sliver_single_child_delegate.dart';
import 'package:PiliMax/common/style.dart';
import 'package:PiliMax/pilimax/forks/common/widgets/video_card/video_card_h.dart';
import 'package:PiliMax/pilimax/common/widgets/video_card/video_card_h_layout_metrics.dart';
import 'package:PiliMax/pilimax/common/widgets/video_card/video_hero_tag.dart';
import 'package:PiliMax/models/search/result.dart';
import 'package:PiliMax/pages/search_panel/all/controller.dart';
import 'package:PiliMax/pilimax/forks/pages/search_panel/all/widgets/pgc_card_v_search.dart';
import 'package:PiliMax/pilimax/forks/pages/search_panel/pgc/widgets/item.dart';
import 'package:PiliMax/pages/search_panel/user/widgets/item.dart';
import 'package:PiliMax/pilimax/forks/pages/search_panel/view.dart';
import 'package:PiliMax/utils/grid.dart';
import 'package:PiliMax/utils/waterfall.dart';
import 'package:material_ui/material_ui.dart';
import 'package:get/get.dart';
import 'package:waterfall_flow/waterfall_flow.dart'
    hide SliverWaterfallFlowDelegateWithMaxCrossAxisExtent;
import 'package:PiliMax/pages/search_panel/all/widgets/activity.dart';
import 'package:PiliMax/pages/search_panel/all/widgets/user.dart';

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
  Widget buildList(ThemeData theme, List<SearchVideoItemModel> list) {
    return SliverMainAxisGroup(
      slivers: [
        ...?controller.searchActivity?.map((e) {
          return SliverToBoxAdapter(
            child: SearchActivityItem(item: e),
          );
        }),
        ...?controller.searchUser?.map((e) {
          return SliverToBoxAdapter(
            child: SearchAllUserItem(item: e),
          );
        }),
        if (controller.searchMedia != null) ...[
          _buildPgc(controller.searchMedia!),
          SliverToBoxAdapter(
            child: Divider(
              height: 14,
              color: theme.colorScheme.outline.withValues(alpha: 0.1),
            ),
          ),
        ],
        _buildVideoResults(list),
      ],
    );
  }

  Widget _buildVideoResults(List<SearchVideoItemModel> list) {
    return SliverWaterfallFlow(
      gridDelegate: SliverWaterfallFlowDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: Grid.smallCardWidth * 2,
        crossAxisSpacing: Style.safeSpace,
      ),
      delegate: SliverChildBuilderDelegate(
        (_, index) {
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
        },
        childCount: list.length,
      ),
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
