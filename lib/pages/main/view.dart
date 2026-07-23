import 'dart:async' show unawaited;
import 'dart:io';

import 'package:PiliMax/common/assets.dart';
import 'package:PiliMax/common/constants.dart';
import 'package:PiliMax/common/style.dart';
import 'package:PiliMax/common/widgets/floating_navigation_bar.dart';
import 'package:PiliMax/common/widgets/flutter/pop_scope.dart';
import 'package:PiliMax/common/widgets/flutter/tabs.dart';
import 'package:PiliMax/common/widgets/image/network_img_layer.dart';
import 'package:PiliMax/common/widgets/route_aware_mixin.dart';
import 'package:PiliMax/models/common/nav_bar_config.dart';
import 'package:PiliMax/pages/home/view.dart';
import 'package:PiliMax/pages/main/controller.dart';
import 'package:PiliMax/plugin/pl_player/controller.dart';
import 'package:PiliMax/plugin/pl_player/models/play_status.dart';
import 'package:PiliMax/services/route_restore_service.dart';
import 'package:PiliMax/utils/android/android_helper.dart';
import 'package:PiliMax/utils/app_scheme.dart';
import 'package:PiliMax/utils/device_utils.dart';
import 'package:PiliMax/utils/extension/context_ext.dart';
import 'package:PiliMax/utils/extension/size_ext.dart';
import 'package:PiliMax/utils/extension/theme_ext.dart';
import 'package:PiliMax/utils/mobile_observer.dart';
import 'package:PiliMax/utils/platform_utils.dart';
import 'package:PiliMax/utils/storage.dart';
import 'package:PiliMax/utils/storage_key.dart';
import 'package:PiliMax/utils/storage_pref.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:get/get.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:win32/win32.dart' as kernel32;
import 'package:window_manager/window_manager.dart';

