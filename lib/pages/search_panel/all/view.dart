import 'package:PiliMax/common/skeleton/video_card_h.dart';
import 'package:PiliMax/common/style.dart';
import 'package:PiliMax/common/widgets/video_card/video_card_h.dart';
import 'package:PiliMax/models/search/result.dart';
import 'package:PiliMax/pages/search_panel/all/controller.dart';
import 'package:PiliMax/pages/search_panel/all/widgets/pgc_card_v_search.dart';
import 'package:PiliMax/pages/search_panel/pgc/widgets/item.dart';
import 'package:PiliMax/pages/search_panel/user/widgets/item.dart';
import 'package:PiliMax/pages/search_panel/view.dart';
import 'package:PiliMax/utils/grid.dart';
import 'package:PiliMax/utils/waterfall.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:waterfall_flow/waterfall_flow.dart'
    hide SliverWaterfallFlowDelegateWithMaxCrossAxisExtent;

class SearchAllPanel extends CommonSearchPanel {
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
    extends CommonSearchPanelState<SearchAllPanel, SearchAllData, dynamic> {
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
  Widget buildList(ThemeData theme, List<dynamic> list) {
    return SliverWaterfallFlow(
      gridDelegate: SliverWaterfallFlowDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: Grid.smallCardWidth * 2,
        crossAxisSpacing: Style.safeSpace,
      ),
      delegate: SliverChildBuilderDelegate(
        (_, index) {
          if (index == list.length - 1) {
            controller.onLoadMore();
          }
          return switch (list[index]) {
            SearchVideoItemModel e => () {
              final heroTag =
                  'search-all-video-${widget.tag}-'
                  '${e.bvid ?? e.aid ?? e.cid}-$index';
              return SizedBox(
                height: 120,
                child: VideoCardH(
                  key: ValueKey(heroTag),
                  videoItem: e,
                  heroTag: heroTag,
                ),
              );
            }(),
            List<SearchPgcItemModel> e =>
              e.length == 1
                  ? SizedBox(
                      height: 160,
                      child: SearchPgcItem(
                        item: e.first,
                        heroTagPrefix: 'search-all-pgc-${widget.tag}',
                        index: index,
                      ),
                    )
                  : SizedBox(
                      height:
                          Grid.smallCardWidth / 2 / 0.75 +
                          MediaQuery.textScalerOf(context).scale(60),
                      child: ListView.builder(
                        padding: const EdgeInsets.only(bottom: 7),
                        physics: const AlwaysScrollableScrollPhysics(),
                        scrollDirection: Axis.horizontal,
                        itemCount: e.length,
                        itemBuilder: (context, itemIndex) {
                          return Container(
                            width: Grid.smallCardWidth / 2,
                            margin: EdgeInsets.only(
                              left: Style.safeSpace,
                              right: itemIndex == e.length - 1
                                  ? Style.safeSpace
                                  : 0,
                            ),
                            child: PgcCardVSearch(
                              item: e[itemIndex],
                              heroTagPrefix:
                                  'search-all-pgc-v-${widget.tag}-$index',
                              index: itemIndex,
                            ),
                          );
                        },
                      ),
                    ),
            SearchUserItemModel e => Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: SearchUserItem(item: e),
            ),
            _ => const SizedBox.shrink(),
          };
        },
        childCount: list.length,
      ),
    );
  }

  @override
  Widget get buildLoading => SliverGrid.builder(
    gridDelegate: Grid.videoCardHDelegate(),
    itemBuilder: (context, index) => const VideoCardHSkeleton(),
    itemCount: 10,
  );
}
