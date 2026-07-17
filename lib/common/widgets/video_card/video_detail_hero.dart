import 'dart:math' as math;

import 'package:PiliMax/common/style.dart';
import 'package:PiliMax/common/widgets/video_card/video_card_h_layout_metrics.dart';
import 'package:PiliMax/common/widgets/video_card/video_transition_registry.dart';
import 'package:PiliMax/pages/video/video_layout_metrics.dart';
import 'package:PiliMax/utils/grid.dart';
import 'package:PiliMax/utils/storage_pref.dart';
import 'package:PiliMax/utils/theme_utils.dart';

import 'package:flutter/material.dart';

export 'package:PiliMax/common/widgets/video_card/video_transition_registry.dart'
    show VideoTransitionSourceLayout;

/// Registers the whole card as the predictive-back return target.
///
/// A descendant [VideoDetailHero.source] owns the independent media Hero.
class VideoDetailTransitionSource extends StatefulWidget {
  const VideoDetailTransitionSource({
    super.key,
    required this.tag,
    required this.child,
    this.borderRadius = Style.mdRadius,
    this.layout = VideoTransitionSourceLayout.verticalCard,
  });

  final Object tag;
  final Widget child;
  final BorderRadiusGeometry borderRadius;
  final VideoTransitionSourceLayout layout;

  @override
  State<VideoDetailTransitionSource> createState() =>
      _VideoDetailTransitionSourceState();
}

class _VideoDetailTransitionSourceState
    extends State<VideoDetailTransitionSource> {
  final GlobalKey _sourceBoundaryKey = GlobalKey();
  VideoTransitionRegistration? _registration;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _registration ??= _registerSource();
  }

  @override
  void didUpdateWidget(VideoDetailTransitionSource oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tag != widget.tag ||
        oldWidget.borderRadius != widget.borderRadius ||
        oldWidget.layout != widget.layout) {
      _registration?.dispose();
      _registration = _registerSource();
    }
  }

  VideoTransitionRegistration _registerSource() {
    return VideoTransitionRegistry.register(
      tag: widget.tag,
      boundaryKey: _sourceBoundaryKey,
      context: context,
      borderRadius: widget.borderRadius,
      layout: widget.layout,
    );
  }

  @override
  void dispose() {
    _registration?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final registration = _registration;
    final child = KeyedSubtree(
      key: _sourceBoundaryKey,
      child: widget.child,
    );
    if (registration == null) {
      return child;
    }
    return _VideoDetailTransitionScope(
      tag: widget.tag,
      registration: registration,
      child: Listener(
        onPointerDown: (event) => registration.notePointerDown(event.position),
        child: child,
      ),
    );
  }
}

class _VideoDetailTransitionScope extends InheritedWidget {
  const _VideoDetailTransitionScope({
    required this.tag,
    required this.registration,
    required super.child,
  });

  final Object tag;
  final VideoTransitionRegistration registration;

  static _VideoDetailTransitionScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_VideoDetailTransitionScope>();

  @override
  bool updateShouldNotify(_VideoDetailTransitionScope oldWidget) =>
      tag != oldWidget.tag || !identical(registration, oldWidget.registration);
}

/// Registers a card title for the shared detail transition without scaling it.
///
/// This must be a descendant of [VideoDetailTransitionSource]. The transition
/// captures its resolved text style and geometry when navigation is claimed.
class VideoDetailTransitionTitle extends StatefulWidget {
  const VideoDetailTransitionTitle({
    super.key,
    required this.text,
    required this.child,
    this.textSpan,
    this.style,
    this.maxLines,
    this.textAlign,
    this.overflow,
  }) : assert(maxLines == null || maxLines > 0);

  final String text;
  final Widget child;
  final InlineSpan? textSpan;
  final TextStyle? style;
  final int? maxLines;
  final TextAlign? textAlign;
  final TextOverflow? overflow;

  @override
  State<VideoDetailTransitionTitle> createState() =>
      _VideoDetailTransitionTitleState();
}

class _VideoDetailTransitionTitleState
    extends State<VideoDetailTransitionTitle> {
  final GlobalKey _titleBoundaryKey = GlobalKey();
  _VideoDetailTransitionScope? _scope;

  VideoTransitionTitleDescriptor get _descriptor =>
      VideoTransitionTitleDescriptor(
        text: widget.text,
        textSpan: widget.textSpan,
        style: widget.style,
        maxLines: widget.maxLines,
        textAlign: widget.textAlign,
        overflow: widget.overflow,
      );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = _VideoDetailTransitionScope.maybeOf(context);
    assert(
      scope != null,
      'VideoDetailTransitionTitle must be inside '
      'VideoDetailTransitionSource.',
    );
    if (!identical(scope?.registration, _scope?.registration)) {
      _scope?.registration.detachTitle(_titleBoundaryKey);
      _scope = scope;
    }
    scope?.registration.attachTitle(_titleBoundaryKey, _descriptor);
  }

  @override
  void didUpdateWidget(VideoDetailTransitionTitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scope?.registration.attachTitle(_titleBoundaryKey, _descriptor);
  }

  @override
  void dispose() {
    _scope?.registration.detachTitle(_titleBoundaryKey);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => KeyedSubtree(
    key: _titleBoundaryKey,
    child: widget.child,
  );
}

/// A decoration painted above a [VideoDetailHero] flight.
///
/// Unlike [VideoDetailHero.flightChild], this child is positioned directly in
/// the Hero's current bounds and is never scaled with the media surface. A
/// single anchor keeps the child's logical-pixel size; supplying both opposing
/// anchors stretches it across that axis, which is useful for progress bars or
/// full-surface decorations. An omitted axis defaults to the leading edge.
@immutable
class VideoDetailHeroFlightOverlay {
  const VideoDetailHeroFlightOverlay({
    required this.child,
    this.top,
    this.right,
    this.bottom,
    this.left,
    this.fadeFraction = 1 / 9,
  }) : assert(fadeFraction > 0 && fadeFraction <= 1);

  final Widget child;
  final double? top;
  final double? right;
  final double? bottom;
  final double? left;

  /// Portion of the uncurved route/gesture timeline reserved for fading this
  /// decoration.
  ///
  /// On push it fades out during the first fraction. On pop it fades in during
  /// the final fraction, immediately before the source card is restored.
  final double fadeFraction;
}

