import 'dart:async';

import 'package:PiliMax/common/widgets/view_safe_area.dart';
import 'package:PiliMax/grpc/dyn.dart';
import 'package:PiliMax/http/loading_state.dart';
import 'package:PiliMax/http/msg.dart';
import 'package:PiliMax/models/common/dynamic/dynamic_badge_mode.dart';
import 'package:PiliMax/models/common/msg/msg_unread_type.dart';
import 'package:PiliMax/models/common/nav_bar_config.dart';
import 'package:PiliMax/pages/dynamics/controller.dart';
import 'package:PiliMax/pages/home/controller.dart';
import 'package:PiliMax/pages/mine/view.dart';
import 'package:PiliMax/services/account_service.dart';
import 'package:PiliMax/utils/extension/get_ext.dart';
import 'package:PiliMax/utils/extension/iterable_ext.dart';
import 'package:PiliMax/utils/feed_back.dart';
import 'package:PiliMax/utils/storage.dart';
import 'package:PiliMax/utils/storage_key.dart';
import 'package:PiliMax/utils/storage_pref.dart';
import 'package:PiliMax/utils/update.dart';
import 'package:collection/collection.dart';
import 'package:easy_debounce/easy_throttle.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class MainController extends GetxController
    with GetSingleTickerProviderStateMixin, AccountMixin {
  @override
  final AccountService accountService = Get.find<AccountService>();

  List<NavigationBarType> navigationBars = <NavigationBarType>[];

  RxDouble? barOffset;
  RxBool? showBottomBar;
  late final bool hideBottomBar;
  late final barHideType = Pref.barHideType;
  bool useBottomNav = false;
  late dynamic controller;
  final RxInt selectedIndex = 0.obs;

  final RxInt dynCount = 0.obs;
  late DynamicBadgeMode dynamicBadgeMode;
  late bool checkDynamic = Pref.checkDynamic;
  late int dynamicPeriod = Pref.dynamicPeriod * 60 * 1000;
  late int _lastCheckDynamicAt = 0;
  int _dynCountEpoch = 0;
  late bool hasDyn = false;
  late final dynamicController = Get.putOrFind(DynamicsController.new);

  late bool hasHome = false;
  late final homeController = Get.putOrFind(HomeController.new);

  late DynamicBadgeMode msgBadgeMode = Pref.msgBadgeMode;
  late Set<MsgUnReadType> msgUnReadTypes = Pref.msgUnReadTypeV2;
  late final RxString msgUnReadCount = ''.obs;
  late int lastCheckUnreadAt = 0;

  final enableMYBar = Pref.enableMYBar;
  final floatingNavBar = Pref.floatingNavBar;
  final useSideBar = Pref.useSideBar;
  final mainTabBarView = Pref.mainTabBarView;
  late final optTabletNav = Pref.optTabletNav;
  late final showNavBarLabel = Pref.showNavBarLabel.obs;

  late final RxBool directExitOnBack = Pref.directExitOnBack.obs;
  late bool showTrayIcon = Pref.showTrayIcon;
  late bool minimizeOnExit = Pref.minimizeOnExit;
  late bool pauseOnMinimize = Pref.pauseOnMinimize;
  late bool isPlaying = false;

  static const _period = 5 * 60 * 1000;
  late int _lastSelectTime = 0;

  @override
  void onInit() {
    super.onInit();
    if (Pref.autoUpdate) {
      Update.checkUpdate();
    }

    setNavBarConfig();

    controller = mainTabBarView
        ? TabController(
            vsync: this,
            initialIndex: selectedIndex.value,
            length: navigationBars.length,
          )
        : PageController(initialPage: selectedIndex.value);

    hideBottomBar =
        !useSideBar && navigationBars.length > 1 && Pref.hideBottomBar;
    if (hideBottomBar) {
      switch (barHideType) {
        case .instant:
          showBottomBar = RxBool(true);
        case .sync:
          barOffset ??= RxDouble(0.0);
      }
    }

    dynamicBadgeMode = Pref.dynamicBadgeMode;

    hasDyn = navigationBars.contains(NavigationBarType.dynamics);
    if (dynamicBadgeMode != DynamicBadgeMode.hidden) {
      if (hasDyn) {
        if (checkDynamic) {
          _lastCheckDynamicAt = DateTime.now().millisecondsSinceEpoch;
        }
        getUnreadDynamic();
      }
    }

    hasHome = navigationBars.contains(NavigationBarType.home);
    if (msgBadgeMode != DynamicBadgeMode.hidden) {
      if (hasHome) {
        lastCheckUnreadAt = DateTime.now().millisecondsSinceEpoch;
        queryUnreadMsg();
      }
    }
  }

  Future<int> _msgUnread() async {
    if (msgUnReadTypes.contains(MsgUnReadType.pm)) {
      final res = await MsgHttp.msgUnread();
      if (res case Success(:final response)) {
        return response.followUnread +
            response.unfollowUnread +
            response.bizMsgFollowUnread +
            response.bizMsgUnfollowUnread +
            response.unfollowPushMsg +
            response.customUnread;
      }
    }
    return 0;
  }

  Future<int> _msgFeedUnread() async {
    int count = 0;
    final remainTypes = Set<MsgUnReadType>.from(msgUnReadTypes)
      ..remove(MsgUnReadType.pm);
    if (remainTypes.isNotEmpty) {
      final res = await MsgHttp.msgFeedUnread();
      if (res case Success(:final response)) {
        for (final item in remainTypes) {
          switch (item) {
            case MsgUnReadType.pm:
              break;
            case MsgUnReadType.reply:
              count += response.reply;
              break;
            case MsgUnReadType.at:
              count += response.at;
              break;
            case MsgUnReadType.like:
              count += response.like;
              break;
            case MsgUnReadType.sysMsg:
              count += response.sysMsg;
              break;
          }
        }
      }
    }
    return count;
  }

  Future<void> queryUnreadMsg([bool isChangeType = false]) async {
    if (!accountService.isLogin.value ||
        !hasHome ||
        msgUnReadTypes.isEmpty ||
        msgBadgeMode == DynamicBadgeMode.hidden) {
      msgUnReadCount.value = '';
      return;
    }

    final res = await Future.wait([_msgUnread(), _msgFeedUnread()]);

    final count = res.sum;

    final countStr = count == 0
        ? ''
        : count > 99
        ? '99+'
        : count.toString();
    if (msgUnReadCount.value == countStr) {
      if (isChangeType) {
        msgUnReadCount.refresh();
      }
    } else {
      msgUnReadCount.value = countStr;
    }
  }

  void getUnreadDynamic() {
    if (!accountService.isLogin.value || !hasDyn) {
      return;
    }
    final requestEpoch = _dynCountEpoch;
    DynGrpc.dynRed().then((res) {
      if (res != null && requestEpoch == _dynCountEpoch) {
        setDynCount(res);
      }
    });
  }

  void setDynCount([int count = 0]) {
    if (!hasDyn) return;
    dynCount.value = count;
  }

  void clearDynCount() {
    _dynCountEpoch++;
    setDynCount();
  }

  void checkUnreadDynamic() {
    if (!hasDyn ||
        !accountService.isLogin.value ||
        dynamicBadgeMode == DynamicBadgeMode.hidden ||
        !checkDynamic) {
      return;
    }
    int now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastCheckDynamicAt >= dynamicPeriod) {
      _lastCheckDynamicAt = now;
      getUnreadDynamic();
    }
  }

  void setNavBarConfig() {
    List<int>? navBarSort =
        (GStorage.setting.get(SettingBoxKey.navBarSort) as List?)?.fromCast();
    late final List<NavigationBarType> navigationBars;
    if (navBarSort == null || navBarSort.isEmpty) {
      navigationBars = NavigationBarType.values;
    } else {
      navigationBars = navBarSort
          .map((i) => NavigationBarType.values[i])
          .toList();
    }
    this.navigationBars = navigationBars;
    final defPage = Pref.defaultHomePage;
    selectedIndex.value = navigationBars.indexOf(defPage);
  }

  void checkDefaultSearch([bool shouldCheck = false]) {
    if (hasHome && homeController.enableSearchWord) {
      if (shouldCheck &&
          navigationBars[selectedIndex.value] != NavigationBarType.home) {
        return;
      }
      int now = DateTime.now().millisecondsSinceEpoch;
      if (now - homeController.lateCheckSearchAt >= _period) {
        homeController
          ..lateCheckSearchAt = now
          ..querySearchDefault();
      }
    }
  }

  void checkUnread([bool shouldCheck = false]) {
    if (accountService.isLogin.value &&
        hasHome &&
        msgBadgeMode != DynamicBadgeMode.hidden) {
      if (shouldCheck &&
          navigationBars[selectedIndex.value] != NavigationBarType.home) {
        return;
      }
      int now = DateTime.now().millisecondsSinceEpoch;
      if (now - lastCheckUnreadAt >= _period) {
        lastCheckUnreadAt = now;
        queryUnreadMsg();
      }
    }
  }

  int? _mineIndex;
  void toMinePage() {
    _mineIndex ??= navigationBars.indexOf(NavigationBarType.mine);
    if (_mineIndex != -1) {
      setIndex(_mineIndex!);
    } else {
      Get.to(
        const Material(
          child: ViewSafeArea(top: true, child: MinePage(showBackBtn: true)),
        ),
      );
    }
  }

  void syncNavigationPage() {
    final targetIndex = selectedIndex.value;
    if (targetIndex < 0 || targetIndex >= navigationBars.length) {
      return;
    }

    if (mainTabBarView) {
      final tabController = controller as TabController;
      if (tabController.index != targetIndex) {
        tabController.index = targetIndex;
      }
      return;
    }

    final pageController = controller as PageController;
    if (!pageController.hasClients) {
      return;
    }
    final page = pageController.page;
    if (page == null || (page - targetIndex).abs() > 0.001) {
      pageController.jumpToPage(targetIndex);
    }
  }

  void toHomePage() {
    var index = navigationBars.indexOf(NavigationBarType.home);
    if (index == -1) {
      index = 0;
    }
    if (selectedIndex.value == index) {
      syncNavigationPage();
    } else {
      setIndex(index);
    }
  }

  void selectFromBottomBar(int value) {
    _setIndex(value, animate: true);
  }

  void setIndex(int value) {
    _setIndex(value, animate: false);
  }

  void _setIndex(int value, {required bool animate}) {
    feedBack();

    final currentNav = navigationBars[value];
    if (value != selectedIndex.value) {
      selectedIndex.value = value;
      if (mainTabBarView) {
        if (animate) {
          controller.animateTo(value);
        } else {
          controller.index = value;
        }
      } else {
        final pageController = controller as PageController;
        if (pageController.hasClients) {
          if (animate) {
            unawaited(
              pageController.animateToPage(
                value,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
              ),
            );
          } else {
            pageController.jumpToPage(value);
          }
        }
      }
      if (currentNav == NavigationBarType.home) {
        checkDefaultSearch();
        checkUnread();
      } else if (currentNav == NavigationBarType.dynamics) {
        clearDynCount();
      }
    } else {
      int now = DateTime.now().millisecondsSinceEpoch;
      if (currentNav == NavigationBarType.dynamics &&
          dynamicController.isAllUpPage) {
        clearDynCount();
      }
      if (now - _lastSelectTime < 500) {
        EasyThrottle.throttle(
          'topOrRefresh',
          const Duration(milliseconds: 500),
          () {
            if (currentNav == NavigationBarType.home) {
              homeController.onRefresh();
            } else if (currentNav == NavigationBarType.dynamics) {
              dynamicController.onNavigationRefresh();
            }
          },
        );
      } else {
        if (currentNav == NavigationBarType.home) {
          homeController.toTopOrRefresh();
        } else if (currentNav == NavigationBarType.dynamics) {
          dynamicController.navigationToTopOrRefresh();
        }
      }
      _lastSelectTime = now;
    }
  }

  void currentToTopOrRefresh() {
    final currentNav = navigationBars[selectedIndex.value];
    if (currentNav == NavigationBarType.home) {
      homeController.toTopOrRefresh();
    } else if (currentNav == NavigationBarType.dynamics) {
      dynamicController.toTopOrRefresh();
    }
  }

  void setSearchBar() {
    if (hasHome) {
      homeController.showTopBar?.value = true;
    }
  }

  @override
  void onClose() {
    barOffset?.close();
    controller.dispose();
    super.onClose();
  }

  @override
  void onChangeAccount(bool isLogin) {
    if (isLogin) {
      getUnreadDynamic();
    } else {
      clearDynCount();
    }
  }
}
