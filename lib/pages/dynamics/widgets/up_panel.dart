import 'package:PiliMax/common/assets.dart';
import 'package:PiliMax/common/widgets/image/network_img_layer.dart';
import 'package:PiliMax/models/common/dynamic/up_panel_position.dart';
import 'package:PiliMax/models/common/image_type.dart';
import 'package:PiliMax/models/dynamics/up.dart';
import 'package:PiliMax/pages/dynamics/controller.dart';
import 'package:PiliMax/pages/live_follow/view.dart';
import 'package:PiliMax/utils/accounts.dart';
import 'package:PiliMax/utils/extension/num_ext.dart';
import 'package:PiliMax/utils/feed_back.dart';
import 'package:PiliMax/utils/page_utils.dart';
import 'package:PiliMax/utils/platform_utils.dart';
import 'package:PiliMax/utils/storage.dart';
import 'package:PiliMax/utils/storage_key.dart';
import 'package:PiliMax/utils/storage_pref.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';

class UpPanel extends StatefulWidget {
  const UpPanel({
    required this.dynamicsController,
    required this.createDynamicButton,
    super.key,
  });

  final DynamicsController dynamicsController;
  final Widget createDynamicButton;

  @override
  State<UpPanel> createState() => _UpPanelState();
}

class _UpPanelState extends State<UpPanel> {
  static const double _topItemExtent = 70;
  static const double _topPanelHeight = 76;
  static const double _sideItemExtent = 76;
  static const double _sideActionExtent = 60;

  late final controller = widget.dynamicsController;
  late final isTop = controller.upPanelPosition == UpPanelPosition.top;
  late final Worker _currentMidWorker;
  int? _lastScrollSignature;
  bool _scrollScheduled = false;

  void toFollowPage() => Get.to(const LiveFollowPage());

  @override
  void initState() {
    super.initState();
    _currentMidWorker = ever<int>(
      controller.currentMid,
      (_) => _scheduleEnsureCurrentVisible(),
    );
    _scheduleEnsureCurrentVisible();
  }

  @override
  void dispose() {
    _currentMidWorker.dispose();
    super.dispose();
  }

  double get _itemExtent => isTop ? _topItemExtent : _sideItemExtent;

  double get _actionExtent => isTop ? _topItemExtent : _sideActionExtent;

  int _visibleLiveCount(List<LiveUserItem>? liveList) {
    if (!controller.showLiveUp || liveList == null) {
      return 0;
    }
    return liveList.length;
  }

