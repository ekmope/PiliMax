import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:PiliMax/common/widgets/image/network_img_layer.dart';
import 'package:PiliMax/common/widgets/video_card/video_transition_registry.dart';
import 'package:PiliMax/pages/video/video_detail_session.dart';

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
  _VideoPopPhase _phase = _VideoPopPhase.idle;
  VideoReturnTarget? _returnTarget;
  bool _routeCompleted = false;
  double _lastProgress = 0;
  double _commitStartProgress = 0;
  double _cancelStartProgress = 0;

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
    _routeCompleted = widget.animation.status == AnimationStatus.completed;
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
  bool handleStartBackGesture(PredictiveBackEvent backEvent) {
    if (!widget.enablePredictiveBack ||
        backEvent.isButtonEvent ||
        !_isEnabled) {
      return false;
    }
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
    if (status == AnimationStatus.reverse &&
        _routeCompleted &&
        _phase == _VideoPopPhase.idle) {
      _phase = _VideoPopPhase.programmatic;
      _handleAnimationTick();
    }
  }

  void _finishCancel() {
    _phase = _VideoPopPhase.idle;
    _setProgress(0);
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
    } else if (next == 0) {
      final cancelPreparedExit =
          _arguments?[videoDetailCancelPreparedExitKey] as VoidCallback?;
      cancelPreparedExit?.call();
      _returnTarget = null;
    }
    _lastProgress = next;
    if (_progress.value != next) {
      _progress.value = next;
    }
  }

  @override
  void dispose() {
    _VideoRouteAnimations.unregister(widget.animation);
    if (widget.enablePredictiveBack) {
      WidgetsBinding.instance.removeObserver(this);
    }
    widget.animation
      ..removeListener(_handleAnimationTick)
      ..removeStatusListener(_handleAnimationStatus);
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.token == null && !_routeCompleted
        ? FadeTransition(opacity: widget.animation, child: widget.child)
        : widget.child;
    return ValueListenableBuilder<double>(
      valueListenable: _progress,
      child: child,
      builder: (context, progress, child) {
        if (progress <= 0) {
          return child!;
        }
        return VideoPageExitTransition(
          progress: progress,
          returnTarget: _returnTarget,
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
    required this.child,
  });

  final double progress;
  final VideoReturnTarget? returnTarget;
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
        return target == null
            ? _fallbackTransition(size)
            : _sharedElementTransition(size, target);
      },
    );
  }

  Widget _fallbackTransition(Size size) {
    final scale = lerpDouble(1, 0.92, progress)!;
    final opacity = 1 - _interval(progress, 0.62, 1);
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: Transform.scale(
            scale: scale,
            child: Opacity(
              opacity: opacity,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24 * progress / scale),
                child: SizedBox.fromSize(size: size, child: child),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _sharedElementTransition(Size size, VideoReturnTarget target) {
    final screenRect = Offset.zero & size;
    final currentRect = Rect.lerp(screenRect, target.rect, progress)!;
    final snapshotBlend = _snapshotBlend(currentRect, target.rect);
    final liveOpacity = 1 - snapshotBlend;
    final radius = _maxRadius(target.borderRadius);
    final cardOpacity = snapshotBlend;
    final currentRadius = lerpDouble(0, radius, progress)!;

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fromRect(
          rect: currentRect,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(currentRadius),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Opacity(
                  opacity: liveOpacity,
                  child: FittedBox(
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                    child: SizedBox.fromSize(size: size, child: child),
                  ),
                ),
                Opacity(
                  opacity: cardOpacity,
                  child: target.snapshot == null
                      ? _VideoCardFallback(coverUrl: target.coverUrl)
                      : RawImage(
                          image: target.snapshot,
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.medium,
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static double _maxRadius(BorderRadius radius) => [
    radius.topLeft.x,
    radius.topRight.x,
    radius.bottomLeft.x,
    radius.bottomRight.x,
  ].reduce((a, b) => a > b ? a : b);

  static double _snapshotBlend(Rect current, Rect target) {
    if (target.width <= 0 || target.height <= 0) {
      return 0;
    }
    final sizeRatio = math.max(
      current.width / target.width,
      current.height / target.height,
    );
    final targetDiagonal = math.sqrt(
      target.width * target.width + target.height * target.height,
    );
    final centerDistance = (current.center - target.center).distance;
    final normalizedCenterDistance = targetDiagonal <= 0
        ? double.infinity
        : centerDistance / targetDiagonal;
    final sizeBlend = _inverseInterval(sizeRatio, 1.14, 1.03);
    final centerBlend = _inverseInterval(
      normalizedCenterDistance,
      0.14,
      0.025,
    );
    return Curves.easeInOutCubic.transform(math.min(sizeBlend, centerBlend));
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

class _VideoCardFallback extends StatelessWidget {
  const _VideoCardFallback({required this.coverUrl});

  final String? coverUrl;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final coverHeight = (size.width / (16 / 9))
            .clamp(0.0, size.height)
            .toDouble();
        if (size.height - coverHeight < 36) {
          return NetworkImgLayer(
            src: coverUrl,
            width: size.width,
            height: size.height,
            borderRadius: BorderRadius.zero,
            clip: false,
          );
        }
        return ColoredBox(
          color: colorScheme.surfaceContainerLow,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              NetworkImgLayer(
                src: coverUrl,
                width: size.width,
                height: coverHeight,
                borderRadius: BorderRadius.zero,
                clip: false,
              ),
              if (coverHeight < size.height)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: size.width * 0.72,
                          height: 7,
                          color: colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.18,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          width: size.width * 0.44,
                          height: 6,
                          color: colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
