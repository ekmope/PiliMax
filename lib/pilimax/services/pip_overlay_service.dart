import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' show max, pow;

import 'package:PiliMax/pages/video/controller.dart';
import 'package:PiliMax/plugin/pl_player/controller.dart';
import 'package:PiliMax/plugin/pl_player/models/play_status.dart';
import 'package:PiliMax/services/logger.dart';
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
import 'package:get/get.dart';

class VideoStackManager {
  static int _videoPageCount = 0;

  static void increment() {
    _videoPageCount++;
    _log('increment: count = $_videoPageCount');
  }

  static void decrement() {
    if (_videoPageCount > 0) {
      _videoPageCount--;
      _log('decrement: count = $_videoPageCount');
    }
  }

  static int getCount() => _videoPageCount;

  static bool isReturningToVideo() {
    final result = _videoPageCount > 1;
    if (result) {
      _log('isReturningToVideo check: true (count = $_videoPageCount)');
    }
    return result;
  }

  static void _log(String msg) {
    if (!kDebugMode) return;
    logger.i('[VideoStackManager] $msg');
  }
}

class PipOverlayService {
  static const double pipWidth = 200;
  static const double pipHeight = 112;
  static bool isVertical = false;

  static OverlayEntry? _overlayEntry;
  static bool isInPipMode = false;
  static final RxBool _isNativePip = false.obs;
  static bool get isNativePip => _isNativePip.value;
  static set isNativePip(bool value) => _isNativePip.value = value;

  static final PipTransitionCoordinator transition = PipTransitionCoordinator()
    ..onRestoreFinished = _finalizeRestore;

  static void _finalizeRestore() {
    stopPip(
      callOnClose: false,
      immediate: true,
      targetContextKey: _savedVideoContextKey,
    );
  }

  static VoidCallback? _onCloseCallback;
  static VoidCallback? _onTapToReturnCallback;

  static void onTapToReturn() {
    if (transition.beginRestore()) {
      _onTapToReturnCallback?.call();
    }
  }

  // 保存控制器引用，防止被 GC
  static dynamic _savedController;
  static PlPlayerController? _savedPlayerController;
  static String? _savedVideoContextKey;
  static String? get savedVideoContextKey => _savedVideoContextKey;
  static final Map<String, dynamic> _savedControllers = {};

  static bool isVideoLikeRoute(String route) {
    return route.startsWith('/video') || route.startsWith('/liveRoom');
  }

