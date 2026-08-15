import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' show max, pow;

import 'package:PiliMax/pilimax/common/widgets/pip_mini_video_content.dart';
import 'package:PiliMax/pages/live_room/controller.dart';
import 'package:PiliMax/plugin/pl_player/controller.dart';
import 'package:PiliMax/plugin/pl_player/models/play_status.dart';
import 'package:PiliMax/pilimax/services/pip_transition_coordinator.dart';
import 'package:PiliMax/services/service_locator.dart';
import 'package:PiliMax/utils/storage_pref.dart';
import 'package:PiliMax/utils/device_utils.dart';
import 'package:PiliMax/utils/platform_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart'
    show
        GestureBinding,
        PointerEnterEvent,
        PointerExitEvent,
        PointerScrollEvent;
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

class LivePipOverlayService {
  static OverlayEntry? _overlayEntry;
  static bool _isInPipMode = false;
  static bool isVertical = false;
  static final RxBool _isNativePip = false.obs;
  static bool get isNativePip => _isNativePip.value;
  static set isNativePip(bool value) => _isNativePip.value = value;
  static String? _currentLiveHeroTag;
  static int? _currentRoomId;

  static final PipTransitionCoordinator transition = PipTransitionCoordinator()
    ..onRestoreFinished = _finalizeRestore;

  static void _finalizeRestore() {
    stopLivePip(callOnClose: false, immediate: true);
  }

  static VoidCallback? _onCloseCallback;
  static VoidCallback? _onReturnCallback;

  static String? get currentHeroTag => _currentLiveHeroTag;
  static int? get currentRoomId => _currentRoomId;

  static void onReturn() {
    if (transition.beginRestore()) {
      _onReturnCallback?.call();
    }
  }

  // 保存控制器引用，防止被 GC
  static dynamic _savedController;
  static PlPlayerController? _savedPlayerController;

  static bool _isVideoLikeRoute(String route) {
    return route.startsWith('/video') || route.startsWith('/liveRoom');
  }

  static void _setSystemAutoPipEnabled(
    PlPlayerController? plPlayerController,
    bool enabled,
  ) {
    // 1. 基础条件判断
    if (!Platform.isAndroid ||
        plPlayerController == null ||
        !plPlayerController.autoPiP ||
        !Pref.enableInAppPipToSystemPip) {
      return;
    }

    if (DeviceUtils.sdkInt >= 31) {
      if (enabled) {
        plPlayerController.enterPip(autoEnter: true);
      } else {
        plPlayerController.disableAutoEnterPip();
      }
    }
  }

  static bool get isInPipMode => _isInPipMode;

  static T? getSavedController<T>() => _savedController as T?;

  /// Cleans up a live controller that will not be reused by the next route.
  /// The controller can outlive its route while its live PiP overlay owns it.
  static void cleanupSavedController() {
    final saved = _savedController;
    if (saved is! LiveRoomController) return;
    saved
      ..closeLiveMsg()
      ..cancelLiveTimer()
      ..cancelLikeTimer();
    videoPlayerServiceHandler?.onVideoDetailDispose(saved.heroTag);
  }

