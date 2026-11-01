import 'dart:async' show StreamSubscription;

import 'package:PiliMax/common/widgets/progress_bar/audio_video_progress_bar.dart';
import 'package:PiliMax/common/widgets/progress_bar/segment_progress_bar.dart';
import 'package:PiliMax/pages/video/controller.dart';
import 'package:PiliMax/plugin/pl_player/controller.dart';
import 'package:PiliMax/plugin/pl_player/view/view.dart';
import 'package:PiliMax/utils/extension/theme_ext.dart';
import 'package:PiliMax/utils/feed_back.dart';
import 'package:PiliMax/utils/platform_utils.dart';
import 'package:material_ui/material_ui.dart';
import 'package:get/get.dart';

class BottomControl extends StatefulWidget {
  const BottomControl({
    super.key,
    required this.playerKey,
    required this.maxWidth,
    required this.isFullScreen,
    required this.animCtr,
    required this.controller,
    required this.buildBottomControl,
    required this.videoDetailController,
    this.isPipMode = false,
  });

  final GlobalKey playerKey;
  final double maxWidth;
  final bool isFullScreen;
  final AnimationController animCtr;
  final PlPlayerController controller;
  final ValueGetter<Widget> buildBottomControl;
  final VideoDetailController videoDetailController;
  final bool isPipMode;

  @override
  State<BottomControl> createState() => _BottomControlState();
}

class _BottomControlState extends State<BottomControl> {
  final _progressBarKey = GlobalKey();
  StreamSubscription? _scrollListener;

  PlPlayerController get controller => widget.controller;
  VideoDetailController get videoDetailController =>
      widget.videoDetailController;
  bool get isFullScreen => widget.isFullScreen;
  bool get isPipMode => widget.isPipMode;

  @override
  void initState() {
    super.initState();
    _listenToScroll();
  }

  void _listenToScroll() {
    _scrollListener = videoDetailController.scrollRatio.listen((ratio) {
      if (!isFullScreen && !isPipMode && ratio >= 1.0) {
        controller.clearHoverPreview(restartControls: true);
      }
    });
  }

  @override
  void didUpdateWidget(covariant BottomControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, controller)) {
      oldWidget.controller.clearHoverPreview();
    }
    if (!identical(oldWidget.videoDetailController, videoDetailController)) {
      _scrollListener?.cancel();
      _listenToScroll();
    }
  }

  @override
  void dispose() {
    _scrollListener?.cancel();
    controller.clearHoverPreview();
    super.dispose();
  }

  void onDragStart(ThumbDragDetails duration) {
    feedBack();
    controller.onSeekStart(duration.seconds);
  }

  void onDragUpdate(ThumbDragDetails duration) {
    if (!controller.isFileSource && controller.showSeekPreview) {
      controller.updatePreviewIndex(duration.seconds);
    }
    controller.seekPosition.value = duration.seconds;
  }

  void onSeek(int milliseconds) {
    controller
      ..clearHoverPreview()
      ..position.value = milliseconds ~/ 1000
      ..onSeekEnd()
      ..seekTo(Duration(milliseconds: milliseconds), isSeek: false);
  }

  void _onHover(double dx, int seconds) {
    if (widget.animCtr.isAnimating ||
        !controller.showControls.value ||
        controller.isSeeking.value ||
        isPipMode ||
        controller.isPipMode ||
        (!isFullScreen && videoDetailController.scrollRatio.value >= 1.0)) {
      return;
    }
    final bar = _progressBarKey.currentContext?.findRenderObject();
    final player = widget.playerKey.currentContext?.findRenderObject();
    if (bar is! RenderBox ||
        player is! RenderBox ||
        !bar.attached ||
        !player.attached) {
      return;
    }
    // Resolve the real progress-bar geometry, including fullscreen safe areas.
    final offset = player.globalToLocal(bar.localToGlobal(Offset(dx, 0)));
    controller.updateHoverPreview(offset, seconds);
  }

  void _onExit() {
    if (controller.isSeeking.value || controller.hoverDx == null) {
      return;
    }
    controller.clearHoverPreview(restartControls: true);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final primary = colorScheme.isLight
        ? colorScheme.inversePrimary
        : colorScheme.primary;
    final thumbGlowColor = primary.withAlpha(80);
    final bufferedBarColor = primary.withValues(alpha: 0.4);

    final enableHover =
        PlatformUtils.isDesktop &&
        controller.showSeekPreview &&
        !controller.isFileSource &&
        !isPipMode;

    return Padding(
      padding: const .symmetric(horizontal: 10, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 7),
            child: Obx(
              () {
                final detailHeaderCollapsed =
                    !isFullScreen &&
                    !isPipMode &&
                    videoDetailController.scrollRatio.value >= 1.0;
                return Offstage(
                  offstage:
                      detailHeaderCollapsed || !controller.showControls.value,
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.bottomCenter,
                    children: [
                      Obx(
                        () => ProgressBar(
                          key: _progressBarKey,
                          progress: controller.progress,
                          buffered: controller.buffered.value,
                          total: controller.duration.value,
                          progressBarColor: primary,
                          baseBarColor: const Color(0x33FFFFFF),
                          bufferedBarColor: bufferedBarColor,
                          thumbColor: primary,
                          thumbGlowColor: thumbGlowColor,
                          barHeight: 3.5,
                          thumbRadius: 7,
                          thumbGlowRadius: 25,
                          onDragStart: onDragStart,
                          onDragUpdate: onDragUpdate,
                          onSeek: onSeek,
                          onHover: enableHover ? _onHover : null,
                          onExit: enableHover ? _onExit : null,
                        ),
                      ),
                      if (controller.enableBlock &&
                          videoDetailController.segmentProgressList.isNotEmpty)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 5.25,
                          child: SegmentProgressBar(
                            segments: List<Segment>.of(
                              videoDetailController.segmentProgressList,
                            ),
                          ),
                        ),
                      if (!isPipMode &&
                          controller.showViewPoints &&
                          videoDetailController.viewPointList.isNotEmpty &&
                          !videoDetailController.showVP.value)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 5.25,
                          child: ViewPointDividerBar(
                            segments: videoDetailController.viewPointList,
                            progress: controller.duration.value > 0
                                ? controller.position.value /
                                      controller.duration.value
                                : 0.0,
                          ),
                        ),
                      if (!isPipMode &&
                          controller.showViewPoints &&
                          videoDetailController.viewPointList.isNotEmpty &&
                          videoDetailController.showVP.value)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8.75),
                          child: ViewPointSegmentProgressBar(
                            segments: videoDetailController.viewPointList,
                            onSeek: PlatformUtils.isDesktop
                                ? (position) =>
                                      controller.seekTo(position, isSeek: false)
                                : null,
                          ),
                        ),

                      if (!isPipMode &&
                          videoDetailController.showDmTrendChart.value)
                        if (videoDetailController.dmTrend.value?.dataOrNull
                            case final list?)
                          buildDmChart(
                            primary,
                            list,
                            videoDetailController,
                            4.5,
                          ),
                    ],
                  ),
                );
              },
            ),
          ),
          widget.buildBottomControl(),
        ],
      ),
    );
  }
}
