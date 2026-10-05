import 'package:PiliMax/common/skeleton/msg_feed_top.dart';
import 'package:PiliMax/common/sliver_single_child_delegate.dart';
import 'package:PiliMax/common/widgets/dialog/dialog.dart';
import 'package:PiliMax/common/widgets/dialog/export_import.dart';
import 'package:PiliMax/common/widgets/flutter/refresh_indicator.dart';
import 'package:PiliMax/common/widgets/image/network_img_layer.dart';
import 'package:PiliMax/common/widgets/loading_widget/http_error.dart';
import 'package:PiliMax/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliMax/common/widgets/sliver_wrap.dart';
import 'package:PiliMax/common/widgets/view_sliver_safe_area.dart';
import 'package:PiliMax/common/widgets/scroll_physics.dart';
import 'package:PiliMax/http/loading_state.dart';
import 'package:PiliMax/models/common/enum_with_label.dart';
import 'package:PiliMax/models/common/image_type.dart';
import 'package:PiliMax/models_new/blacklist/list.dart';
import 'package:PiliMax/pages/blacklist/controller.dart';
import 'package:PiliMax/pages/search/widgets/search_text.dart';
import 'package:PiliMax/utils/date_utils.dart';
import 'package:PiliMax/utils/storage_pref.dart';
import 'package:PiliMax/utils/utils.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:material_ui/material_ui.dart';
import 'package:get/get.dart';

enum _BlockType implements EnumWithLabel {
  local('本地'),
  online('在线');

  @override
  final String label;

  const _BlockType(this.label);
}

class BlackListPage extends StatefulWidget {
  const BlackListPage({super.key});

  @override
  State<BlackListPage> createState() => _BlackListPageState();
}

class _BlackListPageState extends State<BlackListPage>
    with SingleTickerProviderStateMixin {
  final _blackListController = Get.put(BlackListController());
  late final TabController _tabController;
  late EdgeInsets padding;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: _BlockType.values.length,
      vsync: this,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    padding = MediaQuery.viewPaddingOf(context);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SimpleScaffold(
      appBar: AppBar(title: const Text('黑名单管理')),
      body: Column(
        children: [
          TabBar(
            controller: _tabController,
            tabs: _BlockType.values.map((e) => Tab(text: e.label)).toList(),
          ),
          Expanded(
            child: tabBarView(
              controller: _tabController,
              children: [_local, _online],
            ),
          ),
        ],
      ),
    );
  }

  Widget get _online => refreshIndicator(
    onRefresh: _blackListController.onRefresh,
    child: CustomScrollView(
      key: const PageStorageKey(_BlockType.online),
      physics: const AlwaysScrollableScrollPhysics(),
      controller: _blackListController.scrollController,
      slivers: [
        ViewSliverSafeArea(
          sliver: Obx(
            () => _buildBody(_blackListController.loadingState.value),
          ),
        ),
      ],
    ),
  );

  Widget get _local => ScaffoldLayout(
    fab: Padding(
      padding: EdgeInsets.only(
        right: kFloatingActionButtonMargin + padding.right,
        bottom: kFloatingActionButtonMargin + padding.bottom,
      ),
      child: Column(
        spacing: kFloatingActionButtonMargin,
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            tooltip: '导入/导出',
            onPressed: _showImportExportDialog,
            child: const Icon(Icons.swap_vert, size: 26),
          ),
          FloatingActionButton(
            tooltip: '添加',
            onPressed: _showAddMidDialog,
            child: const Icon(Icons.add),
          ),
        ],
      ),
    ),
    body: CustomScrollView(
      key: const PageStorageKey(_BlockType.local),
      slivers: [
        ViewSliverSafeArea(
          bottom: 180,
          sliver: SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            sliver: SliverFixedWrap(
              spacing: 8,
              runSpacing: 8,
              mainAxisExtent: 30,
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final mid = _blackListController.blackMids.elementAt(index);
                  return SearchText(
                    text: mid.toString(),
                    onTap: (value) => Get.toNamed('/member?mid=$value'),
                    onLongPress: (_) => showConfirmDialog(
                      context: context,
                      title: const Text('确定移除该用户？'),
                      onConfirm: () {
                        Pref.removeBlackMid(mid);
                        setState(() {});
                      },
                    ),
                    height: 1,
                    fontSize: 14,
                    padding: const EdgeInsets.fromLTRB(11, 8, 11, 0),
                  );
                },
                childCount: _blackListController.blackMids.length,
              ),
            ),
          ),
        ),
      ],
    ),
  );

  void _showAddMidDialog() {
    var text = '';
    showConfirmDialog(
      context: context,
      title: const Text('屏蔽用户'),
      content: TextField(
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onChanged: (value) => text = value,
        decoration: const InputDecoration(labelText: 'UID'),
      ),
      onConfirm: () {
        final mid = int.tryParse(text);
        if (mid == null) {
          SmartDialog.showToast('请输入有效 UID');
          return;
        }
        Pref.setBlackMid(mid);
        setState(() {});
      },
    );
  }

  void _showImportExportDialog() {
    showImportExportDialog<List>(
      context,
      title: '黑名单',
      localFileName: () => 'blackMids',
      onExport: () => Utils.jsonEncoder.convert(
        _blackListController.blackMids.toList(),
      ),
      onImport: (json) {
        _blackListController.blackMids.addAll(Set<int>.from(json));
        Pref.blackMids = _blackListController.blackMids;
        setState(() {});
      },
    );
  }

  Widget _buildBody(LoadingState<List<BlackListItem>?> loadingState) {
    late final style = TextStyle(color: Theme.of(context).colorScheme.outline);
    return switch (loadingState) {
      Loading() => const SliverPrototypeExtentList(
        prototypeItem: MsgFeedTopSkeleton(),
        delegate: SliverSingleChildDelegate(
          count: 12,
          child: MsgFeedTopSkeleton(),
        ),
      ),
      Success(:final response) =>
        response != null && response.isNotEmpty
            ? SliverList.builder(
                itemCount: response.length,
                itemBuilder: (BuildContext context, int index) {
                  if (index == response.length - 1) {
                    _blackListController.onLoadMore();
                  }
                  final item = response[index];
                  return ListTile(
                    visualDensity: .standard,
                    onTap: () => Get.toNamed('/member?mid=${item.mid}'),
                    leading: NetworkImgLayer(
                      width: 45,
                      height: 45,
                      type: ImageType.avatar,
                      src: item.face,
                    ),
                    title: Text(
                      item.uname!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14),
                    ),
                    subtitle: Text(
                      '添加时间: ${DateFormatUtils.format(item.mtime, format: DateFormatUtils.longFormatDs)}',
                      maxLines: 1,
                      style: style,
                      overflow: TextOverflow.ellipsis,
                    ),
                    dense: true,
                    trailing: TextButton(
                      onPressed: () => _blackListController.onRemove(
                        context,
                        index,
                        item.uname,
                        item.mid,
                      ),
                      child: const Text('移除'),
                    ),
                  );
                },
              )
            : HttpError(onReload: _blackListController.onReload),
      Error(:final errMsg) => HttpError(
        errMsg: errMsg,
        onReload: _blackListController.onReload,
      ),
    };
  }
}
