import 'dart:async';

import 'package:PiliMax/http/dynamics.dart';
import 'package:PiliMax/http/loading_state.dart';
import 'package:PiliMax/http/msg.dart';
import 'package:PiliMax/models/common/dynamic/dynamics_type.dart';
import 'package:PiliMax/models/dynamics/result.dart';
import 'package:PiliMax/pages/common/common_list_controller.dart';
import 'package:PiliMax/pages/dynamics/controller.dart';
import 'package:PiliMax/pages/main/controller.dart';
import 'package:PiliMax/services/account_service.dart';
import 'package:PiliMax/utils/extension/scroll_controller_ext.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

class DynamicsTabController
    extends CommonListController<DynamicsDataModel, DynamicItemModel>
    with AccountMixin {
  DynamicsTabController({required this.dynamicsType});
  final DynamicsTabType dynamicsType;

  String offset = '';
  int? mid;
  bool _pendingRefresh = false;
  Completer<void>? _pendingRefreshCompleter;

  late final mainController = Get.find<MainController>();
  final dynamicsController = Get.find<DynamicsController>();

  @override
  void onInit() {
    super.onInit();
    queryData();
  }

  @override
  Future<void> onRefresh() {
    if (isLoading) {
      _pendingRefresh = true;
      return (_pendingRefreshCompleter ??= Completer<void>()).future;
    }
    return _performRefresh();
  }

  Future<void> _performRefresh() async {
    try {
      if (dynamicsType == .all) {
        mainController.markDynamicsViewed();
      }
      offset = '';
      await super.onRefresh();
    } finally {
      await _drainPendingRefresh();
    }
  }

  Future<void> _drainPendingRefresh() async {
    if (!_pendingRefresh) {
      return;
    }
    _pendingRefresh = false;
    final pendingCompleter = _pendingRefreshCompleter;
    _pendingRefreshCompleter = null;
    try {
      await _performRefresh();
      if (pendingCompleter != null && !pendingCompleter.isCompleted) {
        pendingCompleter.complete();
      }
    } catch (error, stackTrace) {
      if (pendingCompleter != null && !pendingCompleter.isCompleted) {
        pendingCompleter.completeError(error, stackTrace);
      }
      rethrow;
    }
  }

  @override
  List<DynamicItemModel>? getDataList(DynamicsDataModel response) {
    offset = response.offset ?? '';
    return response.items;
  }

  @override
  Future<LoadingState<DynamicsDataModel>> customGetData() =>
      DynamicsHttp.followDynamic(
        type: dynamicsType,
        offset: offset,
        mid: mid,
        tempBannedList: dynamicsController.tempBannedList,
      );

  Future<void> onRemove(int index, dynamic dynamicId) async {
    final res = await MsgHttp.removeDynamic(dynIdStr: dynamicId);
    if (res.isSuccess) {
      loadingState
        ..value.data!.removeAt(index)
        ..refresh();
      SmartDialog.showToast('删除成功');
    } else {
      res.toast();
    }
  }

  @override
  Future<void> onReload() {
    scrollController.jumpToTop();
    if (isLoading) {
      return onRefresh();
    }
    return super.onReload();
  }

  void onBlock(int index) {
    if (dynamicsType != .up) {
      loadingState
        ..value.data!.removeAt(index)
        ..refresh();
    }
  }

  void onUnfold(DynamicItemModel item, int index) {
    try {
      final list = loadingState.value.data!;
      final ids = item.modules.moduleFold!.ids!;
      final flag = index + ids.length + 1;
      for (int i = index + 1; i < flag; i++) {
        list[i].visible = true;
      }
      item.modules.moduleFold = null;
      loadingState.refresh();
    } catch (_) {}
  }

  @override
  void onChangeAccount(bool isLogin) => onReload();

  @override
  void onClose() {
    _pendingRefresh = false;
    final pendingCompleter = _pendingRefreshCompleter;
    _pendingRefreshCompleter = null;
    if (pendingCompleter != null && !pendingCompleter.isCompleted) {
      pendingCompleter.complete();
    }
    super.onClose();
  }
}