/// Moves a frozen video media surface into the detail player's rectangle.
///
/// Both ends opt in to user-gesture transitions so Android predictive back can
/// drive the same flight. Keep the target child lightweight; the default
/// The flight never carries a live player or scrolling state.
class VideoDetailHero extends StatelessWidget {
  const VideoDetailHero.source({
    super.key,
    required this.child,
    required this.flightChild,
    this.flightOverlays = const <VideoDetailHeroFlightOverlay>[],
    this.borderRadius = Style.mdRadius,
  }) : tag = null,
       _isDetailTarget = false;

  const VideoDetailHero.target({
    super.key,
    required this.tag,
    this.child = const VideoDetailHeroShell(),
    this.borderRadius = BorderRadius.zero,
  }) : flightChild = null,
       flightOverlays = const <VideoDetailHeroFlightOverlay>[],
       _isDetailTarget = true;

  final Object? tag;

  /// The complete source/target content shown while no Hero flight is active.
  final Widget child;

  /// A decoration-free media surface used only by a source Hero flight.
  ///
  /// The target constructor stores `null`; the internal fallback to [child]
  /// remains available for framework-created or defensive fallback children.
  final Widget? flightChild;

  /// Unscaled decorations painted above [flightChild] during the flight.
  final List<VideoDetailHeroFlightOverlay> flightOverlays;
  final BorderRadiusGeometry borderRadius;
  final bool _isDetailTarget;

  static Tween<Rect?> _createRectTween(Rect? begin, Rect? end) =>
      RectTween(begin: begin, end: end);

  static Widget _flightShuttleBuilder(
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection flightDirection,
    BuildContext fromHeroContext,
    BuildContext toHeroContext,
  ) {
    final fromHero = fromHeroContext.widget as Hero;
    final toHero = toHeroContext.widget as Hero;
    final fromChild = _heroChild(fromHero.child);
    final toChild = _heroChild(toHero.child);
    final sourceChild = fromChild.isDetailTarget ? toChild : fromChild;
    final sourceContext = fromChild.isDetailTarget
        ? toHeroContext
        : fromHeroContext;
    final sourceSize = _contextSize(sourceContext);
    final isPop = flightDirection == HeroFlightDirection.pop;
    final sourceVisibleRect = _sourceVisibleRect(
      sourceContext,
      sourceChild.registration,
    );

    final sourceFlightChild = _FixedSizeFlightChild(
      layoutSize: sourceSize,
      child: sourceChild.flightChild ?? sourceChild.child,
    );
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final flightProgress = switch (flightDirection) {
          HeroFlightDirection.push => animation.value,
          HeroFlightDirection.pop => 1 - animation.value,
        };
        final radius =
            BorderRadiusGeometry.lerp(
              isPop ? BorderRadius.zero : sourceChild.borderRadius,
              isPop ? sourceChild.borderRadius : BorderRadius.zero,
              flightProgress,
            ) ??
            BorderRadius.zero;
        final visibleRect = Rect.lerp(
          isPop ? const Rect.fromLTWH(0, 0, 1, 1) : sourceVisibleRect,
          isPop ? sourceVisibleRect : const Rect.fromLTWH(0, 0, 1, 1),
          flightProgress,
        )!;

        final flightBody = sourceChild.flightOverlays.isEmpty
            ? sourceFlightChild
            : Stack(
                fit: StackFit.expand,
                clipBehavior: Clip.none,
                children: <Widget>[
                  sourceFlightChild,
                  for (final overlay in sourceChild.flightOverlays)
                    _buildFlightOverlay(
                      overlay,
                      flightProgress: flightProgress,
                      isPop: isPop,
                    ),
                ],
              );

        return RepaintBoundary(
          child: ClipRect(
            clipper: _NormalizedRectClipper(visibleRect),
            clipBehavior: Clip.hardEdge,
            child: ClipRRect(
              borderRadius: radius,
              clipBehavior: Clip.antiAlias,
              child: flightBody,
            ),
          ),
        );
      },
    );
  }

  static _VideoDetailHeroChild _heroChild(Widget child) {
    if (child case final _VideoDetailHeroChild heroChild) {
      return heroChild;
    }
    return _VideoDetailHeroChild(
      borderRadius: BorderRadius.zero,
      isDetailTarget: false,
      registration: null,
      child: child,
    );
  }

  static Widget _buildFlightOverlay(
    VideoDetailHeroFlightOverlay overlay, {
    required double flightProgress,
    required bool isPop,
  }) {
    final opacity = _flightOverlayOpacity(
      overlay,
      flightProgress: flightProgress,
      isPop: isPop,
    );
    return Positioned(
      top: overlay.top ?? (overlay.bottom == null ? 0.0 : null),
      right: overlay.right,
      bottom: overlay.bottom,
      left: overlay.left ?? (overlay.right == null ? 0.0 : null),
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: Opacity(opacity: opacity, child: overlay.child),
        ),
      ),
    );
  }

  static double _flightOverlayOpacity(
    VideoDetailHeroFlightOverlay overlay, {
    required double flightProgress,
    required bool isPop,
  }) {
    final fraction = overlay.fadeFraction;
    final rawProgress = _rawFlightProgress(
      flightProgress,
      isPop: isPop,
    );
    if (!isPop) {
      if (rawProgress <= 0) {
        return 1;
      }
      if (rawProgress >= fraction) {
        return 0;
      }
      return 1 - Curves.ease.transform(rawProgress / fraction);
    }

    final fadeStart = 1 - fraction;
    if (rawProgress <= fadeStart) {
      return 0;
    }
    if (rawProgress >= 1) {
      return 1;
    }
    return Curves.ease.transform(
      (rawProgress - fadeStart) / fraction,
    );
  }

  static double _rawFlightProgress(
    double flightProgress, {
    required bool isPop,
  }) {
    final easedProgress = flightProgress.clamp(0.0, 1.0).toDouble();
    if (isPop) {
      // The reversed easeOutCubic flight reaches the source as easeInCubic.
      return math.pow(easedProgress, 1 / 3).toDouble();
    }
    // Inverse of easeOutCubic: f(t) = 1 - (1 - t)^3.
    return 1 - math.pow(1 - easedProgress, 1 / 3).toDouble();
  }

  static Size _contextSize(BuildContext context) {
    final renderObject = context.findRenderObject();
    if (renderObject is RenderBox && renderObject.hasSize) {
      return renderObject.size;
    }
    return Size.zero;
  }

  static Rect _sourceVisibleRect(
    BuildContext sourceContext,
    VideoTransitionRegistration? registration,
  ) {
    final renderObject = sourceContext.findRenderObject();
    final cardVisibleRect = registration?.currentVisibleRect();
    if (renderObject is! RenderBox ||
        !renderObject.hasSize ||
        renderObject.size.isEmpty ||
        cardVisibleRect == null) {
      return const Rect.fromLTWH(0, 0, 1, 1);
    }
    final mediaRect =
        renderObject.localToGlobal(Offset.zero) & renderObject.size;
    final intersection = mediaRect.intersect(cardVisibleRect);
    if (intersection.isEmpty) {
      if (cardVisibleRect.top >= mediaRect.bottom) {
        return const Rect.fromLTRB(0, 1, 1, 1);
      }
      if (cardVisibleRect.bottom <= mediaRect.top) {
        return const Rect.fromLTRB(0, 0, 1, 0);
      }
      if (cardVisibleRect.left >= mediaRect.right) {
        return const Rect.fromLTRB(1, 0, 1, 1);
      }
      if (cardVisibleRect.right <= mediaRect.left) {
        return const Rect.fromLTRB(0, 0, 0, 1);
      }
      return Rect.zero;
    }
    return Rect.fromLTRB(
      ((intersection.left - mediaRect.left) / mediaRect.width).clamp(0.0, 1.0),
      ((intersection.top - mediaRect.top) / mediaRect.height).clamp(0.0, 1.0),
      ((intersection.right - mediaRect.left) / mediaRect.width).clamp(0.0, 1.0),
      ((intersection.bottom - mediaRect.top) / mediaRect.height).clamp(
        0.0,
        1.0,
      ),
    );
  }

  static Widget _buildPlaceholder(
    BuildContext context,
    Size heroSize,
    Widget child,
  ) {
    return SizedBox.fromSize(size: heroSize);
  }

  @override
  Widget build(BuildContext context) {
    if (!_isDetailTarget) {
      return _VideoDetailMediaHeroSource(
        borderRadius: borderRadius,
        flightChild: flightChild,
        flightOverlays: flightOverlays,
        child: child,
      );
    }
    return _buildHero(
      rawTag: tag!,
      borderRadius: borderRadius,
      isDetailTarget: true,
      child: child,
    );
  }

  static Widget _buildHero({
    Key? key,
    required Object rawTag,
    required BorderRadiusGeometry borderRadius,
    required bool isDetailTarget,
    VideoTransitionRegistration? registration,
    required Widget child,
    Widget? flightChild,
    List<VideoDetailHeroFlightOverlay> flightOverlays =
        const <VideoDetailHeroFlightOverlay>[],
  }) {
    return Hero(
      key: key,
      tag: _VideoDetailMediaHeroTag(rawTag),
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeOutCubic,
      createRectTween: VideoDetailHero._createRectTween,
      flightShuttleBuilder: VideoDetailHero._flightShuttleBuilder,
      transitionOnUserGestures: true,
      placeholderBuilder: VideoDetailHero._buildPlaceholder,
      child: _VideoDetailHeroChild(
        borderRadius: borderRadius,
        isDetailTarget: isDetailTarget,
        registration: registration,
        flightChild: flightChild,
        flightOverlays: flightOverlays,
        child: child,
      ),
    );
  }
}