  static void _setEnteringPipFlag(dynamic controller, bool value) {
    try {
      controller.isEnteringPip = value;
    } catch (_) {}
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

  // 释放小窗持有的旧视频页 owner。只能由 stopPip 在清空静态引用前捕获参数后
  // 调用（releaseSavedOwner 标志），避免调用方在 stopPip 之后读取已清空的引用
  // 导致释放静默失效。
  // disposePlayer 语义：owner 页面已离开路由栈（如从列表点开新视频）才允许
  // dispose；owner 仍在栈内（链式进入新视频/直播，稍后会返回恢复）只能暂停——
  // dispose 会消耗 owner 页面持有的 _playerCount 计数，导致后续页面 dispose 时
  // 计数归零、误销毁下层页面正在复用的播放器实例
  static void _releaseSavedVideoOwner({
    required VideoDetailController controller,
    required PlPlayerController? player,
    required bool disposePlayer,
  }) {
    controller
      ..isEnteringPip = false
      ..cancelBlockListener();

    if (player != null) {
      controller.makeHeartBeat();
      if (disposePlayer) {
        videoPlayerServiceHandler?.onVideoDetailDispose(controller.heroTag);
        player.dispose();
      } else {
        player.pause();
      }
    }
  }

  static String _keyPart(Object? value) => value?.toString() ?? '';

  static String? buildVideoContextKey({
    Object? videoType,
    Object? bvid,
    Object? cid,
    Object? epId,
    Object? seasonId,
  }) {
    if (bvid == null &&
        cid == null &&
        epId == null &&
        seasonId == null &&
        videoType == null) {
      return null;
    }
    return [
      _keyPart(videoType),
      _keyPart(bvid),
      _keyPart(cid),
      _keyPart(epId),
      _keyPart(seasonId),
    ].join('|');
  }

  static String? contextKeyFromArgs(Map? args) {
    if (args == null) {
      return null;
    }
    return buildVideoContextKey(
      videoType: args['videoType'],
      bvid: args['bvid'],
      cid: args['cid'],
      epId: args['epId'],
      seasonId: args['seasonId'],
    );
  }

  static String? _contextKeyFromController(dynamic controller) {
    if (controller is! VideoDetailController) {
      return null;
    }
    return buildVideoContextKey(
      videoType: controller.videoType,
      bvid: controller.bvid,
      cid: controller.cid.value,
      epId: controller.epId,
      seasonId: controller.seasonId,
    );
  }

  static bool startPip({
    required BuildContext context,
    required PlPlayerController plPlayerController,
    required Widget Function(bool isNative, double width, double height)
    videoPlayerBuilder,
    VoidCallback? onClose,
    VoidCallback? onTapToReturn,
    VoidCallback? onStartFailed,
    VoidCallback? onOverlayInserted,
    dynamic controller,
    Map<String, dynamic>? additionalControllers,
    Rect? sourceRect,
  }) {
    if (isInPipMode) {
      return false;
    }

    isInPipMode = true;
    transition.beginEnter(sourceRect: sourceRect);
    isVertical = false;
    if (controller is VideoDetailController) {
      isVertical = controller.isVertical.value;
    }

    _onCloseCallback = onClose;
    _onTapToReturnCallback = onTapToReturn;
    _savedController = controller;
    _savedPlayerController = plPlayerController;
    _savedVideoContextKey = _contextKeyFromController(controller);
    if (additionalControllers != null) {
      _savedControllers.addAll(additionalControllers);
    }

    _overlayEntry = OverlayEntry(
      builder: (context) => PipWidget(
        videoPlayerBuilder: videoPlayerBuilder,
        onClose: () {
          stopPip(callOnClose: true, immediate: true);
        },
        onTapToReturn: () {
          if (transition.beginRestore()) {
            _onTapToReturnCallback?.call();
          }
        },
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final overlayContext = Get.overlayContext ?? context;
        Overlay.of(overlayContext).insert(_overlayEntry!);
        onOverlayInserted?.call();

        // 允许应用内小窗继续使用 Auto-PiP 手势
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!isInPipMode) return;
          _setSystemAutoPipEnabled(plPlayerController, true);
        });
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Error inserting pip overlay: $e');
        }
        _setSystemAutoPipEnabled(plPlayerController, false);
        isInPipMode = false;
        transition.reset();
        _overlayEntry = null;
        _savedController = null;
        _savedPlayerController = null;
        _savedVideoContextKey = null;
        _savedControllers.clear();
        onStartFailed?.call();
      }
    });
    return true;
  }

  static T? getSavedController<T>() => _savedController as T?;

  static T? getAdditionalController<T>(String key) =>
      _savedControllers[key] as T?;

  static void stopPip({
    bool callOnClose = true,
    bool immediate = false,
    bool resetState = true,
    String? targetContextKey,
    bool releaseSavedOwner = false,
    bool disposeSavedOwnerPlayer = true,
  }) {
    if (!isInPipMode && _overlayEntry == null) {
      return;
    }

    final bool shouldResetState = targetContextKey == null
        ? resetState
        : targetContextKey != _savedVideoContextKey;

    if (kDebugMode) {
      debugPrint(
        '[PiP] Stopping PiP mode (immediate: $immediate, callOnClose: $callOnClose, shouldResetState: $shouldResetState, targetContextKey: $targetContextKey, savedContextKey: $_savedVideoContextKey)',
      );
    }

    isInPipMode = false;
    transition.reset();
    // isNativePip 是 Rx 变量，不能在 build 阶段（如 initState）同步修改，
    // 否则会触发 Obx rebuild 导致 "setState during build" 错误。
    // 延迟到当前帧结束后再更新。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      isNativePip = false;
    });

    final closeCallback = callOnClose ? _onCloseCallback : null;
    final playerController = _savedPlayerController;
    // 静态引用即将被清空，释放 owner 所需的引用必须在此捕获
    final ownerToRelease = releaseSavedOwner ? _savedController : null;
    _onCloseCallback = null;
    _onTapToReturnCallback = null;

    // 清理控制器缓存，防止内存泄漏和状态污染
    if (kDebugMode &&
        (_savedController != null || _savedControllers.isNotEmpty)) {
      debugPrint(
        '[PiP] Clearing cached controllers, resetState: $shouldResetState, targetContextKey: $targetContextKey, savedContextKey: $_savedVideoContextKey',
      );
    }

    // 旧 controller 仍在路由栈内时，不能完整 onClose：
    // TabController/ScrollController 仍会被旧页面再次使用。
    // 若 controller 已由 GetX 关闭，页面已离栈，此时再执行完整清理。
    if (shouldResetState && _savedController is VideoDetailController) {
      final ctrl = (_savedController as VideoDetailController)
        ..isEnteringPip = false
        ..cancelBlockListener();
      if (ctrl.isClosed) {}
      for (final controller in _savedControllers.values) {
        _setEnteringPipFlag(controller, false);
      }
    }

    _savedController = null;
    _savedPlayerController = null;
    _savedVideoContextKey = null;
    _savedControllers.clear();

    final overlayToRemove = _overlayEntry;
    _overlayEntry = null;

    // 小窗结束后，仅在视频/直播详情页中保留系统 Auto-PiP，其余场景立即关闭防止误触发
    final currentRoute = Get.currentRoute;
    final keepAutoPip = isVideoLikeRoute(currentRoute);
    _setSystemAutoPipEnabled(playerController, keepAutoPip);

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

    void removeAndCallback() {
      try {
        overlayToRemove?.remove();
        if (kDebugMode) {
          debugPrint('[PiP] Overlay entry removed successfully');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Error removing pip overlay: $e');
        }
      }
      // overlay 已移除，此时 dispose 播放器不会留下持有失效纹理的窗口
      if (ownerToRelease is VideoDetailController) {
        _releaseSavedVideoOwner(
          controller: ownerToRelease,
          player: playerController,
          disposePlayer: disposeSavedOwnerPlayer,
        );
      }
      closeCallback?.call();
    }

    if (immediate) {
      removeAndCallback();
    } else {
      Future.delayed(const Duration(milliseconds: 300), removeAndCallback);
    }
  }
}