enum _MainBackAction {
  dynamicsRoot,
  homeRecommended,
  firstNavigation,
  exit,
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends PopScopeState<MainApp>
    with
        RouteAware,
        RouteAwareMixin,
        WidgetsBindingObserver,
        WindowListener,
        TrayListener {
  final _mainController = Get.put(MainController());
  final _navigationKey = GlobalKey();
  late final _setting = GStorage.setting;
  late final List<Worker> _backPopWorkers;
  late EdgeInsets _padding;
  late ThemeData theme;
  Brightness? _brightness;
  bool _navigationSyncScheduled = false;

  @override
  bool get initCanPop => _allowAndroidPredictiveExit;

  bool get _supportsPredictiveBack =>
      Platform.isAndroid && DeviceUtils.sdkInt >= 33;

  bool get _allowAndroidPredictiveExit =>
      _supportsPredictiveBack && _backAction == _MainBackAction.exit;

  _MainBackAction get _backAction {
    if (_isOnDynamicsSubTab) {
      return _MainBackAction.dynamicsRoot;
    }
    if (_isOnHomeSubTab) {
      return _MainBackAction.homeRecommended;
    }
    if (!_mainController.directExitOnBack.value &&
        _mainController.selectedIndex.value != 0) {
      return _MainBackAction.firstNavigation;
    }
    return _MainBackAction.exit;
  }

  bool get _isOnHomeSubTab {
    if (!_mainController.hasHome) {
      return false;
    }
    return _mainController.navigationBars[_mainController
                .selectedIndex
                .value] ==
            NavigationBarType.home &&
        !_mainController.homeController.isRcmdTab;
  }

  bool get _isOnDynamicsSubTab {
    if (!_mainController.hasDyn) {
      return false;
    }
    return _mainController.navigationBars[_mainController
                .selectedIndex
                .value] ==
            NavigationBarType.dynamics &&
        !_mainController.dynamicController.isAllTab;
  }

  void _syncAndroidPredictiveBack() {
    if (canPopNotifier.value != _allowAndroidPredictiveExit) {
      canPopNotifier.value = _allowAndroidPredictiveExit;
    }
  }

  void _recordMainRestoreState() {
    final selectedIndex = _mainController.selectedIndex.value;
    if (selectedIndex < 0 ||
        selectedIndex >= _mainController.navigationBars.length) {
      return;
    }

    String? homeTab;
    if (_mainController.hasHome) {
      final homeController = _mainController.homeController;
      final homeIndex = homeController.currentIndex.value;
      if (homeIndex >= 0 && homeIndex < homeController.tabs.length) {
        homeTab = homeController.tabs[homeIndex].name;
      }
    }

    unawaited(
      RouteRestoreService.updateMainState(
        navigation: _mainController.navigationBars[selectedIndex].name,
        homeTab: homeTab,
      ),
    );
  }

  void _onMainNavigationChanged() {
    _syncAndroidPredictiveBack();
    _recordMainRestoreState();
  }

  void _onHomeTabChanged() {
    _syncAndroidPredictiveBack();
    _recordMainRestoreState();
  }

  void _restoreMainState(MainRestoreState state) {
    if (_mainController.hasHome) {
      if (state.homeTab case final homeTab?) {
        _mainController.homeController.restoreTab(homeTab);
      }
    }
    _mainController.restoreNavigation(state.navigation);
    _scheduleNavigationPageSync();
    _recordMainRestoreState();
  }

  Future<void> _restoreRoute() async {
    final shouldRecordCurrentState = await RouteRestoreService.restoreIfNeeded(
      restoreMainState: _restoreMainState,
    );
    if (mounted) {
      if (shouldRecordCurrentState) {
        _recordMainRestoreState();
      }
      RouteRestoreService.captureCurrentRoute();
    }
  }

  void _scheduleNavigationPageSync() {
    if (_navigationSyncScheduled) {
      return;
    }
    _navigationSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _navigationSyncScheduled = false;
      if (mounted) {
        _mainController.syncNavigationPage();
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _backPopWorkers = [
      ever<int>(
        _mainController.selectedIndex,
        (_) => _onMainNavigationChanged(),
      ),
      ever<bool>(
        _mainController.directExitOnBack,
        (_) => _syncAndroidPredictiveBack(),
      ),
    ];
    if (_mainController.hasDyn) {
      _backPopWorkers.add(
        ever<int>(
          _mainController.dynamicController.currentMid,
          (_) => _syncAndroidPredictiveBack(),
        ),
      );
    }
    if (_mainController.hasHome) {
      _backPopWorkers.add(
        ever<int>(
          _mainController.homeController.currentIndex,
          (_) => _onHomeTabChanged(),
        ),
      );
    }
    _recordMainRestoreState();
    _syncAndroidPredictiveBack();
    addObserverMobile(this);
    if (Platform.isAndroid) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_restoreRoute());
      });
    }
    if (PlatformUtils.isDesktop) {
      windowManager
        ..addListener(this)
        ..setPreventClose(true);
      if (_mainController.showTrayIcon) {
        trayManager.addListener(this);
        _handleTray();
      }
    } else {
      // FlutterSmartDialog throws
      PiliScheme.init();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _padding = MediaQuery.viewPaddingOf(context);
    theme = Theme.of(context);
    final brightness = theme.brightness;
    NetworkImgLayer.reduce =
        NetworkImgLayer.reduceLuxColor != null && brightness.isDark;
    if (PlatformUtils.isDesktop) {
      if (_brightness != brightness) {
        _brightness = brightness;
        windowManager.setBrightness(brightness);
      }
    }
    if (!_mainController.useSideBar) {
      final size = MediaQuery.sizeOf(context);
      if (Pref.autoSideBar) {
        _mainController.useBottomNav = size.width < Pref.sideBarThreshold;
      } else {
        _mainController.useBottomNav = size.isPortrait;
      }
    }
    _scheduleNavigationPageSync();
  }

  @override
  void didPopNext() {
    addObserverMobile(this);
    _mainController
      ..checkUnreadDynamic()
      ..checkDefaultSearch(true)
      ..checkUnread(_mainController.useBottomNav);
    _scheduleNavigationPageSync();
    _recordMainRestoreState();
    super.didPopNext();
  }

  @override
  void didPushNext() {
    removeObserverMobile(this);
    super.didPushNext();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _recordMainRestoreState();
      unawaited(RouteRestoreService.saveLatestRoute());
      return;
    }
    if (state == AppLifecycleState.resumed) {
      _mainController
        ..checkUnreadDynamic()
        ..checkDefaultSearch(true)
        ..checkUnread(_mainController.useBottomNav);
    }
  }

  @override
  void dispose() {
    if (PlatformUtils.isDesktop) {
      trayManager.removeListener(this);
      windowManager.removeListener(this);
    }
    removeObserverMobile(this);
    for (final worker in _backPopWorkers) {
      worker.dispose();
    }
    PiliScheme.listener?.cancel();
    GStorage.close();
    super.dispose();
  }

  @override
  void onWindowMaximize() {
    _setting.put(SettingBoxKey.isWindowMaximized, true);
  }

  @override
  void onWindowUnmaximize() {
    _setting.put(SettingBoxKey.isWindowMaximized, false);
  }

  @override
  Future<void> onWindowMoved() async {
    if (PlPlayerController.instance?.isDesktopPip ?? false) {
      return;
    }
    final Offset offset = await windowManager.getPosition();
    _setting.put(SettingBoxKey.windowPosition, [offset.dx, offset.dy]);
  }

  @override
  Future<void> onWindowResized() async {
    if (PlPlayerController.instance?.isDesktopPip ?? false) {
      return;
    }
    final Rect bounds = await windowManager.getBounds();
    _setting.putAll({
      SettingBoxKey.windowSize: [bounds.width, bounds.height],
      SettingBoxKey.windowPosition: [bounds.left, bounds.top],
    });
  }

  @override
  void onWindowClose() {
    if (_mainController.showTrayIcon && _mainController.minimizeOnExit) {
      windowManager.hide();
      _onHideWindow();
    } else {
      _onClose();
    }
  }

  Future<void> _onClose() async {
    await GStorage.compact();
    await GStorage.close();
    await trayManager.destroy();
    if (Platform.isWindows) {
      // flutter_inappwebview
      // 6.2.0-beta.2+ https://github.com/pichillilorenzo/flutter_inappwebview/issues/2482
      // 6.1.5 https://github.com/pichillilorenzo/flutter_inappwebview/issues/2512#issuecomment-3031039587
      final hProcess = kernel32.GetCurrentProcess();
      kernel32.TerminateProcess(hProcess, 0);
    } else {
      exit(0);
    }
  }

  @override
  void onWindowMinimize() {
    _onHideWindow();
  }

  @override
  void onWindowRestore() {
    _onShowWindow();
  }

  void _onHideWindow() {
    if (_mainController.pauseOnMinimize) {
      if (PlPlayerController.instance case final player?) {
        if (_mainController.isPlaying = player.playerStatus.isPlaying) {
          player.pause();
        }
      } else {
        _mainController.isPlaying = false;
      }
    }
  }

  void _onShowWindow() {
    if (_mainController.pauseOnMinimize && _mainController.isPlaying) {
      PlPlayerController.instance?.play();
    }
  }

  @override
  Future<void> onTrayIconMouseDown() async {
    if (await windowManager.isVisible()) {
      _onHideWindow();
      windowManager.hide();
    } else {
      _onShowWindow();
      windowManager.show();
    }
  }

  @override
  Future<void> onTrayIconRightMouseDown() async {
    // ignore: deprecated_member_use
    trayManager.popUpContextMenu(bringAppToFront: true);
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        windowManager.show();
      case 'exit':
        _onClose();
    }
  }

  Future<void> _handleTray() async {
    if (Platform.isWindows) {
      await trayManager.setIcon(Assets.logoIco);
    } else {
      await trayManager.setIcon(Assets.logoLarge);
    }
    if (!Platform.isLinux) {
      await trayManager.setToolTip(Constants.appName);
    }

    Menu trayMenu = Menu(
      items: [
        MenuItem(key: 'show', label: '显示窗口'),
        MenuItem.separator(),
        MenuItem(key: 'exit', label: '退出 ${Constants.appName}'),
      ],
    );
    await trayManager.setContextMenu(trayMenu);
  }

  @pragma('vm:prefer-inline')
  static void _onBack() {
    if (Platform.isAndroid) {
      unawaited(_clearRouteRestoreAndBack());
    }
  }

  static Future<void> _clearRouteRestoreAndBack() async {
    try {
      await RouteRestoreService.markIntentionalExit();
    } finally {
      PiliAndroidHelper.back();
    }
  }

  @override
  void onPopInvokedWithResult(bool didPop, Object? result) {
    if (didPop) {
      if (Platform.isAndroid) {
        unawaited(RouteRestoreService.markIntentionalExit());
      }
      return;
    }
    switch (_backAction) {
      case _MainBackAction.dynamicsRoot:
        _mainController.dynamicController.backToAllTab();
        _syncAndroidPredictiveBack();
      case _MainBackAction.homeRecommended:
        _mainController.homeController.backToRcmdTab();
        _syncAndroidPredictiveBack();
      case _MainBackAction.firstNavigation:
        _mainController
          ..selectNavigation(0)
          ..barOffset?.value = 0.0
          ..showBottomBar?.value = true
          ..setSearchBar();
      case _MainBackAction.exit:
        if (!_allowAndroidPredictiveExit) {
          _onBack();
        }
    }
  }

  Widget? get _bottomNav {
    Widget? bottomNav;
    if (_mainController.navigationBars.length > 1) {
      if (_mainController.floatingNavBar) {
        bottomNav = Obx(
          () => FloatingNavigationBar(
            labelBehavior: _mainController.showNavBarLabel.value
                ? NavigationDestinationLabelBehavior.alwaysShow
                : NavigationDestinationLabelBehavior.alwaysHide,
            onDestinationSelected: _mainController.selectNavigation,
            selectedIndex: _mainController.selectedIndex.value,
            destinations: _mainController.navigationBars
                .map(
                  (e) => FloatingNavigationDestination(
                    label: e.label,
                    icon: _buildIcon(type: e),
                    selectedIcon: _buildIcon(type: e, selected: true),
                  ),
                )
                .toList(),
          ),
        );
      } else if (_mainController.enableMYBar) {
        bottomNav = Obx(
          () => NavigationBar(
            maintainBottomViewPadding: true,
            labelBehavior: _mainController.showNavBarLabel.value
                ? NavigationDestinationLabelBehavior.alwaysShow
                : NavigationDestinationLabelBehavior.alwaysHide,
            onDestinationSelected: _mainController.selectNavigation,
            selectedIndex: _mainController.selectedIndex.value,
            destinations: _mainController.navigationBars
                .map(
                  (e) => NavigationDestination(
                    label: e.label,
                    icon: _buildIcon(type: e),
                    selectedIcon: _buildIcon(type: e, selected: true),
                  ),
                )
                .toList(),
          ),
        );
      } else {
        bottomNav = Obx(
          () => BottomNavigationBar(
            currentIndex: _mainController.selectedIndex.value,
            onTap: _mainController.selectNavigation,
            iconSize: 16,
            selectedFontSize: 12,
            unselectedFontSize: 12,
            showSelectedLabels: _mainController.showNavBarLabel.value,
            showUnselectedLabels: _mainController.showNavBarLabel.value,
            type: .fixed,
            items: _mainController.navigationBars
                .map(
                  (e) => BottomNavigationBarItem(
                    label: e.label,
                    icon: _buildIcon(type: e),
                    activeIcon: _buildIcon(type: e, selected: true),
                  ),
                )
                .toList(),
          ),
        );
      }

      if (_mainController.hideBottomBar) {
        if (_mainController.barOffset case final barOffset?) {
          return Obx(
            () => FractionalTranslation(
              translation: Offset(0.0, barOffset.value / Style.topBarHeight),
              child: bottomNav,
            ),
          );
        }
        if (_mainController.showBottomBar case final showBottomBar?) {
          return Obx(
            () => AnimatedSlide(
              curve: Curves.easeInOutCubicEmphasized,
              duration: const Duration(milliseconds: 500),
              offset: Offset(0, showBottomBar.value ? 0 : 1),
              child: bottomNav,
            ),
          );
        }
      }
    }

    return bottomNav;
  }

  Widget _sideBar(ThemeData theme) {
    return _mainController.navigationBars.length > 1
        ? context.isTablet && _mainController.optTabletNav
              ? Obx(() {
                  final showLabel = _mainController.showNavBarLabel.value;
                  return Column(
                    children: [
                      const SizedBox(height: 25),
                      userAndSearchVertical(theme),
                      const Spacer(flex: 2),
                      Expanded(
                        flex: 5,
                        child: SizedBox(
                          width: showLabel ? 130 : 80,
                          child: NavigationDrawer(
                            backgroundColor: Colors.transparent,
                            tilePadding: const .symmetric(
                              vertical: 5,
                              horizontal: 12,
                            ),
                            indicatorShape: const RoundedRectangleBorder(
                              borderRadius: .all(.circular(16)),
                            ),
                            onDestinationSelected:
                                _mainController.selectNavigation,
                            selectedIndex: _mainController.selectedIndex.value,
                            children: _mainController.navigationBars
                                .map(
                                  (e) => NavigationDrawerDestination(
                                    label: showLabel
                                        ? Text(e.label)
                                        : const SizedBox.shrink(),
                                    icon: _buildIcon(type: e),
                                    selectedIcon: _buildIcon(
                                      type: e,
                                      selected: true,
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      ),
                    ],
                  );
                })
              : Obx(
                  () => NavigationRail(
                    groupAlignment: 0.5,
                    selectedIndex: _mainController.selectedIndex.value,
                    onDestinationSelected: _mainController.selectNavigation,
                    labelType: _mainController.showNavBarLabel.value
                        ? NavigationRailLabelType.selected
                        : NavigationRailLabelType.none,
                    leading: userAndSearchVertical(theme),
                    destinations: _mainController.navigationBars
                        .map(
                          (e) => NavigationRailDestination(
                            label: Text(e.label),
                            icon: _buildIcon(type: e),
                            selectedIcon: _buildIcon(type: e, selected: true),
                          ),
                        )
                        .toList(),
                  ),
                )
        : Container(
            width: 80,
            padding: const .only(top: 10),
            child: userAndSearchVertical(theme),
          );
  }

  List<Widget> get _navigationPages => List.generate(
    _mainController.navigationBars.length,
    (index) => Obx(
      () => HeroMode(
        enabled: _mainController.selectedIndex.value == index,
        child: _mainController.navigationBars[index].page,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (_mainController.mainTabBarView) {
      child = CustomTabBarView(
        key: _navigationKey,
        scrollDirection: _mainController.useBottomNav ? .horizontal : .vertical,
        physics: const NeverScrollableScrollPhysics(),
        controller: _mainController.controller,
        children: _navigationPages,
      );
    } else {
      child = PageView(
        key: _navigationKey,
        physics: const NeverScrollableScrollPhysics(),
        controller: _mainController.controller,
        children: _navigationPages,
      );
    }

    Widget? bottomNav;
    if (_mainController.useBottomNav) {
      bottomNav = _bottomNav;
      child = Row(children: [Expanded(child: child)]);
    } else {
      child = Row(
        children: [
          _sideBar(theme),
          VerticalDivider(
            width: 1,
            endIndent: _padding.bottom,
            color: theme.colorScheme.outline.withValues(alpha: 0.06),
          ),
          Expanded(child: child),
        ],
      );
    }

    child = Scaffold(
      extendBody: true,
      resizeToAvoidBottomInset: false,
      appBar: AppBar(toolbarHeight: 0),
      body: Padding(
        padding: EdgeInsets.only(
          left: _mainController.useBottomNav ? _padding.left : 0.0,
          right: _padding.right,
        ),
        child: child,
      ),
      bottomNavigationBar: bottomNav,
    );

    if (PlatformUtils.isMobile) {
      child = AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness: theme.brightness.reverse,
        ),
        child: child,
      );
    }

    if (PlatformUtils.isMobile && _padding.top > 0) {
      child = Stack(
        children: [
          child,
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: _padding.top,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _mainController.currentToTopOrRefresh,
            ),
          ),
        ],
      );
    }

    return child;
  }

  Widget _buildIcon({required NavigationBarType type, bool selected = false}) {
    final icon = selected ? type.selectIcon : type.icon;
    return type == .dynamics
        ? Obx(() {
            final dynCount = _mainController.dynCount.value;
            return Badge(
              isLabelVisible: dynCount > 0,
              label: _mainController.dynamicBadgeMode == .number
                  ? Text(dynCount.toString())
                  : null,
              padding: const .symmetric(horizontal: 6),
              child: icon,
            );
          })
        : icon;
  }

  Widget userAndSearchVertical(ThemeData theme) {
    return Column(
      children: [
        userAvatar(theme: theme, mainController: _mainController),
        const SizedBox(height: 8),
        msgBadge(_mainController),
        IconButton(
          tooltip: '搜索',
          icon: const Icon(Icons.search_outlined, semanticLabel: '搜索'),
          onPressed: () => Get.toNamed('/search'),
        ),
      ],
    );
  }
}
