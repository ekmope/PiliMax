import 'package:PiliMax/http/follow.dart';
import 'package:PiliMax/http/loading_state.dart';
import 'package:PiliMax/http/member.dart';
import 'package:PiliMax/http/user.dart';
import 'package:PiliMax/models/common/follow_order_type.dart';
import 'package:PiliMax/models_new/follow/data.dart';
import 'package:PiliMax/models_new/follow/list.dart';
import 'package:PiliMax/pages/common/common_list_controller.dart';
import 'package:PiliMax/pages/follow/controller.dart';
import 'package:PiliMax/pilimax/forks/utils/storage.dart';
import 'package:PiliMax/utils/storage_key.dart';
import 'package:PiliMax/utils/storage_pref.dart';
import 'package:get/get.dart';

class FollowChildController
    extends CommonListController<FollowData, FollowItemModel> {
  FollowChildController(this.controller, this.mid, this.tagid);
  final FollowController? controller;
  final int? tagid;
  final int mid;
  int? total;

  late final loadSameFollow = controller?.isOwner == false;
  late final Rx<LoadingState<List<FollowItemModel>?>> sameState =
      LoadingState<List<FollowItemModel>?>.loading().obs;

  // Parent-owned pages share one sort state; standalone contact pages retain
  // the persisted value for their independent sorting control.
  late final Rx<FollowOrderType> _standaloneOrderType =
      Pref.followOrderType.obs;

  Rx<FollowOrderType> get orderType =>
      controller?.orderType ?? _standaloneOrderType;

  void setOrderType(FollowOrderType type) {
    if (controller != null) {
      controller!.setOrderType(type);
      return;
    }
    _standaloneOrderType.value = type;
    GStorage.setting.put(SettingBoxKey.followOrderType, type.index);
  }

  void toggleOrderType() {
    if (controller != null) {
      controller!.toggleOrderType();
      return;
    }
    final FollowOrderType type = orderType.value == .def ? .attention : .def;
    setOrderType(type);
    onReload();
  }

  @override
  void onInit() {
    super.onInit();
    queryData();
    if (loadSameFollow) {
      _loadSameFollow();
    }
  }

  @override
  List<FollowItemModel>? getDataList(FollowData response) {
    total = response.total;
    return response.list;
  }

  @override
  void checkIsEnd(int length) {
    if (total != null && length >= total!) {
      isEnd = true;
    }
  }

  @override
  bool customHandleResponse(bool isRefresh, Success<FollowData> response) {
    if (controller != null) {
      try {
        if (controller!.isOwner &&
            tagid == null &&
            isRefresh &&
            controller!.followState.value.isSuccess) {
          controller!.tabs
            ..[0].count = response.response.total
            ..refresh();
        }
      } catch (_) {}
    }
    return false;
  }

  @override
  Future<LoadingState<FollowData>> customGetData() {
    final order = orderType.value.type;
    if (tagid != null) {
      return MemberHttp.followUpGroup(
        mid: mid,
        tagid: tagid,
        pn: page,
        orderType: order,
      );
    }

    return FollowHttp.followings(
      vmid: mid,
      pn: page,
      orderType: order,
    );
  }

  Future<void> _loadSameFollow() async {
    final res = await UserHttp.sameFollowing(mid: mid);
    if (res case Success(:final response)) {
      sameState.value = Success(response.list);
    }
  }
}
