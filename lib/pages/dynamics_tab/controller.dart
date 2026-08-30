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
  Future<void>? _activeQuery;
  Future<void>? _activeRefresh;
  bool _drainingPendingRefresh = false;
  bool _closing = false;

  late final mainController = Get.find<MainController>();
  final dynamicsController = Get.find<DynamicsController>();

  @override
  void onInit() {
    super.onInit();
    queryData();
  }

  @override
  Future<void> queryData([bool isRefresh = true]) {
    if (_closing) {
      return Future<void>.value();
    }
    final activeRefresh = _activeRefresh;
    if (activeRefresh != null) {
      return activeRefresh;
    }
    final activeQuery = _activeQuery;
    if (activeQuery != null || isLoading) {
      return activeQuery ?? Future<void>.value();
    }
    final request = super.queryData(isRefresh);
    _activeQuery = request;
    unawaited(
      request.then<void>(
        (_) => _finishQuery(request),
        onError: (Object error, StackTrace stackTrace) {
          _finishQuery(request);
        },
      ),
    );
    return request;
  }

  void _finishQuery(Future<void> request) {
    if (!identical(_activeQuery, request)) {
      return;
    }
    _activeQuery = null;
    if (_pendingRefresh &&
        _activeRefresh == null &&
        !_drainingPendingRefresh &&
        !_closing) {
      unawaited(_drainPendingRefresh());
    }
  }

  @override
  Future<void> onRefresh() {
    if (_closing) {
      return Future<void>.value();
    }
    if (isLoading || _activeQuery != null || _activeRefresh != null) {
      _pendingRefresh = true;
      return (_pendingRefreshCompleter ??= Completer<void>()).future;
    }
    return _performRefresh();
  }

  Future<void> _performRefresh() async {
    if (_closing) {
      return;
    }
    final activeRefresh = _activeRefresh;
    if (activeRefresh != null) {
      return activeRefresh;
    }
    final operation = _performRefreshBody();
    _activeRefresh = operation;
    try {
      await operation;
    } finally {
      if (identical(_activeRefresh, operation)) {
        _activeRefresh = null;
      }
      if (_pendingRefresh && !_drainingPendingRefresh && !_closing) {
        unawaited(_drainPendingRefresh());
      }
    }
  }

  Future<void> _performRefreshBody() async {
    // The refresh path calls the parent query directly so it can remain
    // behind the serialized request gate. Reapply the normal list-controller
    // refresh reset here instead of carrying over the previous page state.
    page = 1;
    isEnd = false;
    offset = '';
    await super.queryData();
    if (dynamicsType == .all && !_closing) {
      await mainController.syncDynamicsViewed();
    }
  }

  Future<void> _drainPendingRefresh() async {
    if (!_pendingRefresh || _drainingPendingRefresh || _closing) {
      return;
    }
    _drainingPendingRefresh = true;
    try {
      while (_pendingRefresh && !_closing) {
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
        }
      }
    } finally {
      _drainingPendingRefresh = false;
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
    if (!isLoading && _activeQuery == null && _activeRefresh == null) {
      loadingState.value = LoadingState.loading();
    }
    return onRefresh();
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
    _closing = true;
    _pendingRefresh = false;
    final pendingCompleter = _pendingRefreshCompleter;
    _pendingRefreshCompleter = null;
    if (pendingCompleter != null && !pendingCompleter.isCompleted) {
      pendingCompleter.complete();
    }
    super.onClose();
  }
}
