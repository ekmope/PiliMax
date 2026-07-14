import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:PiliMax/common/widgets/video_card/video_transition_registry.dart';
import 'package:PiliMax/pages/video/video_detail_entry_overlay.dart';
import 'package:PiliMax/pages/video/video_detail_exit_snapshot.dart';
import 'package:PiliMax/pages/video/video_detail_session.dart';
import 'package:PiliMax/services/video_transition_diagnostics.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Keeps the stock Android transition everywhere except the video route.
///
/// The video route still forwards Android predictive-back events into its
/// PageRoute, but owns the visual transform so it is not animated twice.
class AppPredictiveBackPageTransitionsBuilder extends PageTransitionsBuilder {
  const AppPredictiveBackPageTransitionsBuilder();

  static const _delegate = PredictiveBackPageTransitionsBuilder();

  @override
  Duration get transitionDuration => _delegate.transitionDuration;

  @override
  Duration get reverseTransitionDuration => _delegate.reverseTransitionDuration;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (route.settings.name != '/videoV') {
      return AnimatedBuilder(
        animation: secondaryAnimation,
        child: child,
        builder: (context, child) =>
            _VideoRouteAnimations.drives(secondaryAnimation)
            ? child!
            : _delegate.buildTransitions(
                route,
                context,
                animation,
                secondaryAnimation,
                child!,
              ),
      );
    }
    final arguments = route.settings.arguments;
    final token = arguments is Map
        ? arguments[videoTransitionTokenKey] as VideoTransitionToken?
        : null;
    if (arguments is Map) {
      (arguments[videoDetailEntryOverlayKey]
              as VideoDetailEntryOverlayController?)
          ?.bindRouteAnimation(route.offstage ? null : animation);
    }
    _VideoRouteAnimations.register(animation);
    return _VideoPredictiveBackDriver(
      route: route,
      animation: animation,
      token: token,
      enablePredictiveBack: true,
      child: child,
    );
  }
}

/// Preserves the same video back-button transition when predictive back is off.
class AppZoomPageTransitionsBuilder extends PageTransitionsBuilder {
  const AppZoomPageTransitionsBuilder();

  static const _delegate = ZoomPageTransitionsBuilder();

  @override
  DelegatedTransitionBuilder? get delegatedTransition => _delegatedTransition;

  static Widget? _delegatedTransition(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    bool allowSnapshotting,
    Widget? child,
  ) {
    final delegatedTransition = _delegate.delegatedTransition;
    if (delegatedTransition == null) {
      return child;
    }
    return AnimatedBuilder(
      animation: secondaryAnimation,
      child: child ?? const SizedBox.shrink(),
      builder: (context, child) =>
          _VideoRouteAnimations.drives(secondaryAnimation)
          ? child!
          : delegatedTransition(
                  context,
                  animation,
                  secondaryAnimation,
                  allowSnapshotting,
                  child,
                ) ??
                child!,
    );
  }

  @override
  Duration get transitionDuration => _delegate.transitionDuration;

  @override
  Duration get reverseTransitionDuration => _delegate.reverseTransitionDuration;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (route.settings.name != '/videoV') {
      return AnimatedBuilder(
        animation: secondaryAnimation,
        child: child,
        builder: (context, child) =>
            _VideoRouteAnimations.drives(secondaryAnimation)
            ? child!
            : _delegate.buildTransitions(
                route,
                context,
                animation,
                secondaryAnimation,
                child!,
              ),
      );
    }
    final arguments = route.settings.arguments;
    final token = arguments is Map
        ? arguments[videoTransitionTokenKey] as VideoTransitionToken?
        : null;
    if (arguments is Map) {
      (arguments[videoDetailEntryOverlayKey]
              as VideoDetailEntryOverlayController?)
          ?.bindRouteAnimation(route.offstage ? null : animation);
    }
    _VideoRouteAnimations.register(animation);
    return _VideoPredictiveBackDriver(
      route: route,
      animation: animation,
      token: token,
      enablePredictiveBack: false,
      child: child,
    );
  }
}

abstract final class _VideoRouteAnimations {
  static final Set<Animation<double>> _animations =
      HashSet<Animation<double>>.identity();

  static void register(Animation<double> animation) {
    _animations.add(animation);
  }

  static void unregister(Animation<double> animation) {
    _animations.remove(animation);
  }

  static bool drives(Animation<double> animation) {
    final candidateChain = _animationChain(animation);
    for (final registered in _animations) {
      if (_animationChain(registered).any(candidateChain.contains)) {
        return true;
      }
    }
    return false;
  }

