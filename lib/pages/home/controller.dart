import 'dart:async';
import 'dart:math';

import 'package:PiliMax/http/api.dart';
import 'package:PiliMax/http/init.dart';
import 'package:PiliMax/models/common/home_tab_type.dart';
import 'package:PiliMax/pages/common/common_controller.dart';
import 'package:PiliMax/pages/main/controller.dart';
import 'package:PiliMax/services/account_service.dart';
import 'package:PiliMax/utils/storage.dart';
import 'package:PiliMax/utils/storage_key.dart';
import 'package:PiliMax/utils/storage_pref.dart';
import 'package:PiliMax/utils/wbi_sign.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class HomeController extends GetxController
    with GetSingleTickerProviderStateMixin, ScrollOrRefreshMixin {
  late List<HomeTabType> tabs;
  late TabController tabController;
  final RxInt currentIndex = 0.obs;

  RxBool? showTopBar;
  late final bool hideTopBar;

  bool enableSearchWord = Pref.enableSearchWord;
  late final RxString defaultSearch = ''.obs;
  late int lateCheckSearchAt = 0;

  ScrollOrRefreshMixin get controller => tabs[tabController.index].ctr();

  @override
  ScrollController get scrollController => controller.scrollController;

  AccountService accountService = Get.find<AccountService>();

  bool get isRcmdTab => tabs[currentIndex.value] == HomeTabType.rcmd;

  bool backToRcmdTab() {
    final rcmdIndex = tabs.indexOf(HomeTabType.rcmd);
    if (rcmdIndex == -1 || currentIndex.value == rcmdIndex) {
      return false;
    }
    tabController.animateTo(rcmdIndex);
    return true;
  }

  void _handleTabChange() {
    final index = tabController.index;
    if (currentIndex.value != index) {
      currentIndex.value = index;
    }
  }

  @override
  void onInit() {
    super.onInit();

    hideTopBar = !Pref.useSideBar && Pref.hideTopBar;
    if (hideTopBar) {
      final mainCtr = Get.find<MainController>();
      switch (mainCtr.barHideType) {
        case .instant:
          showTopBar = RxBool(true);
        case .sync:
          mainCtr.barOffset ??= RxDouble(0.0);
      }
    }

    if (enableSearchWord) {
      lateCheckSearchAt = DateTime.now().millisecondsSinceEpoch;
      querySearchDefault();
    }

    setTabConfig();
  }

  @override
  Future<void> onRefresh() {
    return controller.showRefresh().catchError((e) {
      if (kDebugMode) debugPrint(e.toString());
    });
  }

  void setTabConfig() {
    final tabs = GStorage.setting.get(SettingBoxKey.tabBarSort) as List?;
    if (tabs != null) {
      this.tabs = tabs.map((i) => HomeTabType.values[i]).toList();
    } else {
      this.tabs = HomeTabType.values;
    }

    final initialIndex = max(0, this.tabs.indexOf(HomeTabType.rcmd));
    currentIndex.value = initialIndex;
    tabController = TabController(
      initialIndex: initialIndex,
      length: this.tabs.length,
      vsync: this,
    )..addListener(_handleTabChange);
  }

  @override
  void dispose() {
    tabController
      ..removeListener(_handleTabChange)
      ..dispose();
    super.dispose();
  }

  Future<void> querySearchDefault() async {
    try {
      final res = await Request().get(
        Api.searchDefault,
        queryParameters: await WbiSign.makSign({'web_location': 333.1365}),
      );
      if (res.data['code'] == 0) {
        defaultSearch.value = res.data['data']?['name'] ?? '';
        // defaultSearch.value = res.data['data']?['show_name'] ?? '';
      }
    } catch (_) {}
  }
}
