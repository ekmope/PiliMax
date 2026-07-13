import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:PiliMax/common/widgets/video_card/video_detail_hero.dart';
import 'package:PiliMax/pages/video/video_layout_metrics.dart';
import 'package:PiliMax/utils/storage_pref.dart';

import 'package:flutter/material.dart';

const videoDetailEntryOverlayKey = '_videoDetailEntryOverlay';

/// Owns the paint-only detail skeleton shown underneath a video Hero flight.
///
/// Create the controller and call [insert] before pushing the detail route,
/// then bind the route animation as soon as it becomes available. The entry is
/// deliberately non-interactive and is removed as soon as the route reverses.
final class VideoDetailEntryOverlayController {
  factory VideoDetailEntryOverlayController({
    required OverlayState overlay,
    required bool? isVertical,
    required VideoDetailSkeletonVariant variant,
    String? title,
    bool expandedIntro = false,
    bool showRecommendations = true,
    bool hasSeasonPanel = false,
    bool hasPagesPanel = false,
    Duration revealDuration = const Duration(milliseconds: 320),
  }) => VideoDetailEntryOverlayController._(
    overlay: overlay,
    isVertical: isVertical,
    variant: variant,
    title: title,
    expandedIntro: expandedIntro,
    showRecommendations: showRecommendations,
    hasSeasonPanel: hasSeasonPanel,
    hasPagesPanel: hasPagesPanel,
    revealDuration: revealDuration,
  );

  VideoDetailEntryOverlayController._({
    required this._overlay,
    required this._isVertical,
    required this._variant,
    required this._title,
    required this.expandedIntro,
    required this.showRecommendations,
    required this._hasSeasonPanel,
    required this._hasPagesPanel,
    required this.revealDuration,
  }) {
    _activeController?.abort();
    _activeController = this;
  }

  static VideoDetailEntryOverlayController? _activeController;

  static bool get isEnteringVideo => _activeController?.isActive ?? false;

  final OverlayState _overlay;
  bool? _isVertical;
  VideoDetailSkeletonVariant _variant;
  String? _title;
  final bool expandedIntro;
  final bool showRecommendations;
  bool _hasSeasonPanel;
  bool _hasPagesPanel;
  final Duration revealDuration;

  OverlayEntry? _entry;
  Animation<double>? _routeAnimation;
  _VideoDetailEntryOverlayState? _presentation;
  Completer<void>? _revealCompleter;
  bool _revealRequested = false;
  bool _routeCompleted = false;
  bool _removed = false;
  bool _disposed = false;

  bool get isActive => _entry != null && !_removed && !_disposed;

  /// Inserts the entry once. Repeated calls are harmless.
  void insert() {
    if (_disposed || _removed || _entry != null) {
      return;
    }
    final entry = OverlayEntry(
      builder: (context) => Positioned.fill(
        child: _VideoDetailEntryOverlay(controller: this),
      ),
    );
    _entry = entry;
    _overlay.insert(entry);
  }

  /// Restores the intended route < skeleton < Hero stacking order.
  ///
  /// Navigator inserts its opaque route entries during push. Calling this in
  /// the same tap callback, before the first frame, keeps this entry above the
  /// route while the HeroController will insert its flight above both.
  void bringToFront() {
    final entry = _entry;
    if (!isActive || entry == null) {
      return;
    }
    entry.remove();
    _overlay.insert(entry);
  }

  void updateProfile({
    bool? isVertical,
    VideoDetailSkeletonVariant? variant,
    String? title,
    bool? hasSeasonPanel,
    bool? hasPagesPanel,
  }) {
    if (!isActive || _revealRequested) {
      return;
    }
    final orientationChanged = isVertical != null && isVertical != _isVertical;
    if (orientationChanged) {
      _presentation?._prepareProfileChange();
    }
    _isVertical = isVertical ?? _isVertical;
    _variant = variant ?? _variant;
    _title = title ?? _title;
    _hasSeasonPanel = hasSeasonPanel ?? _hasSeasonPanel;
    _hasPagesPanel = hasPagesPanel ?? _hasPagesPanel;
    _entry?.markNeedsBuild();
  }

  /// Makes the entry follow the exact progress used by the route and Hero.
  ///
  /// Passing a different animation safely detaches the previous one. An
  /// unbound entry remains at progress zero and is therefore not visible.
  void bindRouteAnimation(Animation<double>? animation) {
    if (_disposed || _removed || identical(animation, _routeAnimation)) {
      return;
    }
    _detachRouteAnimation();
    _routeAnimation = animation;
    if (animation == null) {
      _entry?.markNeedsBuild();
      return;
    }
    animation
      ..addListener(_onRouteAnimationTick)
      ..addStatusListener(_onRouteAnimationStatus);
    _routeCompleted = animation.status == AnimationStatus.completed;
    if (animation.status == AnimationStatus.dismissed ||
        (animation.status == AnimationStatus.reverse && _routeCompleted)) {
      abort();
      return;
    }
    _entry?.markNeedsBuild();
  }

  /// Fades the skeleton away while the real detail content becomes visible.
  ///
  /// The returned future completes after the fade or after any early cleanup.
  Future<void> beginReveal() {
    if (!isActive) {
      return Future<void>.value();
    }
    final existing = _revealCompleter;
    if (existing != null) {
      return existing.future;
    }
    final completer = Completer<void>();
    _revealCompleter = completer;
    _revealRequested = true;
    _presentation?._beginReveal();
    return completer.future;
  }

  /// Removes the skeleton immediately after a successful content handoff.
  void complete() => _remove();

  /// Removes the skeleton immediately when navigation or preparation aborts.
  void abort() => _remove();