class _VideoDetailMediaHeroSource extends StatefulWidget {
  const _VideoDetailMediaHeroSource({
    required this.borderRadius,
    required this.child,
    required this.flightChild,
    required this.flightOverlays,
  });

  final BorderRadiusGeometry borderRadius;
  final Widget child;
  final Widget? flightChild;
  final List<VideoDetailHeroFlightOverlay> flightOverlays;

  @override
  State<_VideoDetailMediaHeroSource> createState() =>
      _VideoDetailMediaHeroSourceState();
}

class _VideoDetailMediaHeroSourceState
    extends State<_VideoDetailMediaHeroSource> {
  final GlobalKey _mediaBoundaryKey = GlobalKey();
  _VideoDetailTransitionScope? _scope;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = _VideoDetailTransitionScope.maybeOf(context);
    assert(
      scope != null,
      'VideoDetailHero.source must be inside VideoDetailTransitionSource.',
    );
    if (identical(scope?.registration, _scope?.registration)) {
      _scope = scope;
      return;
    }
    _scope?.registration.detachMedia(_mediaBoundaryKey);
    _scope = scope;
    scope?.registration.attachMedia(_mediaBoundaryKey, widget.borderRadius);
  }

  @override
  void didUpdateWidget(_VideoDetailMediaHeroSource oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.borderRadius != widget.borderRadius) {
      _scope?.registration.attachMedia(
        _mediaBoundaryKey,
        widget.borderRadius,
      );
    }
  }

  @override
  void dispose() {
    _scope?.registration.detachMedia(_mediaBoundaryKey);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = _scope;
    if (scope == null) {
      return widget.child;
    }
    return VideoDetailHero._buildHero(
      key: _mediaBoundaryKey,
      rawTag: scope.tag,
      borderRadius: widget.borderRadius,
      isDetailTarget: false,
      registration: scope.registration,
      child: widget.child,
      flightChild: widget.flightChild,
      flightOverlays: widget.flightOverlays,
    );
  }
}

final class _VideoDetailMediaHeroTag {
  const _VideoDetailMediaHeroTag(this.rawTag);

  final Object rawTag;

  @override
  bool operator ==(Object other) =>
      other is _VideoDetailMediaHeroTag && other.rawTag == rawTag;

  @override
  int get hashCode => Object.hash(_VideoDetailMediaHeroTag, rawTag);
}

/// A paint-only placeholder for the video detail page during a Hero flight.
///
/// It uses canvas coordinates instead of Flex widgets, so intermediate Hero
/// sizes cannot cause text reflow or overflow. The player area is only a
/// surface slot; no live video widget is moved into the Navigator overlay.
class VideoDetailHeroShell extends StatelessWidget {
  const VideoDetailHeroShell({
    super.key,
    this.playerSurfaceOpacity = 1,
    this.navigationSurfaceOpacity = 1,
    this.detailSurfaceOpacity = 1,
    this.recommendationSurfaceOpacity = 1,
    this.recommendationCount = 4,
    this.isVertical,
    this.playerBottomOverride,
    this.variant = VideoDetailSkeletonVariant.ugc,
    this.title,
    this.expandedIntro = false,
    this.showRecommendations = true,
    this.hasSeasonPanel = false,
    this.hasPagesPanel = false,
    this.tabCount = VideoDetailLayoutMetrics.defaultTabCount,
    this.actionCount = VideoDetailLayoutMetrics.ugcActionCount,
    this.hasEpisodePanel = false,
    this.ugcTitleHeightOverride,
  }) : assert(playerSurfaceOpacity >= 0 && playerSurfaceOpacity <= 1),
       assert(
         navigationSurfaceOpacity >= 0 && navigationSurfaceOpacity <= 1,
       ),
       assert(detailSurfaceOpacity >= 0 && detailSurfaceOpacity <= 1),
       assert(
         recommendationSurfaceOpacity >= 0 && recommendationSurfaceOpacity <= 1,
       ),
       assert(recommendationCount >= 0),
       assert(tabCount > 0),
       assert(actionCount >= 0);