  static Set<Animation<double>> _animationChain(Animation<double> animation) {
    final chain = HashSet<Animation<double>>.identity();
    Animation<double>? current = animation;
    while (current != null && chain.add(current)) {
      current = switch (current) {
        ProxyAnimation(:final parent) => parent,
        ReverseAnimation(:final parent) => parent,
        CurvedAnimation(:final parent) => parent,
        _ => null,
      };
    }
    return chain;
  }
}

enum _VideoPopPhase { idle, predicting, canceling, committing, programmatic }

class _VideoPredictiveBackDriver extends StatefulWidget {
  const _VideoPredictiveBackDriver({
    required this.route,
    required this.animation,
    required this.token,
    required this.enablePredictiveBack,
    required this.child,
  });

  final PageRoute<dynamic> route;
  final Animation<double> animation;
  final VideoTransitionToken? token;
  final bool enablePredictiveBack;
  final Widget child;

  @override
  State<_VideoPredictiveBackDriver> createState() =>
      _VideoPredictiveBackDriverState();
}

class _VideoPredictiveBackDriverState extends State<_VideoPredictiveBackDriver>
    with WidgetsBindingObserver {
  final ValueNotifier<double> _progress = ValueNotifier(0);
  final SnapshotController _snapshotController = SnapshotController();
  final GlobalKey _transitionRootKey = GlobalKey();
  _VideoPopPhase _phase = _VideoPopPhase.idle;
  VideoReturnTarget? _returnTarget;
  VideoDetailExitVisual? _exitVisual;
  Widget? _exitTexture;
  bool _routeCompleted = false;
  double _lastProgress = 0;
  double _commitStartProgress = 0;
  double _cancelStartProgress = 0;
  int? _forwardDiagnosticId;
  int? _backDiagnosticId;

  Map<dynamic, dynamic>? get _arguments {
    final arguments = widget.route.settings.arguments;
    return arguments is Map ? arguments : null;
  }

  VideoDetailSession? get _session =>
      _arguments?[videoDetailSessionKey] as VideoDetailSession?;

  bool get _isEnabled =>
      widget.route.isCurrent && widget.route.popGestureEnabled;

  @override
  void initState() {
    super.initState();
    _VideoRouteAnimations.register(widget.animation);
    _routeCompleted =
        !widget.route.offstage &&
        widget.animation.status == AnimationStatus.completed;
    if (!_routeCompleted && widget.token != null) {
      _forwardDiagnosticId = VideoTransitionDiagnostics.begin(
        VideoTransitionDiagnosticKind.entry,
        expectedDuration: widget.route.transitionDuration,
      );
    }
    widget.animation
      ..addListener(_handleAnimationTick)
      ..addStatusListener(_handleAnimationStatus);
    if (widget.enablePredictiveBack) {
      WidgetsBinding.instance.addObserver(this);
    }
  }

  @override
  void didUpdateWidget(_VideoPredictiveBackDriver oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enablePredictiveBack != widget.enablePredictiveBack) {
      if (widget.enablePredictiveBack) {
        WidgetsBinding.instance.addObserver(this);
      } else {
        WidgetsBinding.instance.removeObserver(this);
      }
    }
    if (!identical(oldWidget.animation, widget.animation)) {
      _VideoRouteAnimations.unregister(oldWidget.animation);
      _VideoRouteAnimations.register(widget.animation);
      oldWidget.animation
        ..removeListener(_handleAnimationTick)
        ..removeStatusListener(_handleAnimationStatus);
      widget.animation
        ..addListener(_handleAnimationTick)
        ..addStatusListener(_handleAnimationStatus);
    }
    if (!identical(oldWidget.token, widget.token) && _progress.value == 0) {
      _returnTarget = null;
    }
  }

  @override
  void didChangeMetrics() {
    if (!_snapshotController.allowSnapshotting) {
      return;
    }
    _endSnapshotExit();
    _returnTarget = null;
    if (mounted) {
      setState(() {});
    }
  }

  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) {
    if (!widget.enablePredictiveBack ||
        backEvent.isButtonEvent ||
        !_isEnabled) {
      return false;
    }
    _finishBackDiagnostic('superseded');
    _backDiagnosticId = VideoTransitionDiagnostics.begin(
      VideoTransitionDiagnosticKind.predictiveBack,
    );
    _phase = _VideoPopPhase.predicting;
    _setProgress(backEvent.progress);
    widget.route.handleStartBackGesture(progress: 1 - backEvent.progress);
    return true;
  }

  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent backEvent) {
    if (_phase != _VideoPopPhase.predicting) {
      return;
    }
    VideoTransitionDiagnostics.recordInputEvent(_backDiagnosticId);
    _setProgress(backEvent.progress);
    widget.route.handleUpdateBackGestureProgress(
      progress: 1 - backEvent.progress,
    );
  }

  @override
  void handleCancelBackGesture() {
    if (_phase != _VideoPopPhase.predicting) {
      return;
    }
    _cancelStartProgress = _lastProgress;
    _phase = _VideoPopPhase.canceling;
    widget.route.handleCancelBackGesture();
    if (!mounted) {
      return;
    }
    if (widget.animation.isCompleted) {
      _finishCancel();
    } else {
      _handleAnimationTick();
    }
  }

  @override
  void handleCommitBackGesture() {
    if (_phase != _VideoPopPhase.predicting) {
      return;
    }
    _commitStartProgress = _lastProgress;
    _phase = _VideoPopPhase.committing;
    widget.route.handleCommitBackGesture();
    if (mounted) {
      _handleAnimationTick();
    }
  }

  void _handleAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _finishForwardDiagnostic('completed');
      if (_phase == _VideoPopPhase.canceling) {
        _finishCancel();
        return;
      }
      if (!_routeCompleted) {
        _routeCompleted = true;
        if (mounted) {
          setState(() {});
        }
      }
      return;
    }
    if (status == AnimationStatus.dismissed) {
      if (_phase == _VideoPopPhase.committing) {
        _finishBackDiagnostic('committed');
      } else if (_phase == _VideoPopPhase.programmatic) {
        _finishBackDiagnostic('completed');
      }
      return;
    }
    if (status == AnimationStatus.reverse &&
        _routeCompleted &&
        _phase == _VideoPopPhase.idle) {
      _phase = _VideoPopPhase.programmatic;
      _finishBackDiagnostic('superseded');
      _backDiagnosticId = VideoTransitionDiagnostics.begin(
        VideoTransitionDiagnosticKind.programmaticBack,
        expectedDuration: widget.route.reverseTransitionDuration,
      );
      _handleAnimationTick();
    }
  }

  void _finishCancel() {
    _phase = _VideoPopPhase.idle;
    _setProgress(0);
    _finishBackDiagnostic('canceled');
  }

  void _finishForwardDiagnostic(String outcome) {
    final captureId = _forwardDiagnosticId;
    _forwardDiagnosticId = null;
    VideoTransitionDiagnostics.finish(captureId, outcome: outcome);
  }

  void _finishBackDiagnostic(String outcome) {
    final captureId = _backDiagnosticId;
    _backDiagnosticId = null;
    VideoTransitionDiagnostics.finish(captureId, outcome: outcome);
  }

  void _handleAnimationTick() {
    switch (_phase) {
      case _VideoPopPhase.canceling:
        final rawProgress = 1 - widget.animation.value;
        final normalized = _cancelStartProgress <= 0
            ? 0.0
            : (rawProgress / _cancelStartProgress).clamp(0.0, 1.0);
        _setProgress(
          _cancelStartProgress * Curves.easeInOutCubic.transform(normalized),
        );
        break;
      case _VideoPopPhase.programmatic:
        _setProgress(
          Curves.easeInOutCubic.transform(1 - widget.animation.value),
        );
        break;
      case _VideoPopPhase.committing:
        final leg = 1 - widget.animation.value;
        _setProgress(
          lerpDouble(
            _commitStartProgress,
            1,
            Curves.easeOutCubic.transform(leg.clamp(0, 1)),
          )!,
        );
        break;
      case _VideoPopPhase.idle:
      case _VideoPopPhase.predicting:
        break;
    }
  }

  void _setProgress(double value) {
    final next = value.clamp(0.0, 1.0);
    if (_lastProgress == 0 && next > 0) {
      final prepareForExit =
          _arguments?[videoDetailPrepareForExitKey]
              as VideoDetailPrepareForExit?;
      final preparedForSharedElement = prepareForExit?.call() ?? true;
      final session = _session;
      final token = widget.token;
      final canReturnToSource =
          preparedForSharedElement &&
          token != null &&
          (session == null ||
              (session.matchesLaunchContent &&
                  session.launchContentKey == token.contentKey));
      _returnTarget = canReturnToSource
          ? VideoTransitionRegistry.resolveReturn(token)
          : null;
      _prepareSnapshotExit();
    } else if (next == 0) {
      final cancelPreparedExit =
          _arguments?[videoDetailCancelPreparedExitKey] as VoidCallback?;
      cancelPreparedExit?.call();
      _returnTarget = null;
      _endSnapshotExit();
    }
    _lastProgress = next;
    if (_progress.value != next) {
      _progress.value = next;
    }
  }

  void _prepareSnapshotExit() {
    _exitVisual?.dispose();
    final provider =
        _arguments?[videoDetailExitVisualProviderKey]
            as VideoDetailExitVisualProvider?;
    final transitionRoot = _transitionRootKey.currentContext
        ?.findRenderObject();
    final visual = transitionRoot is RenderBox
        ? provider?.call(transitionRoot)
        : null;
    if (visual?.isUsable == true) {
      _exitVisual = visual;
    } else {
      visual?.dispose();
      _exitVisual = null;
    }
    _exitTexture = _exitVisual?.buildLiveTexture();
    _snapshotController.allowSnapshotting = _exitVisual != null;
  }

  void _endSnapshotExit() {
    final visual = _exitVisual;
    _snapshotController.allowSnapshotting = false;
    _exitVisual = null;
    _exitTexture = null;
    visual?.dispose();
  }

  @override
  void dispose() {
    _finishForwardDiagnostic('disposed');
    _finishBackDiagnostic('disposed');
    _VideoRouteAnimations.unregister(widget.animation);
    if (widget.enablePredictiveBack) {
      WidgetsBinding.instance.removeObserver(this);
    }
    widget.animation
      ..removeListener(_handleAnimationTick)
      ..removeStatusListener(_handleAnimationStatus);
    _exitVisual?.dispose();
    _exitVisual = null;
    _exitTexture = null;
    _snapshotController.dispose();
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final page = widget.token == null && !_routeCompleted
        ? FadeTransition(opacity: widget.animation, child: widget.child)
        : widget.child;
    return ValueListenableBuilder<double>(
      valueListenable: _progress,
      child: SnapshotWidget(
        controller: _snapshotController,
        mode: SnapshotMode.forced,
        child: RepaintBoundary(
          key: _transitionRootKey,
          child: SizedBox.expand(child: page),
        ),
      ),
      builder: (context, progress, child) {
        return VideoPageExitTransition(
          progress: progress,
          returnTarget: _returnTarget,
          exitVisual: _exitVisual,
          exitTexture: _exitTexture,
          child: child!,
        );
      },
    );
  }
}