  /// Permanently releases the controller. Repeated calls are harmless.
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _remove();
  }

  double get _routeProgress => (_routeAnimation?.value ?? 0).clamp(0.0, 1.0);

  void _onRouteAnimationTick() => _entry?.markNeedsBuild();

  void _onRouteAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _routeCompleted = true;
    } else if (status == AnimationStatus.dismissed ||
        (status == AnimationStatus.reverse && _routeCompleted)) {
      abort();
    }
  }

  void _attachPresentation(_VideoDetailEntryOverlayState presentation) {
    if (_removed || _disposed) {
      return;
    }
    _presentation = presentation;
    if (_revealRequested) {
      presentation._beginReveal();
    }
  }

  void _detachPresentation(_VideoDetailEntryOverlayState presentation) {
    if (identical(_presentation, presentation)) {
      _presentation = null;
    }
  }

  void _detachRouteAnimation() {
    final animation = _routeAnimation;
    if (animation == null) {
      return;
    }
    animation
      ..removeListener(_onRouteAnimationTick)
      ..removeStatusListener(_onRouteAnimationStatus);
    _routeAnimation = null;
  }

  void _remove() {
    if (_removed) {
      _completeRevealFuture();
      return;
    }
    _removed = true;
    if (identical(_activeController, this)) {
      _activeController = null;
    }
    _detachRouteAnimation();
    _presentation = null;
    final entry = _entry;
    _entry = null;
    if (entry != null) {
      entry
        ..remove()
        ..dispose();
    }
    _completeRevealFuture();
  }

  void _completeRevealFuture() {
    final completer = _revealCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }
}

class _VideoDetailEntryOverlay extends StatefulWidget {
  const _VideoDetailEntryOverlay({required this.controller});

  final VideoDetailEntryOverlayController controller;

  @override
  State<_VideoDetailEntryOverlay> createState() =>
      _VideoDetailEntryOverlayState();
}

class _VideoDetailEntryOverlayState extends State<_VideoDetailEntryOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _revealController = AnimationController(
    vsync: this,
    duration: widget.controller.revealDuration,
  )..addStatusListener(_onRevealStatus);
  late final AnimationController _profileController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );

  bool _revealStarted = false;
  double? _profileFromPlayerBottom;

  @override
  void initState() {
    super.initState();
    widget.controller._attachPresentation(this);
  }

  void _beginReveal() {
    if (!mounted || _revealStarted) {
      return;
    }
    _revealStarted = true;
    _revealController.forward();
  }

  void _prepareProfileChange() {
    if (!mounted) {
      return;
    }
    final viewport = MediaQuery.sizeOf(context);
    final target = _targetPlayerBottom(viewport);
    final from = _profileFromPlayerBottom;
    _profileFromPlayerBottom = from == null
        ? target
        : lerpDouble(
            from,
            target,
            Curves.easeInOutCubic.transform(_profileController.value),
          );
    _profileController.forward(from: 0);
  }

  double _targetPlayerBottom(Size viewport) {
    final topInset = Pref.removeSafeArea
        ? 0.0
        : MediaQuery.viewPaddingOf(context).top;
    return VideoDetailLayoutMetrics.entryPlayerBottom(
      viewport,
      isVertical: widget.controller._isVertical,
      topInset: topInset,
    );
  }

  void _onRevealStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      widget.controller.complete();
    }
  }

  @override
  void dispose() {
    widget.controller._detachPresentation(this);
    _revealController
      ..removeStatusListener(_onRevealStatus)
      ..dispose();
    _profileController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([_revealController, _profileController]),
    builder: (context, _) {
      final viewport = MediaQuery.sizeOf(context);
      final targetPlayerBottom = _targetPlayerBottom(viewport);
      final profileFrom = _profileFromPlayerBottom;
      final playerBottom = profileFrom == null
          ? targetPlayerBottom
          : lerpDouble(
              profileFrom,
              targetPlayerBottom,
              Curves.easeInOutCubic.transform(_profileController.value),
            )!;
      final routeProgress = Curves.easeOutCubic.transform(
        widget.controller._routeProgress,
      );
      final routeOpacity = const Interval(
        0,
        0.72,
        curve: Curves.easeOutCubic,
      ).transform(widget.controller._routeProgress);
      final revealOpacity =
          1 -
          Curves.easeInOutCubic.transform(
            _revealController.value,
          );
      final entryOffset = (viewport.height - targetPlayerBottom).clamp(
        0.0,
        viewport.height,
      );
      final profileOffset = playerBottom - targetPlayerBottom;

      return Stack(
        fit: StackFit.expand,
        children: [
          IgnorePointer(
            child: Opacity(
              opacity: routeOpacity * revealOpacity,
              child: Transform.translate(
                offset: Offset(
                  0,
                  entryOffset * (1 - routeProgress) + profileOffset,
                ),
                child: VideoDetailHeroShell(
                  playerSurfaceOpacity: 0,
                  navigationSurfaceOpacity: 1,
                  detailSurfaceOpacity: 1,
                  recommendationSurfaceOpacity: 1,
                  isVertical: widget.controller._isVertical,
                  variant: widget.controller._variant,
                  title: widget.controller._title,
                  expandedIntro: widget.controller.expandedIntro,
                  showRecommendations: widget.controller.showRecommendations,
                  hasSeasonPanel: widget.controller._hasSeasonPanel,
                  hasPagesPanel: widget.controller._hasPagesPanel,
                ),
              ),
            ),
          ),
          Positioned(
            top: playerBottom,
            left: 0,
            right: 0,
            bottom: 0,
            child: const AbsorbPointer(child: SizedBox.expand()),
          ),
        ],
      );
    },
  );
}
