import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:PiliMax/common/widgets/video_card/video_detail_hero.dart';
import 'package:PiliMax/common/widgets/video_card/video_transition_registry.dart';
import 'package:PiliMax/pages/video/video_detail_transition_timing.dart';
import 'package:PiliMax/pages/video/video_layout_metrics.dart';
import 'package:PiliMax/utils/storage_pref.dart';
import 'package:PiliMax/utils/theme_utils.dart';

import 'package:flutter/material.dart';

const videoDetailEntryOverlayKey = '_videoDetailEntryOverlay';

/// Owns the paint-only detail skeleton shown underneath a video Hero flight.
///
/// Create the controller and call [insert] before pushing the detail route,
/// then bind the route animation as soon as it becomes available. The entry is
/// deliberately non-interactive and follows a reversible route transition
/// until the route is dismissed or real detail content takes over.
final class VideoDetailEntryOverlayController {
  factory VideoDetailEntryOverlayController({
    required OverlayState overlay,
    required VideoTransitionToken transitionToken,
    required bool? isVertical,
    required VideoDetailSkeletonVariant variant,
    String? title,
    bool expandedIntro = false,
    bool showRecommendations = true,
    bool hasSeasonPanel = false,
    bool hasPagesPanel = false,
    int tabCount = VideoDetailLayoutMetrics.defaultTabCount,
    int actionCount = VideoDetailLayoutMetrics.ugcActionCount,
    bool hasEpisodePanel = false,
    Duration revealDuration = videoDetailTransitionDuration,
  }) => VideoDetailEntryOverlayController._(
    overlay: overlay,
    transitionToken: transitionToken,
    isVertical: isVertical,
    variant: variant,
    title: title,
    expandedIntro: expandedIntro,
    showRecommendations: showRecommendations,
    hasSeasonPanel: hasSeasonPanel,
    hasPagesPanel: hasPagesPanel,
    tabCount: tabCount,
    actionCount: actionCount,
    hasEpisodePanel: hasEpisodePanel,
    revealDuration: revealDuration,
  );

  VideoDetailEntryOverlayController._({
    required this._overlay,
    required this.transitionToken,
    required this._isVertical,
    required this._variant,
    required this._title,
    required this.expandedIntro,
    required this.showRecommendations,
    required this._hasSeasonPanel,
    required this._hasPagesPanel,
    required this._tabCount,
    required this._actionCount,
    required this._hasEpisodePanel,
    required this.revealDuration,
  }) {
    _activeController?.abort();
    _activeController = this;
  }

  static VideoDetailEntryOverlayController? _activeController;

  static bool get isEnteringVideo => _activeController?.isActive ?? false;

  final OverlayState _overlay;
  final VideoTransitionToken transitionToken;
  bool? _isVertical;
  VideoDetailSkeletonVariant _variant;
  String? _title;
  final bool expandedIntro;
  final bool showRecommendations;
  bool _hasSeasonPanel;
  bool _hasPagesPanel;
  int _tabCount;
  int _actionCount;
  bool _hasEpisodePanel;
  final Duration revealDuration;
  final ValueNotifier<double> _routeProgressNotifier = ValueNotifier(0);

  OverlayEntry? _entry;
  Animation<double>? _routeAnimation;
  _VideoDetailEntryOverlayState? _presentation;
  Completer<void>? _revealCompleter;
  bool _revealRequested = false;
  bool _reversibleExitInProgress = false;
  bool _removed = false;
  bool _disposed = false;
  bool _didCompleteReveal = false;

  bool get isActive => _entry != null && !_removed && !_disposed;

