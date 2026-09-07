import 'package:PiliMax/common/widgets/scroll_physics.dart'
    show clampingScrollPhysics, tabBarView;
import 'package:PiliMax/http/loading_state.dart';
import 'package:PiliMax/models/common/dynamic/dynamics_type.dart';
import 'package:PiliMax/models/common/dynamic/up_panel_position.dart';
import 'package:PiliMax/models/dynamics/up.dart';
import 'package:PiliMax/pages/common/common_page.dart';
import 'package:PiliMax/pages/dynamics/controller.dart';
import 'package:PiliMax/pages/dynamics/widgets/up_panel.dart';
import 'package:PiliMax/pages/dynamics_create/view.dart';
import 'package:PiliMax/pages/dynamics_tab/view.dart';
import 'package:PiliMax/pages/main/controller.dart';
import 'package:PiliMax/utils/extension/get_ext.dart';
import 'package:PiliMax/utils/storage_key.dart';
import 'package:PiliMax/utils/storage_pref.dart';
import 'package:PiliMax/pilimax/forks/utils/storage.dart';
import 'package:material_ui/material_ui.dart' hide DraggableScrollableSheet;
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart' show BoxEvent;

class DynamicsPage extends StatefulWidget {
  const DynamicsPage({super.key});

  @override
  State<DynamicsPage> createState() => _DynamicsPageState();
}