  static void startLivePip({
    required BuildContext context,
    required String heroTag,
    required int roomId,
    required PlPlayerController plPlayerController,
    VoidCallback? onClose,
    VoidCallback? onReturn,
    dynamic controller,
    Rect? sourceRect,
  }) {
    if (_isInPipMode) {
      stopLivePip(callOnClose: true);
    }

    _isInPipMode = true;
    transition.beginEnter(sourceRect: sourceRect);
    isVertical = plPlayerController.isVertical;
    _currentLiveHeroTag = heroTag;
    _currentRoomId = roomId;
    _onCloseCallback = onClose;
    _onReturnCallback = onReturn;
    _savedController = controller;
    _savedPlayerController = plPlayerController;

    _overlayEntry = OverlayEntry(
      builder: (context) => LivePipWidget(
        heroTag: heroTag,
        roomId: roomId,
        plPlayerController: plPlayerController,
        onClose: () {
          stopLivePip(callOnClose: true, immediate: true);
        },
        onReturn: () {
          if (transition.beginRestore()) {
            _onReturnCallback?.call();
          }
        },
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final overlayContext = Get.overlayContext ?? context;
        Overlay.of(overlayContext).insert(_overlayEntry!);

        // 允许应用内小窗继续使用 Auto-PiP 手势
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_isInPipMode) return;
          _setSystemAutoPipEnabled(plPlayerController, true);
        });
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Error inserting live pip overlay: $e');
        }
        SmartDialog.showToast('小窗启动失败: $e');
        _setSystemAutoPipEnabled(plPlayerController, false);
        transition.reset();

        // 完整清理所有状态
        _isInPipMode = false;
        _currentLiveHeroTag = null;
        _currentRoomId = null;
        _overlayEntry = null;
        _savedController = null;
        _savedPlayerController = null;

        // 通知调用者失败
        onClose?.call();
      }
    });
  }

  static void stopLivePip({bool callOnClose = true, bool immediate = false}) {
    if (!_isInPipMode && _overlayEntry == null) {
      return;
    }

    _isInPipMode = false;
    transition.reset();
    // isNativePip 是 Rx 变量，不能在 build 阶段（如 initState）同步修改，
    // 否则会触发 Obx rebuild 导致 "setState during build" 错误
    WidgetsBinding.instance.addPostFrameCallback((_) {
      isNativePip = false;
    });
    _currentLiveHeroTag = null;
    _currentRoomId = null;

    final closeCallback = callOnClose ? _onCloseCallback : null;
    final playerController = _savedPlayerController;

    _onCloseCallback = null;
    _onReturnCallback = null;
    _savedController = null;
    _savedPlayerController = null;

    final overlayToRemove = _overlayEntry;
    _overlayEntry = null;

    // 小窗结束后，仅在视频/直播详情页中保留系统 Auto-PiP，其余场景立即关闭防止误触发
    final currentRoute = Get.currentRoute;
    final keepAutoPip = _isVideoLikeRoute(currentRoute);
    _setSystemAutoPipEnabled(playerController, keepAutoPip);

    void removeAndCallback() {
      try {
        overlayToRemove?.remove();
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Error removing live pip overlay: $e');
        }
      }
      closeCallback?.call();
    }

    if (immediate) {
      removeAndCallback();
    } else {
      Future.delayed(const Duration(milliseconds: 300), removeAndCallback);
    }

    // 如果需要清理，先停止播放器
    if (callOnClose && playerController != null) {
      try {
        // 停止播放但不 dispose，因为其他地方可能还在使用
        playerController.pause();
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Error pausing player: $e');
        }
      }
    }
  }

  static bool isCurrentLiveRoom(int roomId) {
    return _isInPipMode && _currentRoomId == roomId;
  }
}

class LivePipWidget extends StatefulWidget {
  final String heroTag;
  final int roomId;
  final PlPlayerController plPlayerController;
  final VoidCallback onClose;
  final VoidCallback onReturn;

  const LivePipWidget({
    super.key,
    required this.heroTag,
    required this.roomId,
    required this.plPlayerController,
    required this.onClose,
    required this.onReturn,
  });

  @override
  State<LivePipWidget> createState() => _LivePipWidgetState();
}

