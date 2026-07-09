import 'package:PiliMax/common/widgets/flutter/refresh_indicator.dart';
import 'package:PiliMax/common/widgets/loading_widget/http_error.dart';
import 'package:PiliMax/http/loading_state.dart';
import 'package:PiliMax/models/common/dynamic/dynamics_type.dart';
import 'package:PiliMax/models/dynamics/up.dart';
import 'package:PiliMax/models/dynamics/result.dart';
import 'package:PiliMax/pages/dynamics/controller.dart';
import 'package:PiliMax/pages/dynamics/widgets/dynamic_panel.dart';
import 'package:PiliMax/pages/dynamics_tab/controller.dart';
import 'package:PiliMax/utils/extension/get_ext.dart';
import 'package:PiliMax/utils/global_data.dart';
import 'package:PiliMax/utils/waterfall.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:waterfall_flow/waterfall_flow.dart'
    hide SliverWaterfallFlowDelegateWithMaxCrossAxisExtent;

class DynamicsTabPage extends StatefulWidget {
  const DynamicsTabPage({
    super.key,
    this.dynamicsType,
    this.upItem,
  }) : assert(dynamicsType != null || upItem != null);

  final DynamicsTabType? dynamicsType;
  final UpItem? upItem;

  @override
  State<DynamicsTabPage> createState() => _DynamicsTabPageState();
}

class _DynamicsTabPageState extends State<DynamicsTabPage>
    with AutomaticKeepAliveClientMixin, DynMixin {
  DynamicsController dynamicsController = Get.putOrFind(DynamicsController.new);
  late final DynamicsTabController controller;
  late final DynamicsTabType dynamicsType =
      widget.dynamicsType ??
      (widget.upItem!.mid == -1 ? DynamicsTabType.all : DynamicsTabType.up);
  late final int? mid = widget.upItem?.mid == -1 ? null : widget.upItem?.mid;
  late final String tag = widget.upItem == null
      ? dynamicsType.name
      : DynamicsController.upTagForMid(widget.upItem!.mid);

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    controller = Get.putOrFind(
      () => DynamicsTabController(dynamicsType: dynamicsType)..mid = mid,
      tag: tag,
    );
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return refreshIndicator(
      key: controller.refreshKey,
      onRefresh: () {
        dynamicsController.queryFollowUp();
        return controller.onRefresh();
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        controller: controller.scrollController,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.only(bottom: 100),
            sliver: buildPage(
              Obx(() => _buildBody(controller.loadingState.value)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(LoadingState<List<DynamicItemModel>?> loadingState) {
    return switch (loadingState) {
      Loading() => dynSkeleton,
      Success(:final response) =>
        response != null && response.isNotEmpty
            ? GlobalData().dynamicsWaterfallFlow
                  ? SliverWaterfallFlow(
                      gridDelegate: dynGridDelegate,
                      delegate: SliverChildBuilderDelegate(
                        (_, index) => _itemBuilder(response, index),
                        childCount: response.length,
                      ),
                    )
                  : SliverList.builder(
                      itemBuilder: (context, index) =>
                          _itemBuilder(response, index),
                      itemCount: response.length,
                    )
            : HttpError(onReload: controller.onReload),
      Error(:final errMsg) => HttpError(
        errMsg: errMsg,
        onReload: controller.onReload,
      ),
    };
  }

  Widget _itemBuilder(List<DynamicItemModel> list, int index) {
    if (index == list.length - 1) {
      controller.onLoadMore();
    }
    final item = list[index];
    return DynamicPanel(
      key: ValueKey(
        'dynamic-tab-$tag-${item.idStr ?? index}-$index',
      ),
      item: item,
      index: index,
      heroScope: 'dynamic-tab-$tag',
      onRemove: (idStr) => controller.onRemove(index, idStr),
      onBlock: () => controller.onBlock(index),
      onUnfold: () => controller.onUnfold(item, index),
      onUpdate: (newItem) {
        list[index] = newItem;
        controller.loadingState.refresh();
      },
    );
  }
}