  factory VideoDetailHeroShell.revealing({
    Key? key,
    required double progress,
    int recommendationCount = 4,
    bool? isVertical,
    double? playerBottomOverride,
    VideoDetailSkeletonVariant variant = VideoDetailSkeletonVariant.ugc,
    String? title,
    bool expandedIntro = false,
    bool showRecommendations = true,
    bool hasSeasonPanel = false,
    bool hasPagesPanel = false,
    int tabCount = VideoDetailLayoutMetrics.defaultTabCount,
    int actionCount = VideoDetailLayoutMetrics.ugcActionCount,
    bool hasEpisodePanel = false,
    double? ugcTitleHeightOverride,
  }) => VideoDetailHeroShell(
    key: key,
    playerSurfaceOpacity: _remaining(progress, 0.04, 0.34),
    navigationSurfaceOpacity: _remaining(progress, 0.12, 0.44),
    detailSurfaceOpacity: _remaining(progress, 0.28, 0.76),
    recommendationSurfaceOpacity: _remaining(progress, 0.56, 1),
    recommendationCount: recommendationCount,
    isVertical: isVertical,
    playerBottomOverride: playerBottomOverride,
    variant: variant,
    title: title,
    expandedIntro: expandedIntro,
    showRecommendations: showRecommendations,
    hasSeasonPanel: hasSeasonPanel,
    hasPagesPanel: hasPagesPanel,
    tabCount: tabCount,
    actionCount: actionCount,
    hasEpisodePanel: hasEpisodePanel,
    ugcTitleHeightOverride: ugcTitleHeightOverride,
  );

  final double playerSurfaceOpacity;
  final double navigationSurfaceOpacity;
  final double detailSurfaceOpacity;
  final double recommendationSurfaceOpacity;
  final int recommendationCount;
  final bool? isVertical;
  final double? playerBottomOverride;
  final VideoDetailSkeletonVariant variant;
  final String? title;
  final bool expandedIntro;
  final bool showRecommendations;
  final bool hasSeasonPanel;
  final bool hasPagesPanel;
  final int tabCount;
  final int actionCount;
  final bool hasEpisodePanel;
  final double? ugcTitleHeightOverride;

  static double _remaining(double progress, double begin, double end) {
    if (progress <= begin) {
      return 1;
    }
    if (progress >= end) {
      return 0;
    }
    final normalized = (progress - begin) / (end - begin);
    return 1 - Curves.easeInOutCubic.transform(normalized);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Pref.darkVideoPage
        ? ThemeUtils.darkTheme.colorScheme
        : Theme.of(context).colorScheme;
    final mediaSize = MediaQuery.sizeOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : mediaSize.width;
        final height = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : mediaSize.height;
        return SizedBox(
          width: width,
          height: height,
          child: CustomPaint(
            painter: _VideoDetailSkeletonPainter(
              colorScheme: colorScheme,
              playerSurfaceOpacity: playerSurfaceOpacity,
              navigationSurfaceOpacity: navigationSurfaceOpacity,
              detailSurfaceOpacity: detailSurfaceOpacity,
              recommendationSurfaceOpacity: recommendationSurfaceOpacity,
              recommendationCount: recommendationCount,
              isVertical: isVertical,
              playerBottomOverride: playerBottomOverride,
              topInset: Pref.removeSafeArea
                  ? 0
                  : MediaQuery.viewPaddingOf(context).top,
              variant: variant,
              title: title,
              expandedIntro: expandedIntro,
              showRecommendations: showRecommendations,
              hasSeasonPanel: hasSeasonPanel,
              hasPagesPanel: hasPagesPanel,
              tabCount: tabCount,
              actionCount: actionCount,
              hasEpisodePanel: hasEpisodePanel,
              ugcTitleHeightOverride: ugcTitleHeightOverride,
              textScaler: MediaQuery.textScalerOf(context),
              titleStyle: DefaultTextStyle.of(
                context,
              ).style.copyWith(fontSize: 16),
            ),
          ),
        );
      },
    );
  }
}

class _VideoDetailHeroChild extends StatelessWidget {
  const _VideoDetailHeroChild({
    required this.borderRadius,
    required this.isDetailTarget,
    required this.registration,
    required this.child,
    this.flightChild,
    this.flightOverlays = const <VideoDetailHeroFlightOverlay>[],
  });

  final BorderRadiusGeometry borderRadius;
  final bool isDetailTarget;
  final VideoTransitionRegistration? registration;
  final Widget child;
  final Widget? flightChild;
  final List<VideoDetailHeroFlightOverlay> flightOverlays;

  @override
  Widget build(BuildContext context) => child;
}

class _NormalizedRectClipper extends CustomClipper<Rect> {
  const _NormalizedRectClipper(this.rect);

  final Rect rect;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(
    rect.left * size.width,
    rect.top * size.height,
    rect.right * size.width,
    rect.bottom * size.height,
  );

  @override
  bool shouldReclip(covariant _NormalizedRectClipper oldClipper) =>
      rect != oldClipper.rect;
}

class _FixedSizeFlightChild extends StatelessWidget {
  const _FixedSizeFlightChild({
    required this.layoutSize,
    required this.child,
  });

  final Size layoutSize;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fallbackSize = constraints.biggest;
        final effectiveSize = layoutSize.isEmpty ? fallbackSize : layoutSize;
        return SizedBox(
          width: constraints.hasBoundedWidth ? constraints.maxWidth : null,
          height: constraints.hasBoundedHeight ? constraints.maxHeight : null,
          child: FittedBox(
            fit: BoxFit.cover,
            alignment: Alignment.center,
            child: SizedBox.fromSize(size: effectiveSize, child: child),
          ),
        );
      },
    );
  }
}

class _VideoDetailSkeletonPainter extends CustomPainter {
  const _VideoDetailSkeletonPainter({
    required this.colorScheme,
    required this.playerSurfaceOpacity,
    required this.navigationSurfaceOpacity,
    required this.detailSurfaceOpacity,
    required this.recommendationSurfaceOpacity,
    required this.recommendationCount,
    required this.isVertical,
    required this.playerBottomOverride,
    required this.topInset,
    required this.variant,
    required this.title,
    required this.expandedIntro,
    required this.showRecommendations,
    required this.hasSeasonPanel,
    required this.hasPagesPanel,
    required this.tabCount,
    required this.actionCount,
    required this.hasEpisodePanel,
    required this.ugcTitleHeightOverride,
    required this.textScaler,
    required this.titleStyle,
  });

