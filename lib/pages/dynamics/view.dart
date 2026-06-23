import 'package:PiliMax/common/widgets/scroll_physics.dart';
import 'package:PiliMax/http/loading_state.dart';
import 'package:PiliMax/models/common/dynamic/up_panel_position.dart';
import 'package:PiliMax/models/dynamics/up.dart';
import 'package:PiliMax/pages/common/common_page.dart';
import 'package:PiliMax/pages/dynamics/controller.dart';
import 'package:PiliMax/pages/dynamics/widgets/up_panel.dart';
import 'package:PiliMax/pages/dynamics_create/view.dart';
import 'package:PiliMax/pages/dynamics_tab/view.dart';
import 'package:PiliMax/pages/main/controller.dart';
import 'package:PiliMax/utils/extension/get_ext.dart';
import 'package:flutter/material.dart' hide DraggableScrollableSheet;
import 'package:get/get.dart';

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

  Widget _createDynamicBtn(ThemeData theme) {
    final isTop = upPanelPosition == .top;
    return Center(
      child: Container(
        width: isTop ? 70 : 64,
        height: isTop ? 76 : 60,
        alignment: Alignment.center,
        padding: EdgeInsets.only(
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

  Widget upPanelPart(ThemeData theme) {
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
          child: Obx(() => _buildUpPanel(_dynamicsController.upState.value)),
        ),
      ),
    );
  }

  Widget _buildUpPanel(LoadingState<FollowUpModel> upState) {
    return switch (upState) {
      Loading() => const SizedBox.shrink(),
      Success<FollowUpModel>() => UpPanel(
        dynamicsController: _dynamicsController,
        createDynamicButton: _createDynamicBtn(Theme.of(context)),
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

    Widget? drawer;
    Widget? endDrawer;

    PreferredSizeWidget? appBar;

    Widget child = Obx(
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
            upPanelPart(theme),
            Expanded(child: child),
          ],
        );
      case UpPanelPosition.leftFixed:
        child = Row(
          children: [
            upPanelPart(theme),
            Expanded(child: child),
          ],
        );
      case UpPanelPosition.rightFixed:
        child = Row(
          children: [
            Expanded(child: child),
            upPanelPart(theme),
          ],
        );
      case UpPanelPosition.leftDrawer:
        drawer = upPanelPart(theme);
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
      case UpPanelPosition.rightDrawer:
        endDrawer = upPanelPart(theme);
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

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.transparent,
      appBar: appBar,
      drawer: drawer,
      endDrawer: endDrawer,
      body: onBuild(child),
    );
  }
}