class _LivePipWidgetState extends State<LivePipWidget>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  double? _left;
  double? _top;
  double _scale = PipWindowMemory.scale;
  double _scaleStart = 1.0;
  bool _scaleGestureActive = false;
  Timer? _wheelResizeTimer;

  bool get _instantResize =>
      _scaleGestureActive || _wheelResizeTimer?.isActive == true;

  PipTransitionCoordinator get _transition => LivePipOverlayService.transition;
  PipPhase _lastPhase = PipPhase.hidden;

  late final AnimationController _phaseController = AnimationController(
    vsync: this,
    duration: PipTransitionCoordinator.animDuration,
  )..addStatusListener(_onPhaseAnimationStatus);

  late final AnimationController _closeController = AnimationController(
    vsync: this,
    duration: PipTransitionCoordinator.closeFadeDuration,
  );

  Size get _unscaledWindowSize => LivePipOverlayService.isVertical
      ? const Size(112, 200)
      : const Size(200, 112);
  double get _width => _unscaledWindowSize.width * _scale;
  double get _height => _unscaledWindowSize.height * _scale;

  bool _showControls = true;
  Timer? _hideTimer;
  // 桌面端:鼠标悬停时控制栏保持显示,移出即隐藏
  bool _hovering = false;
  bool _isClosing = false;
  bool _isRefreshing = false;
  late final GlobalKey _videoContentKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _transition.addListener(_onPhaseChanged);
    _lastPhase = _transition.phase;
    if (_lastPhase == PipPhase.entering) {
      _phaseController.forward(from: 0);
    } else {
      _phaseController.value = 1;
    }
    // 桌面端控制栏初始隐藏,由 hover 显示
    if (PlatformUtils.isDesktop) {
      _showControls = false;
    } else {
      _startHideTimer();
    }
  }

  void _onPhaseChanged() {
    final phase = _transition.phase;
    if (phase != _lastPhase) {
      _lastPhase = phase;
      if (phase != PipPhase.active) {
        _cancelWheelResize();
        _scaleGestureActive = false;
      }
      switch (phase) {
        case PipPhase.entering:
        case PipPhase.restoring:
          _phaseController.forward(from: 0);
        case PipPhase.active:
          _phaseController
            ..stop()
            ..value = 1;
        case PipPhase.hidden:
          _phaseController.stop();
      }
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _onPhaseAnimationStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) {
      return;
    }
    switch (_transition.phase) {
      case PipPhase.entering:
        _transition.markEnterDone();
      case PipPhase.restoring:
        _transition.markRestoreAnimationDone();
      case PipPhase.active:
      case PipPhase.hidden:
        break;
    }
  }

  void _beginClose() {
    if (_isClosing) {
      return;
    }
    _hideTimer?.cancel();
    _cancelWheelResize();
    _scaleGestureActive = false;
    setState(() => _isClosing = true);
    _closeController.forward(from: 0).then((_) {
      if (mounted) {
        widget.onClose();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _transition.removeListener(_onPhaseChanged);
    _phaseController
      ..removeStatusListener(_onPhaseAnimationStatus)
      ..dispose();
    _closeController.dispose();
    _hideTimer?.cancel();
    _cancelWheelResize();
    if (LivePipOverlayService._overlayEntry != null) {
      LivePipOverlayService._onCloseCallback = null;
      LivePipOverlayService._onReturnCallback = null;
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!LivePipOverlayService.isInPipMode) return;

    // 此处无需重复处理，由 PlPlayerController 中的 onPipChanged 消息统一处理退出逻辑。
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    // 悬停中不自动隐藏
    if (_hovering) return;
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  void _resetHideTimer() {
    if (_showControls) {
      _startHideTimer();
    }
  }

  void _onHoverEnter(PointerEnterEvent event) {
    // 收起/归位动画期间 IgnorePointer 已屏蔽事件,此守卫防异常时序
    if (_transition.phase != PipPhase.active || _isClosing) return;
    _hideTimer?.cancel();
    setState(() {
      _hovering = true;
      _showControls = true;
    });
  }

  void _onHoverExit(PointerExitEvent event) {
    _hideTimer?.cancel();
    setState(() {
      _hovering = false;
      _showControls = false;
    });
  }

  Future<void> _onRefresh() async {
    if (_isRefreshing) return;
    final controller =
        LivePipOverlayService.getSavedController<LiveRoomController>();
    if (controller == null || controller.isClosed) return;

    _resetHideTimer();
    _isRefreshing = true;
    try {
      await controller.queryLiveUrl();
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Error refreshing live PiP: $error');
      }
    } finally {
      _isRefreshing = false;
    }
  }

  void _onTap() {
    // 悬停中由 hover 驱动;触摸/笔等无 hover 场景保留点击切换兜底
    if (_hovering) return;
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls) {
      _startHideTimer();
    }
  }

  double _clampScale(double scale, Size screenSize) {
    return PipWindowMemory.clampScaleToViewport(
      scale: scale,
      viewport: screenSize,
      unscaledWindowSize: _unscaledWindowSize,
    );
  }

  void _clampPositionInScreen(Size screenSize) {
    _left = (_left ?? 0.0)
        .clamp(0.0, max(0.0, screenSize.width - _width))
        .toDouble();
    _top = (_top ?? 0.0)
        .clamp(0.0, max(0.0, screenSize.height - _height))
        .toDouble();
  }

  void _applyScaleAroundCenter(double targetScale, Size screenSize) {
    _clampPositionInScreen(screenSize);
    final center = Offset(_left! + _width / 2, _top! + _height / 2);
    _scale = _clampScale(targetScale, screenSize);
    _left = center.dx - _width / 2;
    _top = center.dy - _height / 2;
    _clampPositionInScreen(screenSize);
  }

  void _rememberWindow() {
    PipWindowMemory.scale = _scale;
    PipWindowMemory.position = Offset(_left ?? 0, _top ?? 0);
  }

  void _cancelWheelResize() {
    _wheelResizeTimer?.cancel();
    _wheelResizeTimer = null;
  }

  void _handlePointerScroll(PointerScrollEvent event, Size screenSize) {
    if (!mounted || _transition.phase != PipPhase.active) {
      return;
    }

    final exponent = (-event.scrollDelta.dy / 100).clamp(-1.0, 1.0);
    final factor = pow(1.1, exponent).toDouble();
    _cancelWheelResize();
    _wheelResizeTimer = Timer(const Duration(milliseconds: 300), () {
      _wheelResizeTimer = null;
      if (mounted) {
        setState(() {});
      }
    });
    setState(() {
      _applyScaleAroundCenter(_scale * factor, screenSize);
    });
    _rememberWindow();
    if (_showControls) {
      _startHideTimer();
    }
  }

  void _onDoubleTap() {
    final screenSize = MediaQuery.sizeOf(context);
    _cancelWheelResize();
    var nextScale = _scale < 1.1
        ? 1.5
        : _scale < 1.6
        ? 2.0
        : 1.0;
    nextScale = _clampScale(nextScale, screenSize);
    if ((nextScale - _scale).abs() < 0.05) {
      nextScale = _clampScale(1.0, screenSize);
    }

    // Keep the nearest horizontal/vertical edge anchored while changing the
    // scale. A plain clamp after changing _scale makes right/bottom windows
    // appear to drift because their far edge is no longer preserved.
    _clampPositionInScreen(screenSize);
    final oldLeft = _left ?? 0.0;
    final oldTop = _top ?? 0.0;
    final oldWidth = _width;
    final oldHeight = _height;
    final distLeft = oldLeft;
    final distRight = screenSize.width - oldLeft - oldWidth;
    final distTop = oldTop;
    final distBottom = screenSize.height - oldTop - oldHeight;

    setState(() {
      _scale = nextScale;
      final newLeft = distLeft <= distRight
          ? oldLeft
          : screenSize.width - distRight - _width;
      final newTop = distTop <= distBottom
          ? oldTop
          : screenSize.height - distBottom - _height;
      _left = newLeft
          .clamp(0.0, max(0.0, screenSize.width - _width))
          .toDouble();
      _top = newTop
          .clamp(0.0, max(0.0, screenSize.height - _height))
          .toDouble();
    });
    _rememberWindow();
    _startHideTimer();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final viewportScale = _clampScale(_scale, screenSize);
    if (viewportScale != _scale) {
      _scale = viewportScale;
      PipWindowMemory.scale = _scale;
    }

    _left ??= (PipWindowMemory.position?.dx ?? screenSize.width - _width - 16)
        .clamp(0.0, max(0.0, screenSize.width - _width))
        .toDouble();
    _top ??= (PipWindowMemory.position?.dy ?? screenSize.height - _height - 100)
        .clamp(0.0, max(0.0, screenSize.height - _height))
        .toDouble();

    return Obx(() {
      final bool isNative = LivePipOverlayService.isNativePip;

      if (isNative) {
        return Positioned.fill(
          child: ColoredBox(
            color: Colors.black,
            child: AbsorbPointer(
              child: PipMiniVideoContent(
                key: _videoContentKey,
                plPlayerController: widget.plPlayerController,
                transition: _transition,
              ),
            ),
          ),
        );
      }

      return AnimatedBuilder(
        animation: Listenable.merge([
          _phaseController,
          _closeController,
          _transition,
        ]),
        builder: (context, _) {
          final phase = _transition.phase;
          final displayLeft = _left!
              .clamp(0.0, max(0.0, screenSize.width - _width))
              .toDouble();
          final displayTop = _top!
              .clamp(0.0, max(0.0, screenSize.height - _height))
              .toDouble();
          final miniRect = Rect.fromLTWH(
            displayLeft,
            displayTop,
            _width,
            _height,
          );
          final progress = PipTransitionCoordinator.animCurve.transform(
            _phaseController.value,
          );
          final rect = _transition.resolveRect(
            miniRect: miniRect,
            progress: progress,
          );
          final radius = _transition.resolveRadius(base: 8, progress: progress);
          final inTransition =
              phase == PipPhase.entering || phase == PipPhase.restoring;
          final interactive = phase == PipPhase.active && !_isClosing;

          return AnimatedPositioned(
            duration: inTransition || _instantResize
                ? Duration.zero
                : const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            left: rect.left,
            top: rect.top,
            child: IgnorePointer(
              ignoring: !interactive,
              child: Listener(
                onPointerSignal: (event) {
                  if (event is! PointerScrollEvent ||
                      event.scrollDelta.dy == 0) {
                    return;
                  }

                  GestureBinding.instance.pointerSignalResolver.register(
                    event,
                    (resolvedEvent) => _handlePointerScroll(
                      resolvedEvent as PointerScrollEvent,
                      screenSize,
                    ),
                  );
                },
                child: GestureDetector(
                  onTap: _onTap,
                  onDoubleTap: _onDoubleTap,
                  onScaleStart: (_) {
                    _hideTimer?.cancel();
                    _cancelWheelResize();
                    _clampPositionInScreen(screenSize);
                    _scaleStart = _scale;
                    setState(() => _scaleGestureActive = true);
                  },
                  onScaleUpdate: (details) {
                    setState(() {
                      _left = _left! + details.focalPointDelta.dx;
                      _top = _top! + details.focalPointDelta.dy;
                      if (details.pointerCount > 1) {
                        _applyScaleAroundCenter(
                          _scaleStart * details.scale,
                          screenSize,
                        );
                      } else {
                        _clampPositionInScreen(screenSize);
                      }
                    });
                    _rememberWindow();
                  },
                  onScaleEnd: (_) {
                    setState(() => _scaleGestureActive = false);
                    if (_showControls) {
                      _startHideTimer();
                    }
                  },
                  child: MouseRegion(
                    onEnter: _onHoverEnter,
                    onExit: _onHoverExit,
                    child: FadeTransition(
                      opacity: _closeController.drive(
                        Tween<double>(begin: 1, end: 0),
                      ),
                      child: ScaleTransition(
                        scale: _closeController.drive(
                          Tween<double>(begin: 1, end: 0.85).chain(
                            CurveTween(curve: Curves.easeOut),
                          ),
                        ),
                        child: AnimatedContainer(
                          duration: inTransition || _instantResize
                              ? Duration.zero
                              : const Duration(milliseconds: 250),
                          curve: Curves.easeOutCubic,
                          width: rect.width,
                          height: rect.height,
                          decoration: BoxDecoration(
                            color: Colors.black,
                            borderRadius: BorderRadius.circular(radius),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.6),
                                blurRadius: 12,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(radius),
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: AbsorbPointer(
                                    child: PipMiniVideoContent(
                                      key: _videoContentKey,
                                      plPlayerController:
                                          widget.plPlayerController,
                                      transition: _transition,
                                    ),
                                  ),
                                ),
                                if (interactive && _showControls) ...[
                                  Positioned.fill(
                                    child: Container(
                                      color: Colors.black.withValues(
                                        alpha: 0.4,
                                      ),
                                    ),
                                  ),
                                  // 左上角关闭
                                  Positioned(
                                    top: 3,
                                    left: 4,
                                    child: GestureDetector(
                                      onTap: _beginClose,
                                      child: const Padding(
                                        padding: EdgeInsets.all(8.0),
                                        child: Icon(
                                          Icons.close,
                                          color: Colors.white,
                                          size: 21,
                                        ),
                                      ),
                                    ),
                                  ),
                                  // 右上角放大/还原
                                  Positioned(
                                    top: 3,
                                    right: 4,
                                    child: GestureDetector(
                                      onTap: () {
                                        _hideTimer?.cancel();
                                        widget.onReturn();
                                      },
                                      child: const Padding(
                                        padding: EdgeInsets.all(8.0),
                                        child: Icon(
                                          Icons.open_in_full,
                                          color: Colors.white,
                                          size: 18,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    left: 0,
                                    right: 0,
                                    bottom: 8,
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceEvenly,
                                      children: [
                                        const SizedBox(width: 22),
                                        Obx(() {
                                          final isPlaying =
                                              widget
                                                  .plPlayerController
                                                  .playerStatus
                                                  .value ==
                                              PlayerStatus.playing;
                                          return GestureDetector(
                                            onTap: () {
                                              _resetHideTimer();
                                              if (isPlaying) {
                                                widget.plPlayerController
                                                    .pause();
                                              } else {
                                                widget.plPlayerController
                                                    .play();
                                              }
                                            },
                                            child: Icon(
                                              isPlaying
                                                  ? Icons.pause
                                                  : Icons.play_arrow,
                                              color: Colors.white,
                                              size: 30,
                                            ),
                                          );
                                        }),
                                        GestureDetector(
                                          onTap: _onRefresh,
                                          child: const Icon(
                                            Icons.refresh,
                                            color: Colors.white70,
                                            size: 22,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    });
  }
}