  final ColorScheme colorScheme;
  final double playerSurfaceOpacity;
  final double navigationSurfaceOpacity;
  final double detailSurfaceOpacity;
  final double recommendationSurfaceOpacity;
  final int recommendationCount;
  final bool? isVertical;
  final double? playerBottomOverride;
  final double topInset;
  final VideoDetailSkeletonVariant variant;
  final String? title;
  final bool expandedIntro;
  final bool showRecommendations;
  final bool hasSeasonPanel;
  final bool hasPagesPanel;
  final int tabCount;
  final int actionCount;
  final bool hasEpisodePanel;
  final double? ugcTitleHeightOverride;
  final TextScaler textScaler;
  final TextStyle titleStyle;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }

    canvas
      ..save()
      ..clipRect(Offset.zero & size);

    final playerBottom =
        (playerBottomOverride ??
                VideoDetailLayoutMetrics.entryPlayerBottom(
                  size,
                  isVertical: isVertical,
                  topInset: topInset,
                ))
            .clamp(0.0, size.height)
            .toDouble();
    final playerRect = Rect.fromLTRB(0, 0, size.width, playerBottom);
    if (playerSurfaceOpacity > 0) {
      canvas.drawRect(
        playerRect,
        Paint()..color = Colors.black.withValues(alpha: playerSurfaceOpacity),
      );
    }

    final navigationBottom = math.min(
      size.height,
      playerBottom + VideoDetailLayoutMetrics.tabBarHeight,
    );
    _paintNavigation(
      canvas,
      Rect.fromLTRB(0, playerBottom, size.width, navigationBottom),
    );

    switch (variant) {
      case VideoDetailSkeletonVariant.ugc:
        _paintUgcBody(canvas, size, navigationBottom);
        break;
      case VideoDetailSkeletonVariant.pgc:
        _paintPgcBody(canvas, size, navigationBottom, showActions: true);
        break;
      case VideoDetailSkeletonVariant.pugv:
        _paintPgcBody(canvas, size, navigationBottom, showActions: false);
        break;
      case VideoDetailSkeletonVariant.local:
        _paintLocalBody(canvas, size, navigationBottom);
        break;
    }

    canvas.restore();
  }

  void _paintNavigation(Canvas canvas, Rect rect) {
    _paintSection(canvas, rect, navigationSurfaceOpacity, () {
      final primaryPaint = _skeletonPaint(navigationSurfaceOpacity);
      final subtlePaint = _subtlePaint(navigationSurfaceOpacity);
      final centerY = rect.top + rect.height / 2;
      final tabFlex = VideoDetailLayoutMetrics.navigationTabRegionFlex(
        tabCount,
      );
      final tabRegionWidth =
          rect.width *
          tabFlex /
          (tabFlex + VideoDetailLayoutMetrics.navigationActionRegionFlex);
      final tabWidth = tabRegionWidth / tabCount;
      for (var index = 0; index < tabCount; index++) {
        final barWidth = math.min(index == 0 ? 42.0 : 48.0, tabWidth * 0.62);
        _drawBar(
          canvas,
          Rect.fromCenter(
            center: Offset(tabWidth * (index + 0.5), centerY),
            width: barWidth,
            height: index == 0 ? 10 : 8,
          ),
          index == 0 ? primaryPaint : subtlePaint,
        );
      }
      final controlsRight =
          rect.right - VideoDetailLayoutMetrics.navigationRightPadding;
      final toggleLeft =
          controlsRight -
          VideoDetailLayoutMetrics.navigationDanmakuToggleExtent;
      final sendLeft =
          toggleLeft - VideoDetailLayoutMetrics.navigationSendDanmakuWidth;
      _drawBar(
        canvas,
        Rect.fromCenter(
          center: Offset(
            sendLeft + VideoDetailLayoutMetrics.navigationSendDanmakuWidth / 2,
            centerY,
          ),
          width: 52,
          height: 8,
        ),
        subtlePaint,
      );
      canvas
        ..drawCircle(
          Offset(
            toggleLeft +
                VideoDetailLayoutMetrics.navigationDanmakuToggleExtent / 2,
            centerY,
          ),
          9,
          primaryPaint,
        )
        ..drawRect(
          Rect.fromCenter(
            center: Offset(tabWidth / 2, rect.bottom - 1),
            width: math.min(42, tabWidth * 0.62),
            height: 2,
          ),
          Paint()
            ..color = colorScheme.primary.withValues(
              alpha: 0.52 * navigationSurfaceOpacity,
            ),
        )
        ..drawRect(
          Rect.fromLTWH(0, rect.bottom - 1, rect.width, 1),
          Paint()
            ..color = colorScheme.outline.withValues(
              alpha: 0.1 * navigationSurfaceOpacity,
            ),
        );
    });
  }

  void _paintUgcBody(Canvas canvas, Size size, double top) {
    const padding = VideoDetailLayoutMetrics.horizontalPadding;
    const gap = VideoDetailLayoutMetrics.sectionGap;
    final ownerTop = top + VideoDetailLayoutMetrics.introTopPadding;
    final ownerBottom = ownerTop + VideoDetailLayoutMetrics.ownerHeight;
    final titleTop = ownerBottom + gap;
    final secondTitleTop = titleTop + 20;
    final titleHeight = _ugcTitleHeight(size);
    final statsTop = titleTop + titleHeight + gap;
    final descriptionTop = statsTop + 18 + gap;
    final actionTop = descriptionTop + (expandedIntro ? 72 : 0);
    final actionBottom = actionTop + VideoDetailLayoutMetrics.actionHeight;
    final panelHeight =
        (hasSeasonPanel ? VideoDetailLayoutMetrics.seasonPanelHeight : 0.0) +
        (hasPagesPanel ? VideoDetailLayoutMetrics.pagesPanelHeight : 0.0);
    final recommendationTop =
        actionBottom +
        panelHeight +
        VideoDetailLayoutMetrics.relatedDividerTopPadding;

    _paintSection(
      canvas,
      _sectionRect(
        size,
        top,
        showRecommendations ? recommendationTop : size.height,
      ),
      detailSurfaceOpacity,
      () {
        final primaryPaint = _skeletonPaint(detailSurfaceOpacity);
        final subtlePaint = _subtlePaint(detailSurfaceOpacity);
        const avatarDiameter = VideoDetailLayoutMetrics.ownerHeight;
        canvas.drawCircle(
          Offset(
            padding + avatarDiameter / 2,
            ownerTop + avatarDiameter / 2,
          ),
          avatarDiameter / 2,
          primaryPaint,
        );

        final followWidth = math.min(72.0, size.width * 0.2);
        final followRect = Rect.fromLTWH(
          size.width - padding - followWidth,
          ownerTop + 3,
          followWidth,
          29,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(followRect, const Radius.circular(6)),
          Paint()
            ..color = colorScheme.secondaryContainer.withValues(
              alpha: 0.72 * detailSurfaceOpacity,
            ),
        );

        const authorX = padding + avatarDiameter + 10;
        final authorWidth = math.max(0.0, followRect.left - authorX - 10);
        _drawBar(
          canvas,
          Rect.fromLTWH(authorX, ownerTop + 5, authorWidth * 0.58, 10),
          primaryPaint,
        );
        _drawBar(
          canvas,
          Rect.fromLTWH(authorX, ownerTop + 23, authorWidth * 0.78, 8),
          subtlePaint,
        );

        final contentWidth = math.max(0.0, size.width - 2 * padding);
        _drawBar(
          canvas,
          Rect.fromLTWH(padding, titleTop, contentWidth * 0.92, 14),
          primaryPaint,
        );
        if (titleHeight > 24) {
          _drawBar(
            canvas,
            Rect.fromLTWH(padding, secondTitleTop, contentWidth * 0.64, 10),
            subtlePaint,
          );
        }
        _paintStats(canvas, padding, statsTop, subtlePaint);
        if (expandedIntro) {
          _drawBar(
            canvas,
            Rect.fromLTWH(padding, descriptionTop, contentWidth * 0.22, 9),
            subtlePaint,
          );
          _drawBar(
            canvas,
            Rect.fromLTWH(
              padding,
              descriptionTop + 20,
              contentWidth * 0.94,
              9,
            ),
            subtlePaint,
          );
          _drawBar(
            canvas,
            Rect.fromLTWH(
              padding,
              descriptionTop + 39,
              contentWidth * 0.72,
              9,
            ),
            subtlePaint,
          );
        }
        _paintActions(
          canvas,
          Rect.fromLTWH(
            padding,
            actionTop,
            contentWidth,
            VideoDetailLayoutMetrics.actionHeight,
          ),
          detailSurfaceOpacity,
        );
        _paintUgcPanels(
          canvas,
          Rect.fromLTWH(padding, actionBottom, contentWidth, panelHeight),
          detailSurfaceOpacity,
        );
      },
    );

    if (showRecommendations) {
      _paintRecommendations(canvas, size, recommendationTop);
    }
  }

  void _paintPgcBody(
    Canvas canvas,
    Size size,
    double top, {
    required bool showActions,
  }) {
    const padding = VideoDetailLayoutMetrics.horizontalPadding;
    final contentTop = top + VideoDetailLayoutMetrics.pgcContentTopPadding;
    final coverHeight = math.min(
      VideoDetailLayoutMetrics.pgcCoverHeight,
      math.max(0.0, size.height - contentTop),
    );
    final coverWidth = math.min(
      VideoDetailLayoutMetrics.pgcCoverWidth,
      math.max(0.0, size.width * 0.32),
    );
    final actionTop =
        contentTop + coverHeight + VideoDetailLayoutMetrics.pgcActionTopGap;
    final episodeTop = actionCount > 0
        ? actionTop + VideoDetailLayoutMetrics.actionHeight
        : actionTop;

    _paintSection(
      canvas,
      _sectionRect(size, top, episodeTop),
      detailSurfaceOpacity,
      () {
        final primaryPaint = _skeletonPaint(detailSurfaceOpacity);
        final subtlePaint = _subtlePaint(detailSurfaceOpacity);
        final coverRect = Rect.fromLTWH(
          padding,
          contentTop,
          coverWidth,
          coverHeight,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            coverRect,
            const Radius.circular(VideoDetailLayoutMetrics.pgcCoverRadius),
          ),
          _thumbnailPaint(detailSurfaceOpacity),
        );

        final infoX = coverRect.right + VideoDetailLayoutMetrics.pgcInfoGap;
        final infoWidth = math.max(0.0, size.width - padding - infoX);
        _drawBar(
          canvas,
          Rect.fromLTWH(infoX, contentTop + 3, infoWidth * 0.62, 14),
          primaryPaint,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              infoX + infoWidth * 0.7,
              contentTop,
              infoWidth * 0.3,
              30,
            ),
            const Radius.circular(8),
          ),
          Paint()
            ..color = colorScheme.secondaryContainer.withValues(
              alpha: 0.72 * detailSurfaceOpacity,
            ),
        );
        _drawBar(
          canvas,
          Rect.fromLTWH(infoX, contentTop + 35, infoWidth * 0.7, 8),
          subtlePaint,
        );
        _drawBar(
          canvas,
          Rect.fromLTWH(infoX, contentTop + 57, infoWidth * 0.86, 9),
          subtlePaint,
        );
        _drawBar(
          canvas,
          Rect.fromLTWH(infoX, contentTop + 77, infoWidth * 0.58, 9),
          subtlePaint,
        );
        _drawBar(
          canvas,
          Rect.fromLTWH(infoX, contentTop + 103, infoWidth * 0.94, 8),
          subtlePaint,
        );
        _drawBar(
          canvas,
          Rect.fromLTWH(infoX, contentTop + 120, infoWidth * 0.74, 8),
          subtlePaint,
        );
        if (showActions && actionCount > 0) {
          _paintActions(
            canvas,
            Rect.fromLTWH(
              padding,
              actionTop,
              math.max(0.0, size.width - 2 * padding),
              VideoDetailLayoutMetrics.actionHeight,
            ),
            detailSurfaceOpacity,
          );
        }
      },
    );

    if (hasEpisodePanel) {
      _paintEpisodeRows(canvas, size, episodeTop);
    }
  }

  void _paintLocalBody(Canvas canvas, Size size, double top) {
    final bodyRect = _sectionRect(size, top, size.height);
    _paintSection(canvas, bodyRect, detailSurfaceOpacity, () {
      const padding = VideoCardHLayoutMetrics.horizontalPadding;
      final primaryPaint = _skeletonPaint(detailSurfaceOpacity);
      final subtlePaint = _subtlePaint(detailSurfaceOpacity);
      var y = top + VideoDetailLayoutMetrics.localTopPadding;
      for (var index = 0; index < recommendationCount; index++) {
        if (y >= size.height) {
          break;
        }
        final thumbnailRect = Rect.fromLTWH(
          padding,
          y + VideoCardHLayoutMetrics.verticalPadding,
          VideoCardHLayoutMetrics.thumbnailWidth,
          VideoCardHLayoutMetrics.thumbnailHeight,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            thumbnailRect,
            const Radius.circular(VideoCardHLayoutMetrics.thumbnailRadius),
          ),
          _thumbnailPaint(detailSurfaceOpacity),
        );
        final textX = thumbnailRect.right + VideoCardHLayoutMetrics.contentGap;
        final textWidth = math.max(0.0, size.width - padding - textX);
        _drawBar(
          canvas,
          Rect.fromLTWH(textX, y + 12, textWidth * 0.92, 11),
          primaryPaint,
        );
        _drawBar(
          canvas,
          Rect.fromLTWH(textX, y + 34, textWidth * 0.72, 9),
          subtlePaint,
        );
        _drawBar(
          canvas,
          Rect.fromLTWH(textX, y + 82, textWidth * 0.46, 8),
          subtlePaint,
        );
        y += VideoDetailLayoutMetrics.localItemExtent;
      }
    });
  }

  void _paintUgcPanels(Canvas canvas, Rect rect, double opacity) {
    if (rect.isEmpty) {
      return;
    }
    final primaryPaint = _skeletonPaint(opacity);
    final subtlePaint = _subtlePaint(opacity);
    final tilePaint = _thumbnailPaint(opacity);
    var top = rect.top;
    if (hasSeasonPanel) {
      _drawBar(
        canvas,
        Rect.fromLTWH(rect.left, top + 8, rect.width * 0.22, 9),
        primaryPaint,
      );
      for (var index = 0; index < 3; index++) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              rect.left + index * 62,
              top + 25,
              54,
              18,
            ),
            const Radius.circular(5),
          ),
          tilePaint,
        );
      }
      top += VideoDetailLayoutMetrics.seasonPanelHeight;
    }
    if (hasPagesPanel) {
      _drawBar(
        canvas,
        Rect.fromLTWH(rect.left, top + 13, rect.width * 0.18, 9),
        primaryPaint,
      );
      _drawBar(
        canvas,
        Rect.fromLTWH(
          math.max(rect.left, rect.right - 74),
          top + 14,
          74,
          8,
        ),
        subtlePaint,
      );
      for (var index = 0; index < 4; index++) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              rect.left + index * 74,
              top + 44,
              66,
              30,
            ),
            const Radius.circular(5),
          ),
          tilePaint,
        );
      }
    }
  }

  double _ugcTitleHeight(Size size) {
    if (ugcTitleHeightOverride case final height?) {
      return height;
    }
    final value = title;
    if (value == null || value.isEmpty) {
      return 38;
    }
    final painter =
        TextPainter(
          text: TextSpan(text: value, style: titleStyle),
          maxLines: 2,
          textDirection: TextDirection.ltr,
          textScaler: textScaler,
        )..layout(
          maxWidth: math.max(
            0.0,
            size.width - 2 * VideoDetailLayoutMetrics.horizontalPadding,
          ),
        );
    final height = painter.height;
    painter.dispose();
    return height;
  }

  void _paintStats(Canvas canvas, double left, double top, Paint paint) {
    var x = left;
    for (final width in <double>[42, 48, 58]) {
      canvas.drawCircle(Offset(x + 5, top + 5), 5, paint);
      _drawBar(canvas, Rect.fromLTWH(x + 14, top + 2, width, 7), paint);
      x += width + 30;
    }
  }

  void _paintActions(
    Canvas canvas,
    Rect rect,
    double opacity,
  ) {
    if (rect.isEmpty) {
      return;
    }
    final iconPaint = _skeletonPaint(opacity);
    final labelPaint = _subtlePaint(opacity);
    if (actionCount == 0) {
      return;
    }
    final itemWidth = rect.width / actionCount;
    for (var index = 0; index < actionCount; index++) {
      final centerX = rect.left + itemWidth * (index + 0.5);
      canvas.drawCircle(
        Offset(
          centerX,
          rect.top + VideoDetailLayoutMetrics.actionIconCenterOffset,
        ),
        VideoDetailLayoutMetrics.actionIconGlyphExtent / 2,
        iconPaint,
      );
      _drawBar(
        canvas,
        Rect.fromCenter(
          center: Offset(
            centerX,
            rect.top + VideoDetailLayoutMetrics.actionLabelCenterOffset,
          ),
          width: math.min(24.0, itemWidth * 0.58),
          height: 6,
        ),
        labelPaint,
      );
    }
  }

  void _paintRecommendations(Canvas canvas, Size size, double top) {
    final sectionRect = _sectionRect(size, top, size.height);
    _paintSection(canvas, sectionRect, recommendationSurfaceOpacity, () {
      canvas.drawRect(
        Rect.fromLTWH(
          VideoDetailLayoutMetrics.horizontalPadding,
          top,
          math.max(
            0.0,
            size.width - 2 * VideoDetailLayoutMetrics.horizontalPadding,
          ),
          VideoDetailLayoutMetrics.relatedDividerHeight,
        ),
        Paint()
          ..color = colorScheme.outline.withValues(
            alpha: 0.08 * recommendationSurfaceOpacity,
          ),
      );
      final y =
          top +
          VideoDetailLayoutMetrics.relatedDividerHeight +
          VideoDetailLayoutMetrics.relatedTopPadding;
      _paintVideoCardRows(canvas, size, y);
    });
  }

  void _paintVideoCardRows(Canvas canvas, Size size, double top) {
    const padding = VideoCardHLayoutMetrics.horizontalPadding;
    final primaryPaint = _skeletonPaint(recommendationSurfaceOpacity);
    final subtlePaint = _subtlePaint(recommendationSurfaceOpacity);
    const cardHeight = VideoDetailLayoutMetrics.relatedCardHeight;
    final maxCrossAxisExtent = math.max(1.0, Grid.smallCardWidth * 2);
    final preferredCrossAxisCount = math.max(
      1,
      (size.width / maxCrossAxisExtent).ceil(),
    );
    const minimumTileWidth =
        2 * VideoCardHLayoutMetrics.horizontalPadding +
        VideoCardHLayoutMetrics.thumbnailWidth +
        VideoCardHLayoutMetrics.contentGap +
        40;
    final crossAxisCount = math.min(
      preferredCrossAxisCount,
      math.max(1, (size.width / minimumTileWidth).floor()),
    );
    final tileWidth = size.width / crossAxisCount;
    for (var index = 0; index < recommendationCount; index++) {
      final row = index ~/ crossAxisCount;
      final column = index % crossAxisCount;
      final y =
          top +
          row * (cardHeight + VideoDetailLayoutMetrics.relatedCardSpacing);
      if (y >= size.height) {
        break;
      }
      final tileLeft = column * tileWidth;
      final contentWidth = math.max(0.0, tileWidth - 2 * padding);
      final thumbnailWidth = math.min(
        VideoCardHLayoutMetrics.thumbnailWidth,
        math.max(
          0.0,
          contentWidth - VideoCardHLayoutMetrics.contentGap,
        ),
      );
      final thumbnailHeight = math.min(
        VideoCardHLayoutMetrics.thumbnailHeight,
        thumbnailWidth /
            (VideoCardHLayoutMetrics.thumbnailWidth /
                VideoCardHLayoutMetrics.thumbnailHeight),
      );
      final thumbnailRect = Rect.fromLTWH(
        tileLeft + padding,
        y + (cardHeight - thumbnailHeight) / 2,
        thumbnailWidth,
        thumbnailHeight,
      );
      final thumbnailRRect = RRect.fromRectAndRadius(
        thumbnailRect,
        const Radius.circular(VideoCardHLayoutMetrics.thumbnailRadius),
      );
      canvas
        ..drawRRect(
          thumbnailRRect,
          _thumbnailPaint(recommendationSurfaceOpacity),
        )
        ..drawRRect(
          thumbnailRRect,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = colorScheme.outline.withValues(
              alpha: 0.14 * recommendationSurfaceOpacity,
            ),
        );
      final textX = thumbnailRect.right + VideoCardHLayoutMetrics.contentGap;
      final textWidth = math.max(
        0.0,
        tileLeft + tileWidth - padding - textX,
      );
      _drawBar(
        canvas,
        Rect.fromLTWH(textX, y + 14, textWidth * 0.94, 10),
        primaryPaint,
      );
      _drawBar(
        canvas,
        Rect.fromLTWH(textX, y + 34, textWidth * 0.72, 9),
        primaryPaint,
      );
      _drawBar(
        canvas,
        Rect.fromLTWH(textX, y + 82, textWidth * 0.42, 7),
        subtlePaint,
      );
    }
  }

  void _paintEpisodeRows(Canvas canvas, Size size, double top) {
    final sectionRect = _sectionRect(size, top, size.height);
    _paintSection(canvas, sectionRect, recommendationSurfaceOpacity, () {
      const padding = VideoDetailLayoutMetrics.horizontalPadding;
      final paint = _thumbnailPaint(recommendationSurfaceOpacity);
      final subtlePaint = _subtlePaint(recommendationSurfaceOpacity);
      _drawBar(
        canvas,
        Rect.fromLTWH(
          padding,
          top + 15,
          math.min(86.0, size.width * 0.28),
          11,
        ),
        _skeletonPaint(recommendationSurfaceOpacity),
      );
      _drawBar(
        canvas,
        Rect.fromLTWH(
          math.max(padding, size.width - padding - 92),
          top + 16,
          92,
          9,
        ),
        subtlePaint,
      );
      const itemWidth = VideoDetailLayoutMetrics.episodeItemWidth;
      const itemHeight = VideoDetailLayoutMetrics.episodeItemHeight;
      const itemStride = VideoDetailLayoutMetrics.episodeItemStride;
      final y = top + VideoDetailLayoutMetrics.episodePanelHeaderHeight;
      for (var index = 0; index < recommendationCount; index++) {
        final rect = Rect.fromLTWH(
          padding + index * itemStride,
          y,
          itemWidth,
          itemHeight,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(6)),
          paint,
        );
        _drawBar(
          canvas,
          Rect.fromCenter(
            center: rect.center,
            width: rect.width * 0.54,
            height: 7,
          ),
          subtlePaint,
        );
      }
    });
  }

  void _paintSection(
    Canvas canvas,
    Rect rect,
    double opacity,
    VoidCallback paintContent,
  ) {
    if (opacity <= 0 || rect.isEmpty) {
      return;
    }
    canvas
      ..save()
      ..clipRect(rect)
      ..drawRect(
        rect,
        Paint()..color = colorScheme.surface.withValues(alpha: opacity),
      );
    paintContent();
    canvas.restore();
  }

  Rect _sectionRect(Size size, double top, double bottom) {
    final safeTop = top.clamp(0.0, size.height);
    final safeBottom = bottom.clamp(safeTop, size.height);
    return Rect.fromLTRB(0, safeTop, size.width, safeBottom);
  }

  Paint _skeletonPaint(double opacity) => Paint()
    ..color = colorScheme.onSurfaceVariant.withValues(alpha: 0.17 * opacity);

  Paint _subtlePaint(double opacity) => Paint()
    ..color = colorScheme.onSurfaceVariant.withValues(alpha: 0.11 * opacity);

  Paint _thumbnailPaint(double opacity) =>
      Paint()
        ..color = colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.92 * opacity,
        );

  static void _drawBar(Canvas canvas, Rect rect, Paint paint) {
    if (rect.width <= 0 || rect.height <= 0) {
      return;
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(rect.height / 2)),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _VideoDetailSkeletonPainter oldDelegate) {
    return colorScheme != oldDelegate.colorScheme ||
        playerSurfaceOpacity != oldDelegate.playerSurfaceOpacity ||
        navigationSurfaceOpacity != oldDelegate.navigationSurfaceOpacity ||
        detailSurfaceOpacity != oldDelegate.detailSurfaceOpacity ||
        recommendationSurfaceOpacity !=
            oldDelegate.recommendationSurfaceOpacity ||
        recommendationCount != oldDelegate.recommendationCount ||
        isVertical != oldDelegate.isVertical ||
        playerBottomOverride != oldDelegate.playerBottomOverride ||
        topInset != oldDelegate.topInset ||
        variant != oldDelegate.variant ||
        title != oldDelegate.title ||
        expandedIntro != oldDelegate.expandedIntro ||
        showRecommendations != oldDelegate.showRecommendations ||
        hasSeasonPanel != oldDelegate.hasSeasonPanel ||
        hasPagesPanel != oldDelegate.hasPagesPanel ||
        tabCount != oldDelegate.tabCount ||
        actionCount != oldDelegate.actionCount ||
        hasEpisodePanel != oldDelegate.hasEpisodePanel ||
        ugcTitleHeightOverride != oldDelegate.ugcTitleHeightOverride ||
        textScaler != oldDelegate.textScaler ||
        titleStyle != oldDelegate.titleStyle;
  }
}
