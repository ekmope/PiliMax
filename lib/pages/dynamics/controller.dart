import 'dart:async';

import 'package:PiliMax/http/dynamics.dart';
import 'package:PiliMax/http/follow.dart';
import 'package:PiliMax/http/loading_state.dart';
import 'package:PiliMax/models/common/dynamic/dynamics_type.dart';
import 'package:PiliMax/models/dynamics/up.dart';
import 'package:PiliMax/models_new/follow/data.dart';
import 'package:PiliMax/pages/common/common_controller.dart';
import 'package:PiliMax/pages/dynamics_tab/controller.dart';
import 'package:PiliMax/services/account_service.dart';
import 'package:PiliMax/utils/accounts.dart';
import 'package:PiliMax/utils/extension/scroll_controller_ext.dart';
import 'package:PiliMax/utils/extension/string_ext.dart';
import 'package:PiliMax/utils/storage_pref.dart';
import 'package:easy_debounce/easy_throttle.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class DynamicsController extends GetxController
    with GetSingleTickerProviderStateMixin, ScrollOrRefreshMixin, AccountMixin {
  @override
  final ScrollController scrollController = ScrollController();
  late final TabController tabController;
  late final PageController upPageController;

  late final RxInt mid = (-1).obs;
  late final RxInt currentMid = (-1).obs;

  Set<int> tempBannedList = <int>{};

  final Rx<LoadingState<FollowUpModel>> upState =
      LoadingState<FollowUpModel>.loading().obs;
  late int _upPage = 1;
  late bool _upEnd = false;
  Set<UpItem>? _cacheUpList;
  late final _showAllUp = Pref.dynamicsShowAllFollowedUp;
  late bool showLiveUp = Pref.expandDynLivePanel;

  final upPanelPosition = Pref.upPanelPosition;

  @override
  final AccountService accountService = Get.find<AccountService>();

  DynamicsTabController? get controller {
    try {
      return Get.find<DynamicsTabController>(
        tag: currentUpTag,
      );
    } catch (_) {
      return null;
    }
  }

  String get currentUpTag => upTagForMid(currentMid.value);

  static String upTagForMid(int mid) => 'up-$mid';

  bool get isAllTab => isAllUpPage;
  bool get isAllUpPage => currentMid.value == -1;

  bool backToAllTab() {
    if (!isAllUpPage) {
      onSelectUp(-1);
      return true;
    }
    return false;
  }

  List<UpItem> get upPageItems {
    final items = <UpItem>[
      UpItem(face: '', uname: '全部动态', mid: -1),
    ];
    if (Pref.dynamicsShowSelfUp && accountService.isLogin.value) {
      items.add(
        UpItem(
          uname: '我',
          face: accountService.face.value,
          mid: Accounts.main.mid,
        ),
      );
    }
    if (upState.value case Success<FollowUpModel>(:final response)) {
      items.addAll(response.upList);
    }
    return items;
  }

  int indexOfMid(int mid) {
    final index = upPageItems.indexWhere((item) => item.mid == mid);
    if (index == -1) {
      return 0;
    }
    return index;
  }

  void _markUpAsRead(int mid) {
    var changed = false;
    for (final item in upPageItems) {
      if (item.mid == mid && item.hasUpdate == true) {
        item.hasUpdate = false;
        changed = true;
      }
    }
    if (changed) {
      upState.refresh();
    }
  }

  @override
  void onInit() {
    super.onInit();
    tabController = TabController(
      length: DynamicsTabType.values.length,
      vsync: this,
      initialIndex: DynamicsTabType.all.index,
    );
    upPageController = PageController(initialPage: indexOfMid(currentMid.value));
    queryFollowUp();
  }

  void onLoadMoreUp() {
    if (_showAllUp) {
      queryAllUp();
    } else {
      queryUpList();
    }
  }

  Future<void> queryUpList() async {
    if (isQuerying || _upEnd) return;
    isQuerying = true;

    final res = await DynamicsHttp.dynUpList(upState.value.data.offset);

    if (res case Success(:final response)) {
      if (response.hasMore == false || response.offset.isNullOrEmpty) {
        _upEnd = true;
      }
      final upData = upState.value.data
        ..hasMore = response.hasMore
        ..offset = response.offset;
      final list = response.upList;
      if (list != null && list.isNotEmpty) {
        upData.upList.addAll(list);
        upState.refresh();
      }
    }

    isQuerying = false;
  }

  Future<void> queryAllUp() async {
    if (isQuerying || _upEnd) return;
    isQuerying = true;

    final res = await FollowHttp.followings(
      vmid: Accounts.main.mid,
      pn: _upPage,
      orderType: 'attention',
      ps: 50,
    );

    if (res case Success(:final response)) {
      _upPage++;
      final list = response.list;
      if (list.isEmpty) {
        _upEnd = true;
      }
      upState
        ..value.data.upList.addAll(
          list..removeWhere((e) => _cacheUpList?.contains(e) == true),
        )
        ..refresh();
    }

    isQuerying = false;
  }

  late bool isQuerying = false;
  Future<void> queryFollowUp() async {
    if (isQuerying) return;
    isQuerying = true;

    if (!accountService.isLogin.value) {
      upState.value = const Error(null);
      isQuerying = false;
      return;
    }

    // reset
    _upEnd = false;
    if (_showAllUp) _upPage = 1;

    final res = await Future.wait([
      DynamicsHttp.followUp(),
      if (_showAllUp)
        FollowHttp.followings(
          vmid: Accounts.main.mid,
          pn: _upPage,
          orderType: 'attention',
          ps: 50,
        ),
    ]);

    final first = res.first;
    if (first case final Success<FollowUpModel> i) {
      final data = i.response;
      final second = res.elementAtOrNull(1);
      if (second case final Success<FollowData> j) {
        final data1 = j.response;
        final list1 = data1.list;

        _upPage++;
        if (list1.isEmpty || list1.length >= (data1.total ?? 0)) {
          _upEnd = true;
        }

        final list = data.upList;
        list.addAll(list1..removeWhere((_cacheUpList = list.toSet()).contains));
      }
      if (!_showAllUp) {
        if (data.hasMore == false || data.offset.isNullOrEmpty) {
          _upEnd = true;
        }
      }
      upState.value = Success(data);
    } else {
      upState.value = const Error(null);
    }

    isQuerying = false;
  }

  void onSelectUp(int mid) {
    final pageIndex = indexOfMid(mid);
    if (this.mid.value == mid) {
      currentMid.value = mid;
      tabController.index = DynamicsTabType.all.index;
      _markUpAsRead(mid);
      if (mid == -1) {
        queryFollowUp();
      }
      controller?.onReload();
      return;
    }

    this.mid.value = mid;
    currentMid.value = mid;
    tabController.index = DynamicsTabType.all.index;
    _markUpAsRead(mid);
    if (upPageController.hasClients) {
      upPageController.animateToPage(
        pageIndex,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void onUpPageChanged(int index) {
    final items = upPageItems;
    if (index < 0 || index >= items.length) {
      return;
    }
    final mid = items[index].mid;
    this.mid.value = mid;
    currentMid.value = mid;
    tabController.index = DynamicsTabType.all.index;
    _markUpAsRead(mid);
    if (index >= items.length - 3) {
      onLoadMoreUp();
    }
  }

  @override
  Future<void> onRefresh() {
    _refreshFollowUp();
    return controller?.showRefresh() ?? Future.value();
  }

  void _refreshFollowUp() {
    if (_showAllUp) {
      _upPage = 1;
      _cacheUpList = null;
    }
    queryFollowUp();
  }

  @override
  void animateToTop() {
    controller?.animateToTop();
    scrollController.animToTop();
  }

  @override
  void toTopOrRefresh() {
    final ctr = controller;
    if (ctr?.scrollController.hasClients == true) {
      EasyThrottle.throttle(
        'topOrRefresh',
        const Duration(milliseconds: 500),
        () {
          animateToTop();
          ctr!.showRefresh();
          _refreshFollowUp();
        },
      );
    } else {
      super.toTopOrRefresh();
    }
  }

  @override
  void onClose() {
    tabController.dispose();
    upPageController.dispose();
    scrollController.dispose();
    super.onClose();
  }

  @override
  void onChangeAccount(bool isLogin) => _refreshFollowUp();
}
