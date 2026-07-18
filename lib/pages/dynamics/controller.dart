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
  bool _clearAllUpUpdatesOnNextResponse = false;
  final Set<int> _clearUpUpdateMidsOnNextResponse = <int>{};
  bool isQuerying = false;
  bool _pendingFollowUpRefresh = false;
  bool _isClosing = false;

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

  bool _clearUpUpdateForMid(Iterable<UpItem>? items, int mid) {
    var changed = false;
    if (items == null) {
      return changed;
    }
    for (final item in items) {
      if (item.mid == mid && item.hasUpdate == true) {
        item.hasUpdate = false;
        changed = true;
      }
    }
    return changed;
  }

  bool _clearFollowUpUpdateForMid(FollowUpModel? data, int mid) {
    final upChanged = _clearUpUpdateForMid(data?.upList, mid);
    final liveChanged = _clearUpUpdateForMid(data?.liveUsers?.items, mid);
    return upChanged || liveChanged;
  }

  void _markUpAsRead(int mid) {
    if (_clearFollowUpUpdateForMid(upState.value.dataOrNull, mid)) {
      upState.refresh();
    }
  }

  void _markUpAsReadAndClearNextResponse(int mid) {
    _markUpAsRead(mid);
    if (!_clearAllUpUpdatesOnNextResponse) {
      _clearUpUpdateMidsOnNextResponse.add(mid);
    }
  }

  void _applyPendingUpUpdateClears(FollowUpModel data) {
    if (_clearAllUpUpdatesOnNextResponse) {
      _clearFollowUpUpdates(data);
      _clearAllUpUpdatesOnNextResponse = false;
      _clearUpUpdateMidsOnNextResponse.clear();
      return;
    }

    for (final mid in _clearUpUpdateMidsOnNextResponse) {
      _clearFollowUpUpdateForMid(data, mid);
    }
    _clearUpUpdateMidsOnNextResponse.clear();
  }

  void _markNavigationSelectionAsRead() {
    if (isAllUpPage) {
      _markAllUpAsReadAndClearNextResponse();
    } else {
      _markUpAsReadAndClearNextResponse(currentMid.value);
    }
  }

  bool _clearUpUpdates(Iterable<UpItem>? items) {
    var changed = false;
    if (items == null) {
      return changed;
    }
    for (final item in items) {
      if (item.hasUpdate == true) {
        item.hasUpdate = false;
        changed = true;
      }
    }
    return changed;
  }

  bool _clearFollowUpUpdates(FollowUpModel? data) {
    final upChanged = _clearUpUpdates(data?.upList);
    final liveChanged = _clearUpUpdates(data?.liveUsers?.items);
    return upChanged || liveChanged;
  }

  void _markAllUpAsRead() {
    if (_clearFollowUpUpdates(upState.value.dataOrNull)) {
      upState.refresh();
    }
  }

  void _markAllUpAsReadAndClearNextResponse() {
    _markAllUpAsRead();
    _clearAllUpUpdatesOnNextResponse = true;
    _clearUpUpdateMidsOnNextResponse.clear();
  }

  void _refreshNavigationSelection() {
    // Keep the immediate UI update and the next follow-up response in sync.
    // A response already in flight may still contain the old red dot.
    _markNavigationSelectionAsRead();
  }

  @override
  void onInit() {
    super.onInit();
    tabController = TabController(
      length: DynamicsTabType.values.length,
      vsync: this,
      initialIndex: DynamicsTabType.all.index,
    );
    upPageController = PageController(
      initialPage: indexOfMid(currentMid.value),
    );
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
    if (_isClosing || isQuerying || _upEnd) return;
    isQuerying = true;

    try {
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
    } finally {
      _completeUpQuery();
    }
  }

  Future<void> queryAllUp() async {
    if (_isClosing || isQuerying || _upEnd) return;
    isQuerying = true;

    try {
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
    } finally {
      _completeUpQuery();
    }
  }

  Future<void> queryFollowUp() async {
    if (_isClosing || isQuerying) return;
    isQuerying = true;

    try {
      if (!accountService.isLogin.value) {
        upState.value = const Error(null);
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
          list.addAll(
            list1..removeWhere((_cacheUpList = list.toSet()).contains),
          );
        }
        if (!_showAllUp) {
          if (data.hasMore == false || data.offset.isNullOrEmpty) {
            _upEnd = true;
          }
        }
        _applyPendingUpUpdateClears(data);
        upState.value = Success(data);
      } else {
        upState.value = const Error(null);
      }
    } finally {
      _completeUpQuery();
    }
  }

  void onSelectUp(int mid) {
    final pageIndex = indexOfMid(mid);
    if (this.mid.value == mid) {
      currentMid.value = mid;
      tabController.index = DynamicsTabType.all.index;
      if (mid == -1) {
        _markAllUpAsReadAndClearNextResponse();
        unawaited(queryFollowUp());
      } else {
        _markUpAsRead(mid);
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

  Future<void> onNavigationRefresh() {
    _refreshNavigationSelection();
    animateToTop();
    return onRefresh();
  }

  void _refreshFollowUp() {
    if (_isClosing) {
      return;
    }
    if (isQuerying) {
      _pendingFollowUpRefresh = true;
      return;
    }
    _startFollowUpRefresh();
  }

  void _startFollowUpRefresh() {
    if (_showAllUp) {
      _upPage = 1;
      _cacheUpList = null;
    }
    unawaited(queryFollowUp());
  }

  void _completeUpQuery() {
    isQuerying = false;
    final shouldRefresh = _pendingFollowUpRefresh;
    _pendingFollowUpRefresh = false;
    if (!shouldRefresh || _isClosing) {
      return;
    }
    if (!accountService.isLogin.value) {
      upState.value = const Error(null);
      return;
    }
    _startFollowUpRefresh();
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

  void navigationToTopOrRefresh() {
    _refreshNavigationSelection();
    toTopOrRefresh();
  }

  @override
  void onClose() {
    _isClosing = true;
    _pendingFollowUpRefresh = false;
    tabController.dispose();
    upPageController.dispose();
    scrollController.dispose();
    super.onClose();
  }

  @override
  void onChangeAccount(bool isLogin) => _refreshFollowUp();
}