class _DynamicsPageState extends CommonPageState<DynamicsPage>
    with AutomaticKeepAliveClientMixin {
  final _dynamicsController = Get.putOrFind(DynamicsController.new);
  UpPanelPosition get upPanelPosition => _dynamicsController.upPanelPosition;
  late final MainController _mainController = Get.find<MainController>();

  @override
  bool get wantKeepAlive => true;

  Widget _createDynamicBtn(
    ThemeData theme, {
    bool compact = false,
    bool isRight = true,
  }) {
    final isTop = upPanelPosition == .top;
    return Center(
      child: Container(
        width: compact ? 34 : (isTop ? 70 : 64),
        height: compact ? 34 : (isTop ? 76 : 60),
        margin: compact
            ? (isRight
                  ? const EdgeInsets.only(right: 16)
                  : const EdgeInsets.only(left: 16))
            : null,
        alignment: Alignment.center,
        padding: compact
            ? EdgeInsets.zero
            : EdgeInsets.only(
                left: isTop ? 12 : 0,
                right: isTop ? 6 : 0,
              ),
        child: IconButton(
          tooltip: '发布动态',
          style: ButtonStyle(
            padding: const WidgetStatePropertyAll(EdgeInsets.zero),
            backgroundColor: WidgetStatePropertyAll(
              theme.colorScheme.secondaryContainer,
            ),
          ),
          onPressed: () => CreateDynPanel.onCreateDyn(context),
          icon: Icon(
            Icons.add,
            size: 18,
            color: theme.colorScheme.onSecondaryContainer,
          ),
        ),
      ),
    );
  }

  Widget upPanelPart(ThemeData theme, {bool includeCreateButton = true}) {
    final isTop = upPanelPosition == .top;
    final needBg = upPanelPosition.index > 2;
    return Material(
      type: needBg ? .canvas : .transparency,
      color: needBg ? theme.colorScheme.surface : null,
      child: SizedBox(
        width: isTop ? null : 64,
        height: isTop ? 76 : null,
        child: NotificationListener<ScrollEndNotification>(
          onNotification: (notification) {
            final metrics = notification.metrics;
            if (metrics.pixels >= metrics.maxScrollExtent - 300) {
              _dynamicsController.onLoadMoreUp();
            }
            return false;
          },
          child: Obx(
            () => _buildUpPanel(
              _dynamicsController.upState.value,
              includeCreateButton: includeCreateButton,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUpPanel(
    LoadingState<FollowUpModel> upState, {
    required bool includeCreateButton,
  }) {
    return switch (upState) {
      Loading() => const SizedBox.shrink(),
      Success<FollowUpModel>() => UpPanel(
        dynamicsController: _dynamicsController,
        createDynamicButton: includeCreateButton
            ? _createDynamicBtn(Theme.of(context))
            : const SizedBox.shrink(),
      ),
      Error() => Center(
        child: IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () => _dynamicsController
            ..upState.value = LoadingState<FollowUpModel>.loading()
            ..queryFollowUp(),
        ),
      ),
    };
  }

  bool get checkPage =>
      _mainController.navigationBars[0] != .dynamics &&
      _mainController.selectedIndex.value == 0;

  @override
  bool onNotificationType1(UserScrollNotification notification) {
    if (checkPage) {
      return false;
    }
    return super.onNotificationType1(notification);
  }

  @override
  bool onNotificationType2(ScrollNotification notification) {
    if (checkPage) {
      return false;
    }
    return super.onNotificationType2(notification);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);

    return StreamBuilder<BoxEvent>(
      stream: GStorage.setting.watch(
        key: SettingBoxKey.dynamicsCategoryTabBar,
      ),
      builder: (context, _) {
        final useCategoryTabs = Pref.dynamicsCategoryTabBar;
        Widget? drawer;
        Widget? endDrawer;
        PreferredSizeWidget? appBar;

        Widget child = useCategoryTabs
            ? tabBarView(
                controller: _dynamicsController.tabController,
                children: DynamicsTabType.values
                    .map((type) => DynamicsTabPage(dynamicsType: type))
                    .toList(growable: false),
              )
            : Obx(
                () {
                  final items = _dynamicsController.upPageItems;
                  return PageView.builder(
                    controller: _dynamicsController.upPageController,
                    physics: clampingScrollPhysics,
                    onPageChanged: _dynamicsController.onUpPageChanged,
                    itemCount: items.length,
                    itemBuilder: (context, index) => DynamicsTabPage(
                      key: ValueKey('dyn-up-${items[index].mid}'),
                      upItem: items[index],
                    ),
                  );
                },
              );

        switch (upPanelPosition) {
          case UpPanelPosition.top:
            child = Column(
              children: [
                upPanelPart(theme, includeCreateButton: !useCategoryTabs),
                Expanded(child: child),
              ],
            );
          case UpPanelPosition.leftFixed:
            child = Row(
              children: [
                upPanelPart(theme, includeCreateButton: !useCategoryTabs),
                Expanded(child: child),
              ],
            );
          case UpPanelPosition.rightFixed:
            child = Row(
              children: [
                Expanded(child: child),
                upPanelPart(theme, includeCreateButton: !useCategoryTabs),
              ],
            );
          case UpPanelPosition.leftDrawer:
            drawer = upPanelPart(
              theme,
              includeCreateButton: !useCategoryTabs,
            );
            if (!useCategoryTabs) {
              appBar = AppBar(
                primary: false,
                toolbarHeight: 50,
                backgroundColor: Colors.transparent,
                actions: [
                  Builder(
                    builder: (context) => IconButton(
                      tooltip: 'UP',
                      icon: const Icon(Icons.people_alt_outlined),
                      onPressed: () => Scaffold.of(context).openDrawer(),
                    ),
                  ),
                ],
              );
            }
          case UpPanelPosition.rightDrawer:
            endDrawer = upPanelPart(
              theme,
              includeCreateButton: !useCategoryTabs,
            );
            if (!useCategoryTabs) {
              appBar = AppBar(
                primary: false,
                leading: Builder(
                  builder: (context) => IconButton(
                    tooltip: 'UP',
                    icon: const Icon(Icons.people_alt_outlined),
                    onPressed: () => Scaffold.of(context).openEndDrawer(),
                  ),
                ),
                leadingWidth: 50,
                toolbarHeight: 50,
                backgroundColor: Colors.transparent,
              );
            }
        }

        if (useCategoryTabs) {
          Widget? leading;
          late final Widget actions;
          switch (upPanelPosition) {
            case UpPanelPosition.top ||
                UpPanelPosition.leftFixed ||
                UpPanelPosition.rightFixed:
              actions = _createDynamicBtn(theme, compact: true);
            case UpPanelPosition.leftDrawer:
              leading = const DrawerButton();
              actions = _createDynamicBtn(theme, compact: true);
            case UpPanelPosition.rightDrawer:
              leading = _createDynamicBtn(theme, compact: true, isRight: false);
              actions = const EndDrawerButton();
          }
          appBar = PreferredSize(
            preferredSize: const Size.fromHeight(50),
            child: Row(
              children: [
                ?leading,
                Expanded(
                  child: TabBar(
                    dividerHeight: 0,
                    isScrollable: true,
                    tabAlignment: .start,
                    dividerColor: Colors.transparent,
                    labelColor: theme.colorScheme.primary,
                    indicatorColor: theme.colorScheme.primary,
                    controller: _dynamicsController.tabController,
                    unselectedLabelColor: theme.colorScheme.onSurface,
                    labelStyle:
                        TabBarTheme.of(context).labelStyle?.copyWith(
                          fontSize: 13,
                        ) ??
                        const TextStyle(fontSize: 13),
                    tabs: DynamicsTabType.values
                        .map((type) => Tab(text: type.label))
                        .toList(growable: false),
                    onTap: (index) {
                      if (!_dynamicsController.tabController.indexIsChanging) {
                        _dynamicsController.animateToTop();
                      }
                    },
                  ),
                ),
                actions,
              ],
            ),
          );
        }

        return Scaffold(
          resizeToAvoidBottomInset: false,
          backgroundColor: Colors.transparent,
          appBar: appBar,
          drawer: drawer,
          endDrawer: endDrawer,
          body: onBuild(child),
        );
      },
    );
  }
}
