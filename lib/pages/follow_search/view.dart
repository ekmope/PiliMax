import 'package:PiliMax/models_new/follow/data.dart';
import 'package:PiliMax/models_new/follow/list.dart';
import 'package:PiliMax/pages/common/search/common_search_page.dart';
import 'package:PiliMax/pages/follow/widgets/follow_item.dart';
import 'package:PiliMax/pages/follow_search/controller.dart';
import 'package:PiliMax/pages/share/view.dart' show UserModel;
import 'package:PiliMax/utils/utils.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class FollowSearchPage extends StatefulWidget {
  const FollowSearchPage({
    super.key,
    this.mid,
    this.isFromSelect = false,
  });

  final int? mid;
  final bool isFromSelect;

  @override
  State<FollowSearchPage> createState() => _FollowSearchPageState();
}

class _FollowSearchPageState
    extends
        CommonSearchPageState<FollowSearchPage, FollowData, FollowItemModel> {
  @override
  late final FollowSearchController controller;

  @override
  void initState() {
    super.initState();
    controller = Get.put(
      FollowSearchController(widget.mid ?? Get.arguments['mid']),
      tag: Utils.generateRandomString(8),
    );
  }

  @override
  List<Widget>? get searchSuggestions => [
    Obx(() {
      final list = controller.suggestions;
      if (list.isEmpty) {
        return const SliverToBoxAdapter(child: SizedBox.shrink());
      }

      return SliverList.builder(
        itemCount: list.length,
        itemBuilder: (context, index) {
          final item = list[index];
          return FollowItem(
            key: ValueKey('follow-search-suggestion-${item.mid}'),
            item: item,
            onSelect: _onSelect,
          );
        },
      );
    }),
  ];

  @override
  bool get isShowingSearchSuggestions => controller.suggestions.isNotEmpty;

  ValueChanged<UserModel>? get _onSelect {
    if (widget.mid != null && widget.isFromSelect) {
      return (userModel) => Get.back(result: userModel);
    }
    return null;
  }

  @override
  Widget buildList(List<FollowItemModel> list) {
    return SliverList.builder(
      itemCount: list.length,
      itemBuilder: ((context, index) {
        if (index == list.length - 1) {
          controller.onLoadMore();
        }
        return FollowItem(
          item: list[index],
          onSelect: _onSelect,
        );
      }),
    );
  }
}
