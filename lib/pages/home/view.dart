import 'package:PiliMax/common/style.dart';
import 'package:PiliMax/common/widgets/custom_height_widget.dart';
import 'package:PiliMax/common/widgets/image/network_img_layer.dart';
import 'package:PiliMax/common/widgets/scroll_physics.dart';
import 'package:PiliMax/pages/common/common_page.dart';
import 'package:PiliMax/pages/home/controller.dart';
import 'package:PiliMax/pages/home/home_preview_scope.dart';
import 'package:PiliMax/pages/main/controller.dart';
import 'package:PiliMax/pages/mine/controller.dart';
import 'package:PiliMax/utils/extension/get_ext.dart';
import 'package:PiliMax/utils/extension/size_ext.dart';
import 'package:PiliMax/utils/feed_back.dart';
import 'package:material_ui/material_ui.dart';
import 'package:get/get.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.preview = false});

  final bool preview;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends CommonPageState<HomePage>
    with AutomaticKeepAliveClientMixin {
  late ColorScheme _colorScheme;
  final _homeController = Get.putOrFind(HomeController.new);
  final _mainController = Get.find<MainController>();

  @override
  bool get needsCorrection => _homeController.hideTopBar;

  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _colorScheme = ColorScheme.of(context);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    Widget tabBar;
    if (_homeController.tabs.length > 1) {
      tabBar = Padding(
        padding: const EdgeInsets.only(top: 4),
        child: SizedBox(
          height: 42,
          width: double.infinity,
          child: TabBar(
            controller: _homeController.tabController,
            tabs: _homeController.tabs.map((e) => Tab(text: e.label)).toList(),
            isScrollable: true,
            dividerColor: Colors.transparent,
            dividerHeight: 0,
            splashBorderRadius: Style.mdRadius,
            tabAlignment: TabAlignment.center,
            onTap: (_) {
              feedBack();
              if (!_homeController.tabController.indexIsChanging) {
                _homeController.animateToTop();
              }
            },
          ),
        ),
      );
      if (_homeController.hideTopBar &&
          _mainController.barHideType == .instant) {
        tabBar = Material(
          color: _colorScheme.surface,
          child: tabBar,
        );
      }
    } else {
      tabBar = const SizedBox(height: 6);
    }
    return HomePreviewScope(
      enabled: widget.preview,
      child: Column(
        children: [
          if (!_mainController.useSideBar &&
              MediaQuery.sizeOf(context).isPortrait)
            customAppBar(),
          tabBar,
          Expanded(
            child: onBuild(
              tabBarView(
                controller: _homeController.tabController,
                children: _homeController.tabs.map((e) => e.page).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget customAppBar() {
    const padding = EdgeInsets.fromLTRB(14, 6, 14, 0);
    final child = Row(
      children: [
        searchBar(),
        const SizedBox(width: 4),
        msgBadge(_mainController),
        const SizedBox(width: 8),
        userAvatar(colorScheme: _colorScheme, mainController: _mainController),
      ],
    );
    if (_homeController.hideTopBar) {
      if (_mainController.barOffset case final barOffset?) {
        return Obx(
          () {
            final offset = barOffset.value;
            return CustomHeightWidget(
              offset: Offset(0, -offset),
              height: Style.topBarHeight - offset,
              child: Padding(
                padding: padding,
                child: child,
              ),
            );
          },
        );
      }
      if (_homeController.showTopBar case final showTopBar?) {
        return Obx(
          () => _HomeTopBarTransition(
            visible: showTopBar.value,
            child: SizedBox(
              height: Style.topBarHeight,
              child: Padding(padding: padding, child: child),
            ),
          ),
        );
      }
    }
    return Container(
      height: Style.topBarHeight,
      padding: padding,
      child: child,
    );
  }

  Widget searchBar() {
    const borderRadius = BorderRadius.all(Radius.circular(25));
    return Expanded(
      child: SizedBox(
        height: 44,
        child: Material(
          borderRadius: borderRadius,
          color: _colorScheme.onSecondaryContainer.withValues(alpha: 0.05),
          child: InkWell(
            borderRadius: borderRadius,
            splashColor: _colorScheme.primaryContainer.withValues(
              alpha: 0.3,
            ),
            onTap: () => Get.toNamed(
              '/search',
              parameters: _homeController.enableSearchWord
                  ? {'hintText': _homeController.defaultSearch.value}
                  : null,
            ),
            child: Row(
              children: [
                const SizedBox(width: 14),
                Icon(
                  Icons.search_outlined,
                  color: _colorScheme.onSecondaryContainer,
                  semanticLabel: '搜索',
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Obx(
                    () => Text(
                      _homeController.defaultSearch.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: _colorScheme.outline),
                    ),
                  ),
                ),
                const SizedBox(width: 5),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeTopBarTransition extends StatefulWidget {
  const _HomeTopBarTransition({required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  State<_HomeTopBarTransition> createState() => _HomeTopBarTransitionState();
}

class _HomeTopBarTransitionState extends State<_HomeTopBarTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );
  late final CurvedAnimation _transition = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOutCubicEmphasized,
  );
  bool _animationsEnabled = false;

  @override
  void initState() {
    super.initState();
    _controller.value = widget.visible ? 1 : 0;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animationsEnabled =
        TickerMode.valuesOf(context).enabled &&
        !(MediaQuery.maybeOf(context)?.disableAnimations ?? false);
    if (animationsEnabled == _animationsEnabled) return;

    _animationsEnabled = animationsEnabled;
    if (!animationsEnabled) {
      _controller.value = widget.visible ? 1 : 0;
    }
  }

  @override
  void didUpdateWidget(_HomeTopBarTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible == widget.visible) return;

    if (!_animationsEnabled) {
      _controller.value = widget.visible ? 1 : 0;
    } else if (widget.visible) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _transition.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizeTransition(
      alignment: Alignment.topCenter,
      sizeFactor: _transition,
      child: IgnorePointer(
        ignoring: !widget.visible,
        child: ExcludeSemantics(
          excluding: !widget.visible,
          child: FadeTransition(opacity: _transition, child: widget.child),
        ),
      ),
    );
  }
}

Widget userAvatar({
  required ColorScheme colorScheme,
  required MainController mainController,
}) {
  return Semantics(
    label: "我的",
    child: Obx(
      () {
        if (mainController.accountService.isLogin.value) {
          return Stack(
            clipBehavior: .none,
            children: [
              NetworkImgLayer(
                type: .avatar,
                width: 34,
                height: 34,
                src: mainController.accountService.face.value,
              ),
              Positioned.fill(
                child: Material(
                  type: .transparency,
                  child: InkWell(
                    onTap: mainController.toMinePage,
                    splashColor: colorScheme.primaryContainer.withValues(
                      alpha: 0.3,
                    ),
                    customBorder: const CircleBorder(),
                  ),
                ),
              ),
              Positioned(
                right: -4,
                bottom: -4,
                child: Obx(
                  () => MineController.anonymity.value
                      ? IgnorePointer(
                          child: Container(
                            padding: const .all(2),
                            decoration: BoxDecoration(
                              shape: .circle,
                              color: colorScheme.secondaryContainer,
                            ),
                            child: Icon(
                              size: 14,
                              MdiIcons.incognito,
                              color: colorScheme.onSecondaryContainer,
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ],
          );
        }
        return SizedBox(
          width: 38,
          height: 38,
          child: IconButton(
            tooltip: '点击登录',
            style: IconButton.styleFrom(
              padding: .zero,
              backgroundColor: colorScheme.onInverseSurface,
            ),
            onPressed: mainController.toMinePage,
            icon: Icon(
              Icons.person_rounded,
              size: 22,
              color: colorScheme.primary,
            ),
          ),
        );
      },
    ),
  );
}

Widget msgBadge(MainController mainController) {
  return Obx(
    () {
      if (mainController.accountService.isLogin.value) {
        final count = mainController.msgUnReadCount.value;
        final isNumBadge = mainController.msgBadgeMode == .number;
        return IconButton(
          tooltip: '消息',
          onPressed: () {
            mainController
              ..clearUnreadMsg()
              ..lastCheckUnreadAt = DateTime.now().millisecondsSinceEpoch;
            Get.toNamed('/whisper');
          },
          icon: Badge(
            isLabelVisible:
                mainController.msgBadgeMode != .hidden && count != null,
            alignment: isNumBadge
                ? const Alignment(0.0, -0.85)
                : const Alignment(1.0, -0.85),
            label: isNumBadge && count != null ? Text(count) : null,
            child: const Icon(Icons.notifications_none),
          ),
        );
      }
      return const SizedBox.shrink();
    },
  );
}