  void _scheduleEnsureCurrentVisible() {
    if (_scrollScheduled) {
      return;
    }
    _scrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollScheduled = false;
      if (mounted) {
        _ensureCurrentVisible();
      }
    });
  }

  void _ensureCurrentVisible() {
    final scrollController = controller.scrollController;
    if (!scrollController.hasClients) {
      return;
    }

    final position = scrollController.position;
    final currentIndex = controller.indexOfMid(controller.currentMid.value);
    final liveList = controller.upState.value.dataOrNull?.liveUsers?.items;
    final fixedExtent =
        _actionExtent + _actionExtent + _visibleLiveCount(liveList) * _itemExtent;
    final currentCenter = fixedExtent + currentIndex * _itemExtent + _itemExtent / 2;
    final target = (currentCenter - position.viewportDimension / 2)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();

    if ((position.pixels - target).abs() < 2) {
      return;
    }
    scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  void _scheduleIfPanelRangeChanged(
    List<UpItem> upList,
    List<LiveUserItem>? liveList,
  ) {
    final signature = Object.hash(
      controller.currentMid.value,
      upList.length,
      liveList?.length ?? 0,
      controller.showLiveUp,
      Pref.dynamicsShowSelfUp,
    );
    if (_lastScrollSignature == signature) {
      return;
    }
    _lastScrollSignature = signature;
    _scheduleEnsureCurrentVisible();
  }

  @override
  Widget build(BuildContext context) {
    final accountService = controller.accountService;
    if (!accountService.isLogin.value) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final upData = controller.upState.value.data;
    final List<UpItem> upList = upData.upList;
    final List<LiveUserItem>? liveList = upData.liveUsers?.items;
    _scheduleIfPanelRangeChanged(upList, liveList);
    return CustomScrollView(
      scrollDirection: isTop ? Axis.horizontal : Axis.vertical,
      physics: const AlwaysScrollableScrollPhysics(),
      controller: controller.scrollController,
      slivers: [
        SliverToBoxAdapter(child: widget.createDynamicButton),
        SliverToBoxAdapter(
          child: InkWell(
            onTap: () {
              setState(() {
                controller.showLiveUp = !controller.showLiveUp;
              });
              _scheduleEnsureCurrentVisible();
            },
            onLongPress: toFollowPage,
            onSecondaryTap: PlatformUtils.isMobile ? null : toFollowPage,
            child: SizedBox(
              width: isTop ? _topItemExtent : null,
              height: isTop ? _topPanelHeight : _sideActionExtent,
              child: Container(
                alignment: Alignment.center,
                padding: isTop
                    ? const EdgeInsets.only(left: 12, right: 6)
                    : null,
                child: Text.rich(
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.primary,
                  ),
                  TextSpan(
                    children: [
                      TextSpan(
                        text: 'Live(${upData.liveUsers?.count ?? 0})',
                      ),
                      if (!isTop) ...[
                        const TextSpan(text: '\n'),
                        WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: Icon(
                            controller.showLiveUp
                                ? Icons.expand_less
                                : Icons.expand_more,
                            size: 12,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ] else
                        WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: Icon(
                            controller.showLiveUp
                                ? Icons.keyboard_arrow_right
                                : Icons.keyboard_arrow_left,
                            color: theme.colorScheme.primary,
                            size: 14,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (controller.showLiveUp && liveList != null && liveList.isNotEmpty)
          SliverList.builder(
            itemCount: liveList.length,
            itemBuilder: (context, index) {
              return upItemBuild(theme, liveList[index]);
            },
          ),
        SliverToBoxAdapter(
          child: upItemBuild(theme, UpItem(face: '', uname: '全部动态', mid: -1)),
        ),
        StreamBuilder<BoxEvent>(
          stream: GStorage.setting.watch().where(
            (event) => event.key == SettingBoxKey.dynamicsShowSelfUp,
          ),
          builder: (context, _) {
            if (!Pref.dynamicsShowSelfUp) {
              return const SliverToBoxAdapter(child: SizedBox.shrink());
            }
            return SliverToBoxAdapter(
              child: Obx(
                () => upItemBuild(
                  theme,
                  UpItem(
                    uname: '我',
                    face: accountService.face.value,
                    mid: Accounts.main.mid,
                  ),
                ),
              ),
            );
          },
        ),
        if (upList.isNotEmpty)
          SliverList.builder(
            itemCount: upList.length,
            itemBuilder: (context, index) {
              return upItemBuild(theme, upList[index]);
            },
          ),
        if (!isTop) const SliverToBoxAdapter(child: SizedBox(height: 200)),
      ],
    );
  }

  void _onSelect(UpItem data) {
    controller.onSelectUp(data.mid);

    setState(() {});
  }

  Widget upItemBuild(ThemeData theme, UpItem data) {
    final isLive = data is LiveUserItem;

    final isAll = data.mid == -1;
    void toMemberPage() => Get.toNamed('/member?mid=${data.mid}');

    Widget avatar;
    if (isAll) {
      avatar = DecoratedBox(
        decoration: const BoxDecoration(
          shape: .circle,
          color: Color(0xFF5CB67B),
        ),
        child: Image.asset(
          width: 38,
          height: 38,
          cacheWidth: 38.cacheSize(context),
          Assets.logo2,
          color: Colors.white,
        ),
      );
    } else {
      avatar = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: NetworkImgLayer(
          width: 38,
          height: 38,
          src: data.face,
          type: ImageType.avatar,
        ),
      );
      if (isLive) {
        avatar = Stack(
          clipBehavior: .none,
          children: [
            avatar,
            Positioned(
              top: isLive && !isTop ? -5 : 0,
              right: -6,
              child: Badge(
                label: const Text(' Live '),
                textColor: theme.colorScheme.onSecondaryContainer,
                backgroundColor: theme.colorScheme.secondaryContainer
                    .withValues(alpha: 0.75),
              ),
            ),
          ],
        );
      } else if (data.hasUpdate ?? false) {
        avatar = Stack(
          clipBehavior: .none,
          children: [
            avatar,
            Positioned(
              top: 0,
              right: 4,
              child: Badge(
                smallSize: 8,
                backgroundColor: theme.colorScheme.primary,
              ),
            ),
          ],
        );
      }
    }

    return SizedBox(
      height: _sideItemExtent,
      width: isTop ? _topItemExtent : null,
      child: InkWell(
        onTap: () {
          feedBack();
          if (isLive) {
            PageUtils.toLiveRoom(data.roomId);
          } else {
            _onSelect(data);
          }
        },
        // onDoubleTap: isLive ? () => _onSelect(data) : null,
        onLongPress: !isAll ? toMemberPage : null,
        onSecondaryTap: !isAll && !PlatformUtils.isMobile ? toMemberPage : null,
        child: Obx(
          () {
            final currentMid = controller.currentMid.value;
            final isCurrent = isLive || currentMid == data.mid;
            return Opacity(
              opacity: isCurrent ? 1 : 0.6,
              child: Column(
                spacing: 4,
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  avatar,
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      isTop ? '${data.uname}\n' : data.uname!,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: currentMid == data.mid
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outline,
                        height: 1.1,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