  bool get didCompleteReveal => _didCompleteReveal;

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
    int? tabCount,
    int? actionCount,
    bool? hasEpisodePanel,
  }) {
    if (!isActive || _revealRequested || _reversibleExitInProgress) {
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
    _tabCount = tabCount ?? _tabCount;
    _actionCount = actionCount ?? _actionCount;
    _hasEpisodePanel = hasEpisodePanel ?? _hasEpisodePanel;
    _presentation?._profileUpdated();
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
      _routeProgressNotifier.value = 0;
      return;
    }
    animation
      ..addListener(_onRouteAnimationTick)
      ..addStatusListener(_onRouteAnimationStatus);
    if (animation.status == AnimationStatus.dismissed) {
      abort();
      return;
    }
    _routeProgressNotifier.value = animation.value;
  }

  /// Keeps the entry presentation alive while predictive back reverses it.
  void beginReversibleExit() {
    if (isActive) {
      _reversibleExitInProgress = true;
    }
  }

  /// Resumes entry handoff after a predictive-back gesture is canceled.
  void cancelReversibleExit() {
    _reversibleExitInProgress = false;
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
  void complete() {
    _didCompleteReveal = true;
    _remove();
  }

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

  double get _routeProgress => _routeProgressNotifier.value.clamp(0.0, 1.0);

  bool get _hasRouteAnimation => _routeAnimation != null;

  void _onRouteAnimationTick() {
    final animation = _routeAnimation;
    if (animation != null) {
      _routeProgressNotifier.value = animation.value;
    }
  }

  void _onRouteAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      cancelReversibleExit();
    } else if (status == AnimationStatus.dismissed) {
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
    _reversibleExitInProgress = false;
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
  late final Listenable _animation = Listenable.merge([
    widget.controller._routeProgressNotifier,
    _revealController,
    _profileController,
  ]);

  bool _revealStarted = false;
  double? _profileFromPlayerBottom;
  Object? _ugcTitleHeightSignature;
  double _ugcTitleHeight = 38;

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

  void _profileUpdated() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  double _targetPlayerBottom(Size viewport) {
    return _targetPlayerRect(viewport).bottom;
  }

  Rect _targetPlayerRect(Size viewport) {
    final topInset = Pref.removeSafeArea
        ? 0.0
        : MediaQuery.viewPaddingOf(context).top;
    return VideoDetailLayoutMetrics.entryPlayerRect(
      viewport,
      isVertical: widget.controller._isVertical,
      topInset: topInset,
    );
  }

  Rect? _targetTitleRect(Size viewport, double playerBottom) {
    const padding = VideoDetailLayoutMetrics.horizontalPadding;
    final bodyTop = playerBottom + VideoDetailLayoutMetrics.tabBarHeight;
    return switch (widget.controller._variant) {
      VideoDetailSkeletonVariant.ugc => () {
        final top =
            bodyTop +
            VideoDetailLayoutMetrics.introTopPadding +
            VideoDetailLayoutMetrics.ownerHeight +
            VideoDetailLayoutMetrics.sectionGap;
        final availableHeight = (viewport.height - top)
            .clamp(0.0, viewport.height)
            .toDouble();
        final height = availableHeight.clamp(0.0, 48.0).toDouble();
        return Rect.fromLTWH(
          padding,
          top,
          (viewport.width - 2 * padding).clamp(0.0, viewport.width).toDouble(),
          height,
        );
      }(),
      VideoDetailSkeletonVariant.pgc || VideoDetailSkeletonVariant.pugv => () {
        final contentTop = bodyTop + padding;
        final coverWidth = (viewport.width * 0.32).clamp(0.0, 115.0).toDouble();
        final infoX = padding + coverWidth + 10;
        final infoWidth = (viewport.width - padding - infoX)
            .clamp(0.0, viewport.width)
            .toDouble();
        return Rect.fromLTWH(
          infoX,
          contentTop + 3,
          infoWidth * 0.62,
          34,
        );
      }(),
      VideoDetailSkeletonVariant.local => null,
    };
  }

  double _cachedUgcTitleHeight(BuildContext context, Size viewport) {
    final title = widget.controller._title;
    if (title == null || title.isEmpty) {
      return 38;
    }
    final style = DefaultTextStyle.of(context).style.copyWith(fontSize: 16);
    final textScaler = MediaQuery.textScalerOf(context);
    final signature = (title, style, textScaler, viewport.width);
    if (signature == _ugcTitleHeightSignature) {
      return _ugcTitleHeight;
    }
    _ugcTitleHeightSignature = signature;
    final painter =
        TextPainter(
          text: TextSpan(text: title, style: style),
          maxLines: 2,
          textDirection: Directionality.of(context),
          textScaler: textScaler,
        )..layout(
          maxWidth:
              (viewport.width - 2 * VideoDetailLayoutMetrics.horizontalPadding)
                  .clamp(0.0, viewport.width)
                  .toDouble(),
        );
    _ugcTitleHeight = painter.height;
    painter.dispose();
    return _ugcTitleHeight;
  }

  Widget _buildMorphingTitle({
    required Rect morphRect,
    required Size viewport,
    required double playerBottom,
    required double progress,
    required double revealOpacity,
  }) {
    final title = widget.controller.transitionToken.title;
    if (title == null || title.text.isEmpty) {
      return const SizedBox.shrink();
    }
    final targetRect = _targetTitleRect(viewport, playerBottom);
    final rect = Rect.lerp(title.rect, targetRect ?? title.rect, progress)!;
    final sourceFontSize = title.style.fontSize ?? 14;
    final fontSize = lerpDouble(sourceFontSize, 16, progress)!;
    final fontScale = fontSize / sourceFontSize;
    final handoffBegin = targetRect == null ? 0.20 : 0.52;
    final handoffEnd = targetRect == null ? 0.56 : 0.90;
    final handoffProgress =
        ((progress - handoffBegin) / (handoffEnd - handoffBegin))
            .clamp(0.0, 1.0)
            .toDouble();
    final titleEntryOpacity =
        widget.controller.transitionToken.sourceLayout ==
            VideoTransitionSourceLayout.horizontalRow
        ? 1.0
        : progress;
    final titleOpacity =
        titleEntryOpacity *
        revealOpacity *
        (1 - Curves.easeInOutCubic.transform(handoffProgress));
    if (titleOpacity <= 0) {
      return const SizedBox.shrink();
    }
    final textSpan = title.textSpan;
    return Positioned(
      left: rect.left - morphRect.left,
      top: rect.top - morphRect.top,
      width: rect.width,
      height: rect.height,
      child: Opacity(
        opacity: titleOpacity,
        child: textSpan != null
            ? Text.rich(
                _scaleInlineSpan(textSpan, fontScale),
                style: title.style.copyWith(fontSize: fontSize),
                maxLines: title.maxLines,
                textAlign: title.textAlign,
                overflow: title.overflow,
                textDirection: title.textDirection,
                textScaler: title.textScaler,
              )
            : Text(
                title.text,
                style: title.style.copyWith(fontSize: fontSize),
                maxLines: title.maxLines,
                textAlign: title.textAlign,
                overflow: title.overflow,
                textDirection: title.textDirection,
                textScaler: title.textScaler,
              ),
      ),
    );
  }

  static InlineSpan _scaleInlineSpan(InlineSpan span, double scale) {
    if (scale == 1 || span is! TextSpan) {
      return span;
    }
    final style = span.style;
    final fontSize = style?.fontSize;
    return TextSpan(
      text: span.text,
      children: span.children
          ?.map((child) => _scaleInlineSpan(child, scale))
          .toList(growable: false),
      style: fontSize == null
          ? style
          : style?.copyWith(fontSize: fontSize * scale),
      recognizer: span.recognizer,
      mouseCursor: span.mouseCursor,
      onEnter: span.onEnter,
      onExit: span.onExit,
      semanticsLabel: span.semanticsLabel,
      semanticsIdentifier: span.semanticsIdentifier,
      locale: span.locale,
      spellOut: span.spellOut,
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
    animation: _animation,
    builder: (context, _) {
      final viewport = MediaQuery.sizeOf(context);
      final targetPlayerRect = _targetPlayerRect(viewport);
      final targetPlayerBottom = targetPlayerRect.bottom;
      final profileFrom = _profileFromPlayerBottom;
      final playerBottom = profileFrom == null
          ? targetPlayerBottom
          : lerpDouble(
              profileFrom,
              targetPlayerBottom,
              Curves.easeInOutCubic.transform(_profileController.value),
            )!;
      final progress = Curves.easeOutCubic.transform(
        widget.controller._routeProgress,
      );
      final revealOpacity =
          1 -
          Curves.easeInOutCubic.transform(
            _revealController.value,
          );
      final profileOffset = playerBottom - targetPlayerBottom;
      final morphRect = Rect.lerp(
        widget.controller.transitionToken.launchRect,
        Offset.zero & viewport,
        progress,
      )!;
      final borderRadius = BorderRadius.lerp(
        widget.controller.transitionToken.launchBorderRadius,
        BorderRadius.zero,
        progress,
      )!;
      final mediaRect = Rect.lerp(
        widget.controller.transitionToken.mediaLaunchRect,
        Rect.fromLTRB(
          0,
          targetPlayerRect.top,
          viewport.width,
          playerBottom,
        ),
        progress,
      )!;
      final localMediaRect = mediaRect.shift(-morphRect.topLeft);
      final mediaBorderRadius = BorderRadius.lerp(
        widget.controller.transitionToken.mediaLaunchBorderRadius,
        BorderRadius.zero,
        progress,
      )!;
      final targetColorScheme = Pref.darkVideoPage
          ? ThemeUtils.darkTheme.colorScheme
          : Theme.of(context).colorScheme;
      final surfaceColor = targetColorScheme.surface;
      final token = widget.controller.transitionToken;
      final sourceSurfaceOpacity =
          token.sourceLayout == VideoTransitionSourceLayout.horizontalRow
          ? 1.0
          : progress;
      final skeletonOpacity = progress * revealOpacity;
      final transitionSurfaceColor = Color.lerp(
        token.sourceSurfaceColor,
        surfaceColor,
        progress,
      )!.withValues(alpha: sourceSurfaceOpacity * revealOpacity);
      final sceneClipRect = Rect.lerp(
        token.sourceVisibleRect,
        Offset.zero & viewport,
        progress,
      )!;

      return ClipRect(
        clipper: _AbsoluteRectClipper(sceneClipRect),
        clipBehavior: Clip.hardEdge,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (widget.controller._hasRouteAnimation)
              Positioned.fromRect(
                rect: morphRect,
                child: IgnorePointer(
                  child: ClipRRect(
                    borderRadius: borderRadius,
                    child: CustomPaint(
                      painter: _VideoDetailMorphSurfacePainter(
                        color: transitionSurfaceColor,
                        mediaRect: localMediaRect,
                        mediaBorderRadius: mediaBorderRadius,
                        playerTopSurfaceOpacity: skeletonOpacity,
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Transform.translate(
                            offset: Offset(0, profileOffset),
                            child: VideoDetailHeroShell(
                              playerSurfaceOpacity: 0,
                              navigationSurfaceOpacity: skeletonOpacity,
                              detailSurfaceOpacity: skeletonOpacity,
                              recommendationSurfaceOpacity: skeletonOpacity,
                              isVertical: widget.controller._isVertical,
                              playerBottomOverride:
                                  localMediaRect.bottom - profileOffset,
                              variant: widget.controller._variant,
                              title: widget.controller._title,
                              expandedIntro: widget.controller.expandedIntro,
                              showRecommendations:
                                  widget.controller.showRecommendations,
                              hasSeasonPanel: widget.controller._hasSeasonPanel,
                              hasPagesPanel: widget.controller._hasPagesPanel,
                              tabCount: widget.controller._tabCount,
                              actionCount: widget.controller._actionCount,
                              hasEpisodePanel:
                                  widget.controller._hasEpisodePanel,
                              ugcTitleHeightOverride:
                                  widget.controller._variant ==
                                      VideoDetailSkeletonVariant.ugc
                                  ? _cachedUgcTitleHeight(context, viewport)
                                  : null,
                            ),
                          ),
                          _buildMorphingTitle(
                            morphRect: morphRect,
                            viewport: viewport,
                            playerBottom: playerBottom,
                            progress: progress,
                            revealOpacity: revealOpacity,
                          ),
                        ],
                      ),
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
        ),
      );
    },
  );
}

class _AbsoluteRectClipper extends CustomClipper<Rect> {
  const _AbsoluteRectClipper(this.rect);

  final Rect rect;

  @override
  Rect getClip(Size size) => rect.intersect(Offset.zero & size);

  @override
  bool shouldReclip(covariant _AbsoluteRectClipper oldClipper) =>
      rect != oldClipper.rect;
}

class _VideoDetailMorphSurfacePainter extends CustomPainter {
  const _VideoDetailMorphSurfacePainter({
    required this.color,
    required this.mediaRect,
    required this.mediaBorderRadius,
    required this.playerTopSurfaceOpacity,
  });

  final Color color;
  final Rect mediaRect;
  final BorderRadius mediaBorderRadius;
  final double playerTopSurfaceOpacity;

  @override
  void paint(Canvas canvas, Size size) {
    final surfacePath = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(mediaBorderRadius.toRRect(mediaRect));
    canvas.drawPath(surfacePath, Paint()..color = color);
    final playerTop = mediaRect.top.clamp(0.0, size.height).toDouble();
    if (playerTopSurfaceOpacity > 0 && playerTop > 0) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, playerTop),
        Paint()
          ..color = Colors.black.withValues(alpha: playerTopSurfaceOpacity),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _VideoDetailMorphSurfacePainter oldDelegate) =>
      color != oldDelegate.color ||
      mediaRect != oldDelegate.mediaRect ||
      mediaBorderRadius != oldDelegate.mediaBorderRadius ||
      playerTopSurfaceOpacity != oldDelegate.playerTopSurfaceOpacity;
}