class VideoPageExitTransition extends StatelessWidget {
  const VideoPageExitTransition({
    super.key,
    required this.progress,
    required this.returnTarget,
    this.exitVisual,
    this.exitTexture,
    required this.child,
  });

  final double progress;
  final VideoReturnTarget? returnTarget;
  final VideoDetailExitVisual? exitVisual;
  final Widget? exitTexture;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        if (size.isEmpty) {
          return child;
        }
        final target = returnTarget;
        final hasSharedTarget = target != null && !target.rect.isEmpty;
        final geometry = hasSharedTarget
            ? _sharedElementGeometry(size, target)
            : _fallbackGeometry(size);
        return _livePageLayer(geometry);
      },
    );
  }

  _VideoExitGeometry _fallbackGeometry(Size size) {
    final scale = lerpDouble(1, 0.92, progress)!;
    final opacity = 1 - _interval(progress, 0.62, 1);
    final scaledSize = size * scale;
    final currentRect = Rect.fromCenter(
      center: (Offset.zero & size).center,
      width: scaledSize.width,
      height: scaledSize.height,
    );
    return _VideoExitGeometry(
      clipRect: currentRect,
      visibleClipRect: currentRect,
      contentTransform: Matrix4.identity()
        ..translateByDouble(currentRect.left, currentRect.top, 0, 1)
        ..scaleByDouble(scale, scale, 1, 1),
      borderRadius: 24 * progress,
      liveOpacity: opacity,
    );
  }

  _VideoExitGeometry _sharedElementGeometry(
    Size size,
    VideoReturnTarget target,
  ) {
    final screenRect = Offset.zero & size;
    final currentRect = Rect.lerp(screenRect, target.rect, progress)!;
    final sourceHandoff = _sourceHandoff(currentRect, target.rect);
    final radius = _maxRadius(target.borderRadius);
    final contentScale = math.max(
      currentRect.width / size.width,
      currentRect.height / size.height,
    );
    final scaledWidth = size.width * contentScale;
    final contentLeft =
        currentRect.left + (currentRect.width - scaledWidth) / 2;

    return _VideoExitGeometry(
      clipRect: currentRect,
      visibleClipRect: Rect.lerp(
        screenRect,
        target.visibleRect,
        progress,
      )!.intersect(currentRect),
      contentTransform: Matrix4.identity()
        ..translateByDouble(contentLeft, currentRect.top, 0, 1)
        ..scaleByDouble(contentScale, contentScale, 1, 1),
      borderRadius: lerpDouble(0, radius, progress)!,
      liveOpacity: 1 - sourceHandoff,
    );
  }

  Widget _livePageLayer(_VideoExitGeometry geometry) {
    return ClipRect(
      clipper: _VideoExitRectClipper(geometry.visibleClipRect),
      clipBehavior: progress <= 0 ? Clip.none : Clip.hardEdge,
      child: ClipRRect(
        clipper: _VideoExitClipper(geometry.clipRRect),
        clipBehavior: progress <= 0 ? Clip.none : Clip.antiAlias,
        child: Opacity(
          opacity: geometry.liveOpacity,
          child: Transform(
            alignment: Alignment.topLeft,
            transform: geometry.contentTransform,
            transformHitTests: false,
            child: Stack(
              fit: StackFit.expand,
              children: [
                child,
                if (exitVisual case final visual?)
                  Positioned.fromRect(
                    rect: visual.clipRect,
                    child: const ColoredBox(color: Colors.black),
                  ),
                if ((exitVisual, exitTexture) case (
                  final visual?,
                  final texture?,
                ))
                  ClipRect(
                    clipper: _VideoExitRectClipper(visual.clipRect),
                    clipBehavior: Clip.hardEdge,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Positioned.fromRect(
                          rect: visual.playerRect,
                          child: texture,
                        ),
                      ],
                    ),
                  ),
                if (exitVisual case final visual?)
                  for (final foreground in visual.foregrounds)
                    ClipRect(
                      clipper: _VideoExitRectClipper(foreground.clipRect),
                      clipBehavior: Clip.hardEdge,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Positioned.fromRect(
                            rect: foreground.rect,
                            child: foreground.build(),
                          ),
                        ],
                      ),
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static double _maxRadius(BorderRadius radius) => [
    radius.topLeft.x,
    radius.topRight.x,
    radius.bottomLeft.x,
    radius.bottomRight.x,
  ].reduce((a, b) => a > b ? a : b);

  static double _sourceHandoff(Rect current, Rect target) {
    if (target.width <= 0 || target.height <= 0) {
      return 0;
    }
    final sizeRatio = math.max(
      current.width / target.width,
      current.height / target.height,
    );
    return Curves.easeInOutCubic.transform(
      _inverseInterval(sizeRatio, 1.08, 1.02),
    );
  }

  static double _inverseInterval(double value, double begin, double end) {
    if (value >= begin) {
      return 0;
    }
    if (value <= end) {
      return 1;
    }
    return (begin - value) / (begin - end);
  }

  static double _interval(double value, double begin, double end) {
    if (value <= begin) {
      return 0;
    }
    if (value >= end) {
      return 1;
    }
    return (value - begin) / (end - begin);
  }
}

final class _VideoExitGeometry {
  const _VideoExitGeometry({
    required this.clipRect,
    required this.visibleClipRect,
    required this.contentTransform,
    required this.borderRadius,
    required this.liveOpacity,
  });

  final Rect clipRect;
  final Rect visibleClipRect;
  final Matrix4 contentTransform;
  final double borderRadius;
  final double liveOpacity;

  RRect get clipRRect => RRect.fromRectAndRadius(
    clipRect,
    Radius.circular(borderRadius),
  );
}

final class _VideoExitRectClipper extends CustomClipper<Rect> {
  const _VideoExitRectClipper(this.rect);

  final Rect rect;

  @override
  Rect getClip(Size size) => rect;

  @override
  bool shouldReclip(_VideoExitRectClipper oldClipper) =>
      oldClipper.rect != rect;
}

final class _VideoExitClipper extends CustomClipper<RRect> {
  const _VideoExitClipper(this.clipRRect);

  final RRect clipRRect;

  @override
  RRect getClip(Size size) => clipRRect;

  @override
  Rect getApproximateClipRect(Size size) => clipRRect.outerRect;

  @override
  bool shouldReclip(_VideoExitClipper oldClipper) =>
      oldClipper.clipRRect != clipRRect;
}
