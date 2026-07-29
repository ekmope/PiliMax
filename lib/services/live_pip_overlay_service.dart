import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' show max;

import 'package:PiliMax/common/widgets/pip_mini_video_content.dart';
import 'package:PiliMax/plugin/pl_player/controller.dart';
import 'package:PiliMax/services/pip_transition_coordinator.dart';
import 'package:PiliMax/utils/storage_pref.dart';
import 'package:PiliMax/utils/device_utils.dart';
import 'package:flutter/foundation.dart';
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

  double get _width => (LivePipOverlayService.isVertical ? 112 : 200) * _scale;
  double get _height => (LivePipOverlayService.isVertical ? 200 : 112) * _scale;

  bool _showControls = true;
  Timer? _hideTimer;
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
    _startHideTimer();
  }

  void _onPhaseChanged() {
    final phase = _transition.phase;
    if (phase != _lastPhase) {
      _lastPhase = phase;
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
    _hideTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  void _onTap() {
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls) {
      _startHideTimer();
    }
  }

  void _onDoubleTap() {
    setState(() {
      if (_scale < 1.1) {
        _scale = 1.5;
      } else if (_scale < 1.6) {
        _scale = 2.0;
      } else {
        _scale = 1.0;
      }

      // 缩放后立即计算并约束位置，防止按钮或部分窗口超出屏幕
      final screenSize = MediaQuery.of(context).size;
      _left = (_left ?? 0.0)
          .clamp(0.0, max(0.0, screenSize.width - _width))
          .toDouble();
      _top = (_top ?? 0.0)
          .clamp(0.0, max(0.0, screenSize.height - _height))
          .toDouble();
    });
    PipWindowMemory.scale = _scale;
    PipWindowMemory.position = Offset(_left ?? 0, _top ?? 0);
    _startHideTimer();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

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
          final miniRect = Rect.fromLTWH(_left!, _top!, _width, _height);
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

          return Positioned(
            left: rect.left,
            top: rect.top,
            child: IgnorePointer(
              ignoring: !interactive,
              child: GestureDetector(
                onTap: _onTap,
                onDoubleTap: _onDoubleTap,
                onPanStart: (_) {
                  _hideTimer?.cancel();
                },
                onPanUpdate: (details) {
                  setState(() {
                    _left = (_left! + details.delta.dx)
                        .clamp(
                          0.0,
                          max(0.0, screenSize.width - _width),
                        )
                        .toDouble();
                    _top = (_top! + details.delta.dy)
                        .clamp(
                          0.0,
                          max(0.0, screenSize.height - _height),
                        )
                        .toDouble();
                  });
                  PipWindowMemory.position = Offset(_left!, _top!);
                },
                onPanEnd: (_) {
                  if (_showControls) {
                    _startHideTimer();
                  }
                },
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
                      duration: inTransition
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
                                  plPlayerController: widget.plPlayerController,
                                  transition: _transition,
                                ),
                              ),
                            ),
                            if (interactive && _showControls) ...[
                              Positioned.fill(
                                child: Container(
                                  color: Colors.black.withValues(alpha: 0.4),
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
                            ],
                          ],
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