class PipWidget extends StatefulWidget {
  final Widget Function(bool isNative, double width, double height)
  videoPlayerBuilder;
  final VoidCallback onClose;
  final VoidCallback onTapToReturn;

  const PipWidget({
    super.key,
    required this.videoPlayerBuilder,
    required this.onClose,
    required this.onTapToReturn,
  });

  @override
  State<PipWidget> createState() => _PipWidgetState();
}

class _PipWidgetState extends State<PipWidget>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  double? _left;
  double? _top;
  double _scale = PipWindowMemory.scale;
  double _scaleStart = 1.0;
  bool _scaleGestureActive = false;
  Timer? _wheelResizeTimer;

  bool get _instantResize =>
      _scaleGestureActive || _wheelResizeTimer?.isActive == true;

  PipTransitionCoordinator get _transition => PipOverlayService.transition;
  PipPhase _lastPhase = PipPhase.hidden;

  late final AnimationController _phaseController = AnimationController(
    vsync: this,
    duration: PipTransitionCoordinator.animDuration,
  )..addStatusListener(_onPhaseAnimationStatus);

  late final AnimationController _closeController = AnimationController(
    vsync: this,
    duration: PipTransitionCoordinator.closeFadeDuration,
  );

  Size get _unscaledWindowSize => PipOverlayService.isVertical
      ? const Size(PipOverlayService.pipHeight, PipOverlayService.pipWidth)
      : const Size(PipOverlayService.pipWidth, PipOverlayService.pipHeight);
  double get _width => _unscaledWindowSize.width * _scale;
  double get _height => _unscaledWindowSize.height * _scale;

  bool _showControls = true;
  Timer? _hideTimer;
  // 桌面端:鼠标悬停时控制栏保持显示,移出即隐藏
  bool _hovering = false;

  bool _isClosing = false;

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
    if (PipOverlayService._overlayEntry != null) {
      PipOverlayService._onCloseCallback = null;
      PipOverlayService._onTapToReturnCallback = null;
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!PipOverlayService.isInPipMode) return;

    // 此处无需重复处理，状态同步由PlPlayerController中的onPipChanged消息统一管理
    // 而且在Controller中已加入了退出延迟，确保系统转场动画完成后再切换布局。
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
      final bool isNative = PipOverlayService.isNativePip;

      // 系统 PiP 模式下，直接铺满窗口，不执行任何自定义尺寸或位置计算
      if (isNative) {
        return Positioned.fill(
          child: ColoredBox(
            color: Colors.black,
            child: AbsorbPointer(
              child: widget.videoPlayerBuilder(
                true,
                screenSize.width,
                screenSize.height,
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
                                color: Colors.black.withValues(alpha: 0.5),
                                blurRadius: 10,
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
                                    child: widget.videoPlayerBuilder(
                                      false,
                                      rect.width,
                                      rect.height,
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
                                  // 右上角还原
                                  Positioned(
                                    top: 3,
                                    right: 4,
                                    child: GestureDetector(
                                      onTap: () {
                                        _hideTimer?.cancel();
                                        widget.onTapToReturn();
                                      },
                                      child: const Padding(
                                        padding: EdgeInsets.all(8.0),
                                        child: Icon(
                                          Icons.open_in_full,
                                          color: Colors.white,
                                          size: 19,
                                        ),
                                      ),
                                    ),
                                  ),
                                  // 底部控制栏
                                  Positioned(
                                    left: 0,
                                    right: 0,
                                    bottom: 8,
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceEvenly,
                                      children: [
                                        // 后退10秒
                                        GestureDetector(
                                          onTap: () {
                                            _resetHideTimer();
                                            final controller =
                                                PipOverlayService.getSavedController<
                                                  VideoDetailController
                                                >();
                                            final plController =
                                                controller?.plPlayerController;
                                            if (plController != null) {
                                              final current = Duration(
                                                seconds:
                                                    plController.position.value,
                                              );
                                              plController.seekTo(
                                                current -
                                                    const Duration(seconds: 10),
                                              );
                                            }
                                          },
                                          child: const Icon(
                                            Icons.replay_10,
                                            color: Colors.white,
                                            size: 22,
                                          ),
                                        ),
                                        // 播放/暂停
                                        Obx(() {
                                          final controller =
                                              PipOverlayService.getSavedController<
                                                VideoDetailController
                                              >();
                                          final plController =
                                              controller?.plPlayerController;
                                          final isPlaying =
                                              plController
                                                  ?.playerStatus
                                                  .value ==
                                              PlayerStatus.playing;
                                          return GestureDetector(
                                            onTap: () {
                                              _resetHideTimer();
                                              if (isPlaying) {
                                                plController?.pause();
                                              } else {
                                                plController?.play();
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
                                        // 前进10秒
                                        GestureDetector(
                                          onTap: () {
                                            _resetHideTimer();
                                            final controller =
                                                PipOverlayService.getSavedController<
                                                  VideoDetailController
                                                >();
                                            final plController =
                                                controller?.plPlayerController;
                                            if (plController != null) {
                                              final current = Duration(
                                                seconds:
                                                    plController.position.value,
                                              );
                                              plController.seekTo(
                                                current +
                                                    const Duration(seconds: 10),
                                              );
                                            }
                                          },
                                          child: const Icon(
                                            Icons.forward_10,
                                            color: Colors.white,
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
