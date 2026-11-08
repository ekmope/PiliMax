import 'package:PiliMax/common/style.dart';
import 'package:PiliMax/common/widgets/button/icon_button.dart';
import 'package:PiliMax/common/widgets/image/network_img_layer.dart';
import 'package:PiliMax/common/widgets/progress_bar/segment_progress_bar.dart';
import 'package:PiliMax/pages/common/slide/common_slide_page.dart';
import 'package:PiliMax/pages/video/controller.dart';
import 'package:PiliMax/plugin/pl_player/controller.dart';
import 'package:PiliMax/utils/duration_utils.dart';
import 'package:PiliMax/utils/scroll_offset_helper.dart';
import 'package:PiliMax/pilimax/forks/utils/storage.dart';
import 'package:PiliMax/utils/storage_key.dart';
import 'package:extended_nested_scroll_view/extended_nested_scroll_view.dart';
import 'package:PiliMax/pilimax/common/widgets/extended_visibility_detector.dart';
import 'package:material_ui/material_ui.dart';
import 'package:get/get.dart';

class ViewPointsPage extends CommonSlidePage {
  const ViewPointsPage({
    super.key,
    super.enableSlide,
    required this.videoDetailController,
    required this.plPlayerController,
  });

  final VideoDetailController videoDetailController;
  final PlPlayerController? plPlayerController;

  @override
  State<ViewPointsPage> createState() => _ViewPointsPageState();
}

class _ViewPointsPageState extends State<ViewPointsPage>
    with SingleTickerProviderStateMixin, CommonSlideMixin {
  VideoDetailController get videoDetailController =>
      widget.videoDetailController;
  PlPlayerController? get plPlayerController => widget.plPlayerController;

  late final int currentIndex;
  late Key _key;
  late bool _isNested;

  @override
  void initState() {
    super.initState();
    final positionSeconds =
        videoDetailController.plPlayerController.position.value;
    currentIndex = videoDetailController.viewPointList.indexWhere((segment) {
      final from = segment.from;
      final to = segment.to;
      return from != null &&
          to != null &&
          positionSeconds >= from &&
          positionSeconds < to;
    });
    if (currentIndex > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToCurrent());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = PrimaryScrollController.of(context);
    _isNested = controller is ExtendedNestedScrollController;
    _key = ValueKey(controller.hashCode);
  }

  void _jumpToCurrent() {
    final itemCount = videoDetailController.viewPointList.length;
    if (!mounted || currentIndex <= 0 || currentIndex >= itemCount) return;

    final controller = PrimaryScrollController.of(context);
    if (!controller.hasClients) return;
    final (offset, remain) = calcFixedItemOffset(
      index: currentIndex,
      itemCount: itemCount,
      topPadding: 7,
      bottomPadding: MediaQuery.viewPaddingOf(context).bottom + 100,
    );

    if (_isNested && controller is ExtendedNestedScrollController) {
      final positions = controller.nestedPositions;
      if (positions.isEmpty) return;
      final position = positions.first;
      final target = adjustScrollOffset(
        offset: offset,
        remain: remain,
        viewportDimension: position.viewportDimension,
      ).clamp(position.minScrollExtent, position.maxScrollExtent).toDouble();
      position.localJumpTo(target);
    } else {
      final positions = controller.positions;
      if (positions.length != 1) return;
      final position = positions.single;
      final target = adjustScrollOffset(
        offset: offset,
        remain: remain,
        viewportDimension: position.viewportDimension,
      ).clamp(position.minScrollExtent, position.maxScrollExtent).toDouble();
      position.jumpTo(target);
    }
  }

  @override
  Widget buildPage(ThemeData theme) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        primary: false,
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        title: const Text('分段信息'),
        toolbarHeight: 45,
        actions: [
          const Text(
            '分段进度条 ',
            style: TextStyle(fontSize: 16),
          ),
          Obx(
            () => Transform.scale(
              alignment: Alignment.centerLeft,
              scale: 0.8,
              child: Switch(
                value: videoDetailController.showVP.value,
                onChanged: (value) {
                  videoDetailController.showVP.value = value;
                  if (plPlayerController?.tempPlayerConf != true) {
                    GStorage.setting.put(
                      SettingBoxKey.showViewPointsOverlay,
                      value,
                    );
                  }
                },
              ),
            ),
          ),
          iconButton(
            context: context,
            size: 30,
            icon: const Icon(Icons.clear),
            tooltip: '关闭',
            onPressed: Get.back,
          ),
          const SizedBox(width: 16),
        ],
        shape: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outline.withValues(alpha: 0.1),
          ),
        ),
      ),
      body: enableSlide ? slideList(theme) : buildList(theme),
    );
  }

  @override
  Widget buildList(ThemeData theme) {
    final child = ListView.builder(
      key: _key,
      itemExtent: 112,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.only(
        top: 7,
        bottom: MediaQuery.viewPaddingOf(context).bottom + 100,
      ),
      itemCount: videoDetailController.viewPointList.length,
      itemBuilder: (context, index) {
        final segment = videoDetailController.viewPointList[index];
        final isCurr = currentIndex == index;
        return _buildItem(theme.colorScheme, segment, isCurr);
      },
    );
    if (_isNested) {
      return ExtendedVisibilityDetector(
        uniqueKey: const ValueKey(ViewPointsPage),
        child: child,
      );
    }
    return child;
  }

  Widget _buildItem(
    ColorScheme colorScheme,
    ViewPointSegment segment,
    bool isCurr,
  ) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: segment.from != null
            ? () {
                Get.back();
                plPlayerController?.seekTo(
                  Duration(seconds: segment.from!),
                  isSeek: false,
                );
              }
            : null,
        child: Padding(
          padding: const .symmetric(horizontal: Style.safeSpace, vertical: 5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              NetworkImgLayer(
                src: segment.url,
                width: 160,
                height: 100,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  spacing: 10,
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      segment.title ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: isCurr
                          ? TextStyle(
                              fontWeight: FontWeight.bold,
                              color: colorScheme.primary,
                            )
                          : null,
                    ),
                    Text(
                      '${segment.from != null ? DurationUtils.formatDuration(segment.from) : ''} - '
                      '${segment.to != null ? DurationUtils.formatDuration(segment.to) : ''}',
                      style: TextStyle(color: colorScheme.outline),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
