import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:PiliMax/common/style.dart';
import 'package:PiliMax/pilimax/common/widgets/video_card/video_card_h_layout_metrics.dart';
import 'package:PiliMax/pilimax/common/widgets/video_card/video_detail_hero_curve.dart';
import 'package:PiliMax/pilimax/common/widgets/video_card/video_detail_ugc_title_height_cache.dart';
import 'package:PiliMax/pilimax/common/widgets/video_card/video_transition_registry.dart';
import 'package:PiliMax/pilimax/pages/video/video_detail_back_progress.dart';
import 'package:PiliMax/pilimax/pages/video/video_layout_metrics.dart';
import 'package:PiliMax/plugin/pl_player/models/fullscreen_mode.dart';
import 'package:PiliMax/utils/grid.dart';
import 'package:PiliMax/utils/platform_utils.dart';
import 'package:PiliMax/utils/storage_pref.dart';
import 'package:PiliMax/utils/theme_utils.dart';

import 'package:material_ui/material_ui.dart';

export 'package:PiliMax/pilimax/common/widgets/video_card/video_transition_registry.dart'
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
    this.fadeFraction = 1 / 5,
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
  /// the final fraction, immediately before the source card is restored. The
  /// default one-fifth fraction is 80 ms on the shared 400 ms timeline.
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
    this.clipStaticChild = false,
  }) : tag = null,
       backProgress = null,
       _isDetailTarget = false;

  const VideoDetailHero.target({
    super.key,
    required this.tag,
    this.child = const VideoDetailHeroShell(),
    this.borderRadius = BorderRadius.zero,
    this.backProgress,
  }) : flightChild = null,
       flightOverlays = const <VideoDetailHeroFlightOverlay>[],
       clipStaticChild = false,
       _isDetailTarget = true;

  final Object? tag;
  final VideoDetailBackProgress? backProgress;

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

  /// Clips only the source's resting media stack. The flight child remains
  /// unclipped so the Hero overlay owns the animated radius exactly once.
  final bool clipStaticChild;
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
    final detailChild = fromChild.isDetailTarget ? fromChild : toChild;
    final sourceContext = fromChild.isDetailTarget
        ? toHeroContext
        : fromHeroContext;
    final sourceSize = _contextSize(sourceContext);
    final isPop = flightDirection == HeroFlightDirection.pop;
    final sourceVisibleRect = _sourceVisibleRect(
      sourceContext,
      sourceChild.registration,
    );

    final sourceFlightChild = RepaintBoundary(
      child: _FixedSizeFlightChild(
        layoutSize: sourceSize,
        child: sourceChild.flightChild ?? sourceChild.child,
      ),
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

        final Widget flightBody;
        if (sourceChild.flightOverlays.isEmpty) {
          flightBody = sourceFlightChild;
        } else {
          final backSnapshot = switch (detailChild.backProgress?.value) {
            final snapshot? when snapshot.phase != VideoDetailBackPhase.idle =>
              snapshot,
            _ => null,
          };
          final rawFlightProgress = _rawFlightProgress(
            flightProgress,
            isPop: isPop,
            backSnapshot: backSnapshot,
          );
          flightBody = Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.none,
            children: <Widget>[
              sourceFlightChild,
              for (final overlay in sourceChild.flightOverlays)
                _buildFlightOverlay(
                  overlay,
                  rawFlightProgress: rawFlightProgress,
                  isPop: isPop,
                ),
            ],
          );
        }

        return ClipRect(
          clipper: _NormalizedRectClipper(visibleRect),
          clipBehavior: Clip.hardEdge,
          child: ClipRRect(
            borderRadius: radius,
            clipBehavior: Clip.antiAlias,
            child: flightBody,
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
      backProgress: null,
      registration: null,
      child: child,
    );
  }

  static Widget _buildFlightOverlay(
    VideoDetailHeroFlightOverlay overlay, {
    required double rawFlightProgress,
    required bool isPop,
  }) {
    final opacity = _flightOverlayOpacity(
      overlay,
      rawFlightProgress: rawFlightProgress,
      isPop: isPop,
    );
    return Positioned(
      top: overlay.top ?? (overlay.bottom == null ? 0.0 : null),
      right: overlay.right,
      bottom: overlay.bottom,
      left: overlay.left ?? (overlay.right == null ? 0.0 : null),
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: Opacity(
            opacity: opacity,
            child: RepaintBoundary(child: overlay.child),
          ),
        ),
      ),
    );
  }

  static double _flightOverlayOpacity(
    VideoDetailHeroFlightOverlay overlay, {
    required double rawFlightProgress,
    required bool isPop,
  }) {
    final fraction = overlay.fadeFraction;
    if (!isPop) {
      if (rawFlightProgress <= 0) {
        return 1;
      }
      if (rawFlightProgress >= fraction) {
        return 0;
      }
      return 1 - Curves.ease.transform(rawFlightProgress / fraction);
    }

    final fadeStart = 1 - fraction;
    if (rawFlightProgress <= fadeStart) {
      return 0;
    }
    if (rawFlightProgress >= 1) {
      return 1;
    }
    return Curves.ease.transform(
      (rawFlightProgress - fadeStart) / fraction,
    );
  }

  static double _rawFlightProgress(
    double flightProgress, {
    required bool isPop,
    required VideoDetailBackSnapshot? backSnapshot,
  }) {
    final easedProgress = flightProgress.clamp(0.0, 1.0).toDouble();
    if (backSnapshot != null) {
      final sourceProgress = backSnapshot.sourcePresentationProgress;
      return isPop ? 1 - sourceProgress : sourceProgress;
    }
    return videoDetailRawProgressForEasedFlight(
      easedProgress,
      isPop: isPop,
    );
  }

  static Size _contextSize(BuildContext context) {
    final renderObject = context.findRenderObject();
    if (renderObject is RenderBox &&
        renderObject.attached &&
        renderObject.hasSize &&
        renderObject.size.isFinite &&
        !renderObject.size.isEmpty) {
      return renderObject.size;
    }
    return Size.zero;
  }

  static Rect _sourceVisibleRect(
    BuildContext sourceContext,
    VideoTransitionRegistration? registration,
  ) {
    final renderObject = sourceContext.findRenderObject();
    if (renderObject is! RenderBox ||
        !renderObject.attached ||
        !renderObject.hasSize ||
        !renderObject.size.isFinite ||
        renderObject.size.isEmpty ||
        registration == null) {
      return const Rect.fromLTWH(0, 0, 1, 1);
    }
    final cardVisibleRect = registration.currentVisibleRect();
    if (!renderObject.attached ||
        cardVisibleRect == null ||
        !cardVisibleRect.isFinite) {
      return const Rect.fromLTWH(0, 0, 1, 1);
    }
    final mediaOrigin = renderObject.localToGlobal(Offset.zero);
    if (!mediaOrigin.isFinite) {
      return const Rect.fromLTWH(0, 0, 1, 1);
    }
    final mediaRect = mediaOrigin & renderObject.size;
    if (!mediaRect.isFinite) {
      return const Rect.fromLTWH(0, 0, 1, 1);
    }
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
        clipStaticChild: clipStaticChild,
        flightChild: flightChild,
        flightOverlays: flightOverlays,
        child: child,
      );
    }
    return _buildHero(
      rawTag: tag!,
      borderRadius: borderRadius,
      isDetailTarget: true,
      backProgress: backProgress,
      child: child,
    );
  }

  static Widget _buildHero({
    Key? key,
    required Object rawTag,
    required BorderRadiusGeometry borderRadius,
    required bool isDetailTarget,
    VideoDetailBackProgress? backProgress,
    VideoTransitionRegistration? registration,
    required Widget child,
    Widget? flightChild,
    List<VideoDetailHeroFlightOverlay> flightOverlays =
        const <VideoDetailHeroFlightOverlay>[],
  }) {
    final transitionCurve = _VideoDetailHeroCurve(backProgress);
    return Hero(
      key: key,
      tag: _VideoDetailMediaHeroTag(rawTag),
      curve: transitionCurve,
      reverseCurve: transitionCurve,
      createRectTween: VideoDetailHero._createRectTween,
      flightShuttleBuilder: VideoDetailHero._flightShuttleBuilder,
      transitionOnUserGestures: true,
      placeholderBuilder: VideoDetailHero._buildPlaceholder,
      child: _VideoDetailHeroChild(
        borderRadius: borderRadius,
        isDetailTarget: isDetailTarget,
        backProgress: backProgress,
        registration: registration,
        flightChild: flightChild,
        flightOverlays: flightOverlays,
        child: child,
      ),
    );
  }
}

final class _VideoDetailHeroCurve extends Curve {
  const _VideoDetailHeroCurve(this.backProgress);

  final VideoDetailBackProgress? backProgress;

  @override
  double transformInternal(double t) {
    final snapshot = backProgress?.value;
    if (snapshot != null && snapshot.phase != VideoDetailBackPhase.idle) {
      return snapshot.entryProgress;
    }
    return videoDetailHeroForwardCurve.transform(t);
  }
}

class _VideoDetailMediaHeroSource extends StatefulWidget {
  const _VideoDetailMediaHeroSource({
    required this.borderRadius,
    required this.clipStaticChild,
    required this.child,
    required this.flightChild,
    required this.flightOverlays,
  });

  final BorderRadiusGeometry borderRadius;
  final bool clipStaticChild;
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
    final staticChild = widget.clipStaticChild
        ? ClipRRect(borderRadius: widget.borderRadius, child: widget.child)
        : widget.child;
    if (scope == null) {
      return staticChild;
    }
    return VideoDetailHero._buildHero(
      key: _mediaBoundaryKey,
      rawTag: scope.tag,
      borderRadius: widget.borderRadius,
      isDetailTarget: false,
      backProgress: null,
      registration: scope.registration,
      child: staticChild,
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
class VideoDetailHeroShell extends StatefulWidget {
  const VideoDetailHeroShell({
    super.key,
    this.playerSurfaceOpacity = 1,
    this.navigationSurfaceOpacity = 1,
    this.detailSurfaceOpacity = 1,
    this.recommendationSurfaceOpacity = 1,
    this.recommendationCount = 4,
    this.isVertical,
    this.isPortrait,
    this.playerBottomOverride,
    this.variant = VideoDetailSkeletonVariant.ugc,
    this.title,
    this.expandedIntro = false,
    this.showRecommendations = true,
    this.hasSeasonPanel = false,
    this.hasPagesPanel = false,
    this.seasonPanelVisibility,
    this.pagesPanelVisibility,
    this.showUgcTitlePlaceholder = true,
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
       assert(
         seasonPanelVisibility == null ||
             (seasonPanelVisibility >= 0 && seasonPanelVisibility <= 1),
       ),
       assert(
         pagesPanelVisibility == null ||
             (pagesPanelVisibility >= 0 && pagesPanelVisibility <= 1),
       ),
       assert(recommendationCount >= 0),
       assert(tabCount > 0),
       assert(actionCount >= 0);

  factory VideoDetailHeroShell.revealing({
    Key? key,
    required double progress,
    int recommendationCount = 4,
    bool? isVertical,
    bool? isPortrait,
    double? playerBottomOverride,
    VideoDetailSkeletonVariant variant = VideoDetailSkeletonVariant.ugc,
    String? title,
    bool expandedIntro = false,
    bool showRecommendations = true,
    bool hasSeasonPanel = false,
    bool hasPagesPanel = false,
    double? seasonPanelVisibility,
    double? pagesPanelVisibility,
    bool showUgcTitlePlaceholder = true,
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
    isPortrait: isPortrait,
    playerBottomOverride: playerBottomOverride,
    variant: variant,
    title: title,
    expandedIntro: expandedIntro,
    showRecommendations: showRecommendations,
    hasSeasonPanel: hasSeasonPanel,
    hasPagesPanel: hasPagesPanel,
    seasonPanelVisibility: seasonPanelVisibility,
    pagesPanelVisibility: pagesPanelVisibility,
    showUgcTitlePlaceholder: showUgcTitlePlaceholder,
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
  final bool? isPortrait;
  final double? playerBottomOverride;
  final VideoDetailSkeletonVariant variant;
  final String? title;
  final bool expandedIntro;
  final bool showRecommendations;
  final bool hasSeasonPanel;
  final bool hasPagesPanel;
  final double? seasonPanelVisibility;
  final double? pagesPanelVisibility;
  final bool showUgcTitlePlaceholder;
  final int tabCount;
  final int actionCount;
  final bool hasEpisodePanel;
  final double? ugcTitleHeightOverride;

  @override
  State<VideoDetailHeroShell> createState() => _VideoDetailHeroShellState();

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
}

class _VideoDetailHeroShellState extends State<VideoDetailHeroShell>
    with SingleTickerProviderStateMixin {
  static const _shimmerDuration = Duration(milliseconds: 800);
  static const _shimmerInitialValue = 0.2;

  final VideoDetailUgcTitleHeightCache _ugcTitleHeightCache =
      VideoDetailUgcTitleHeightCache();
  late final AnimationController _shimmerController = AnimationController(
    vsync: this,
    duration: _shimmerDuration,
  );
  bool _shimmerEnabled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shouldAnimate =
        !(MediaQuery.maybeOf(context)?.disableAnimations ?? false);
    if (shouldAnimate == _shimmerEnabled) {
      return;
    }
    _shimmerEnabled = shouldAnimate;
    if (shouldAnimate) {
      _shimmerController
        ..value = _shimmerInitialValue
        ..repeat(min: _shimmerInitialValue);
    } else {
      _shimmerController
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Pref.darkVideoPage
        ? ThemeUtils.darkTheme.colorScheme
        : Theme.of(context).colorScheme;
    final mediaSize = MediaQuery.sizeOf(context);
    final entryPadding = Pref.removeSafeArea
        ? EdgeInsets.zero
        : MediaQuery.viewPaddingOf(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final titleStyle = DefaultTextStyle.of(context).style.copyWith(
      fontSize: VideoDetailLayoutMetrics.ugcTitleFontSize,
    );
    final textDirection = Directionality.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : mediaSize.width;
        final height = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : mediaSize.height;
        final isPortrait = widget.isPortrait ?? height >= width;
        final viewport = Size(width, height);
        final landscapeEntryLayout = isPortrait
            ? null
            : VideoDetailLayoutMetrics.entryLayout(
                viewport,
                isVertical: widget.isVertical,
                topInset: entryPadding.top,
                pagePadding: entryPadding,
                isPortrait: false,
              );
        final landscapeInfoWidth = landscapeEntryLayout == null
            ? width
            : VideoDetailLayoutMetrics.landscapeInfoPanelRect(
                viewport,
                landscapeEntryLayout,
                pagePadding: entryPadding,
              ).width;
        final ugcTitleHeight = widget.variant == VideoDetailSkeletonVariant.ugc
            ? _ugcTitleHeightCache.resolve(
                title: widget.title,
                viewportWidth: landscapeInfoWidth > 0
                    ? landscapeInfoWidth
                    : width,
                style: titleStyle,
                textScaler: textScaler,
                textDirection: textDirection,
                override: widget.ugcTitleHeightOverride,
              )
            : widget.ugcTitleHeightOverride ??
                  VideoDetailUgcTitleHeightCache.fallbackHeight;
        return SizedBox(
          width: width,
          height: height,
          child: CustomPaint(
            painter: _VideoDetailSkeletonPainter(
              colorScheme: colorScheme,
              playerSurfaceOpacity: widget.playerSurfaceOpacity,
              navigationSurfaceOpacity: widget.navigationSurfaceOpacity,
              detailSurfaceOpacity: widget.detailSurfaceOpacity,
              recommendationSurfaceOpacity: widget.recommendationSurfaceOpacity,
              recommendationCount: widget.recommendationCount,
              isVertical: widget.isVertical,
              isPortrait: isPortrait,
              isDesktop: PlatformUtils.isDesktop,
              playerBottomOverride: widget.playerBottomOverride,
              topInset: entryPadding.top,
              entryPadding: entryPadding,
              variant: widget.variant,
              expandedIntro: widget.expandedIntro,
              showRecommendations: widget.showRecommendations,
              seasonPanelVisibility:
                  widget.seasonPanelVisibility ??
                  (widget.hasSeasonPanel ? 1.0 : 0.0),
              pagesPanelVisibility:
                  widget.pagesPanelVisibility ??
                  (widget.hasPagesPanel ? 1.0 : 0.0),
              showUgcTitlePlaceholder: widget.showUgcTitlePlaceholder,
              tabCount: widget.tabCount,
              actionCount: widget.actionCount,
              hasEpisodePanel: widget.hasEpisodePanel,
              ugcTitleHeight: ugcTitleHeight,
              shimmer: _shimmerController,
              shimmerViewportWidth: width,
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
    required this.backProgress,
    required this.registration,
    required this.child,
    this.flightChild,
    this.flightOverlays = const <VideoDetailHeroFlightOverlay>[],
  });

  final BorderRadiusGeometry borderRadius;
  final bool isDetailTarget;
  final VideoDetailBackProgress? backProgress;
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
    required this.isPortrait,
    required this.isDesktop,
    required this.playerBottomOverride,
    required this.topInset,
    required this.entryPadding,
    required this.variant,
    required this.expandedIntro,
    required this.showRecommendations,
    required this.seasonPanelVisibility,
    required this.pagesPanelVisibility,
    required this.showUgcTitlePlaceholder,
    required this.tabCount,
    required this.actionCount,
    required this.hasEpisodePanel,
    required this.ugcTitleHeight,
    required this.shimmer,
    required this.shimmerViewportWidth,
  }) : super(repaint: shimmer);

  final ColorScheme colorScheme;
  final double playerSurfaceOpacity;
  final double navigationSurfaceOpacity;
  final double detailSurfaceOpacity;
  final double recommendationSurfaceOpacity;
  final int recommendationCount;
  final bool? isVertical;
  final bool isPortrait;
  final bool isDesktop;
  final double? playerBottomOverride;
  final double topInset;
  final EdgeInsets entryPadding;
  final VideoDetailSkeletonVariant variant;
  final bool expandedIntro;
  final bool showRecommendations;
  final double seasonPanelVisibility;
  final double pagesPanelVisibility;
  final bool showUgcTitlePlaceholder;
  final int tabCount;
  final int actionCount;
  final bool hasEpisodePanel;
  final double ugcTitleHeight;
  final Animation<double> shimmer;
  final double shimmerViewportWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }

    canvas
      ..save()
      ..clipRect(Offset.zero & size);

    if (!isPortrait) {
      _paintLandscape(canvas, size);
      canvas.restore();
      return;
    }

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

  void _paintLandscape(Canvas canvas, Size size) {
    final entryLayout = VideoDetailLayoutMetrics.entryLayout(
      size,
      isVertical: isVertical,
      topInset: topInset,
      pagePadding: entryPadding,
      isPortrait: false,
    );
    final playerRect = entryLayout.playerRect;
    final infoPanel = VideoDetailLayoutMetrics.landscapeInfoPanelRect(
      size,
      entryLayout,
      pagePadding: entryPadding,
    );
    final sidebarPanel = VideoDetailLayoutMetrics.landscapeSidebarPanelRect(
      size,
      entryLayout,
      pagePadding: entryPadding,
    );
    final showsRelatedSidebar =
        entryLayout.pageLayout == VideoDetailEntryPageLayout.landscape &&
        variant == VideoDetailSkeletonVariant.ugc &&
        showRecommendations;

    final surroundingSurfaceOpacity = math.max(
      math.max(navigationSurfaceOpacity, detailSurfaceOpacity),
      showsRelatedSidebar ? recommendationSurfaceOpacity : 0.0,
    );
    if (surroundingSurfaceOpacity > 0) {
      final surroundingSurface = Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Offset.zero & size)
        ..addRect(playerRect);
      canvas.drawPath(
        surroundingSurface,
        Paint()
          ..color = colorScheme.surface.withValues(
            alpha: surroundingSurfaceOpacity,
          ),
      );
    }
    if (playerSurfaceOpacity > 0) {
      canvas.drawRect(
        playerRect,
        Paint()..color = Colors.black.withValues(alpha: playerSurfaceOpacity),
      );
    }

    if (sidebarPanel.width > 0) {
      _paintLandscapeSidebar(
        canvas,
        sidebarPanel,
        showRelatedList: showsRelatedSidebar,
      );
    }
    if (!infoPanel.isEmpty) {
      _paintLandscapeInfo(canvas, infoPanel);
    }
  }

  void _paintLandscapeSidebar(
    Canvas canvas,
    Rect rect, {
    required bool showRelatedList,
  }) {
    final navigation = Rect.fromLTWH(
      rect.left,
      rect.top,
      rect.width,
      math.min(VideoDetailLayoutMetrics.tabBarHeight, rect.height),
    );
    _paintNavigation(canvas, navigation);

    final bodyTop =
        navigation.bottom + VideoDetailLayoutMetrics.relatedTopPadding;
    final bodyOpacity = showRelatedList
        ? recommendationSurfaceOpacity
        : detailSurfaceOpacity;
    _paintSection(
      canvas,
      Rect.fromLTRB(rect.left, bodyTop, rect.right, rect.bottom),
      bodyOpacity,
      () {
        if (!showRelatedList) {
          return;
        }
        final primaryPaint = _skeletonPaint(recommendationSurfaceOpacity);
        final subtlePaint = _subtlePaint(recommendationSurfaceOpacity);
        var top = bodyTop;
        final visibleRecommendationCount = math.max(
          recommendationCount,
          VideoDetailLayoutMetrics.landscapeRecommendationCountForSidebarHeight(
            rect.height,
          ),
        );
        for (
          var index = 0;
          index < visibleRecommendationCount && top < rect.bottom;
          index++
        ) {
          const itemHeight = VideoDetailLayoutMetrics.relatedCardHeight;
          final itemContentTop = top + VideoCardHLayoutMetrics.verticalPadding;
          final thumbnailWidth = math.min(
            VideoCardHLayoutMetrics.thumbnailWidth,
            math.max(
              0.0,
              rect.width - 2 * VideoCardHLayoutMetrics.horizontalPadding,
            ),
          );
          final thumbnailHeight = math.min(
            VideoCardHLayoutMetrics.thumbnailHeight,
            math.max(
              0.0,
              itemHeight - 2 * VideoCardHLayoutMetrics.verticalPadding,
            ),
          );
          final thumbnail = Rect.fromLTWH(
            rect.left + VideoCardHLayoutMetrics.horizontalPadding,
            itemContentTop,
            thumbnailWidth,
            thumbnailHeight,
          );
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              thumbnail,
              const Radius.circular(VideoCardHLayoutMetrics.thumbnailRadius),
            ),
            _thumbnailPaint(recommendationSurfaceOpacity),
          );
          final textLeft = thumbnail.right + VideoCardHLayoutMetrics.contentGap;
          final textWidth = math.max(
            0.0,
            rect.right -
                VideoCardHLayoutMetrics.horizontalPadding -
                6 -
                textLeft,
          );
          final textTop = itemContentTop + 4;
          final textBottom = itemContentTop + thumbnailHeight - 4;
          final detailTop = math.max(textTop + 29, textBottom - 31);
          final statTop = math.max(detailTop + 18, textBottom - 13);
          _drawBar(
            canvas,
            Rect.fromLTWH(
              textLeft,
              textTop,
              math.min(200.0, textWidth),
              11,
            ),
            primaryPaint,
          );
          _drawBar(
            canvas,
            Rect.fromLTWH(
              textLeft,
              textTop + 16,
              math.min(150.0, textWidth),
              13,
            ),
            subtlePaint,
          );
          _drawBar(
            canvas,
            Rect.fromLTWH(
              textLeft,
              detailTop,
              math.min(100.0, textWidth),
              13,
            ),
            subtlePaint,
          );
          _drawBar(
            canvas,
            Rect.fromLTWH(
              textLeft,
              statTop,
              math.min(40.0, textWidth),
              13,
            ),
            subtlePaint,
          );
          _drawBar(
            canvas,
            Rect.fromLTWH(
              textLeft + math.min(48.0, textWidth),
              statTop,
              math.min(40.0, math.max(0.0, textWidth - 48)),
              13,
            ),
            subtlePaint,
          );
          top += itemHeight + VideoDetailLayoutMetrics.relatedCardSpacing;
        }
      },
    );
  }

  void _paintLandscapeInfo(Canvas canvas, Rect rect) {
    if (rect.isEmpty) {
      return;
    }
    canvas
      ..save()
      ..clipRect(rect)
      ..translate(rect.left, rect.top);
    final panelSize = rect.size;
    switch (variant) {
      case VideoDetailSkeletonVariant.ugc:
        _paintLandscapeUgcInfo(
          canvas,
          panelSize,
        );
        break;
      case VideoDetailSkeletonVariant.pgc:
        _paintPgcBody(canvas, panelSize, 0, showActions: true);
        break;
      case VideoDetailSkeletonVariant.pugv:
        _paintPgcBody(canvas, panelSize, 0, showActions: false);
        break;
      case VideoDetailSkeletonVariant.local:
        _paintLocalBody(canvas, panelSize, 0);
        break;
    }
    canvas.restore();
  }

  void _paintLandscapeUgcInfo(Canvas canvas, Size size) {
    final layout = _LandscapeUgcInfoLayout.resolve(
      size,
      titleHeight: ugcTitleHeight,
      isDesktop: isDesktop,
      expandedIntro: expandedIntro,
    );
    const padding = VideoDetailLayoutMetrics.horizontalPadding;
    final contentWidth = math.max(0.0, size.width - 2 * padding);
    final actionRect = layout.actionRect;
    final panelHeight =
        seasonPanelVisibility * VideoDetailLayoutMetrics.seasonPanelHeight +
        pagesPanelVisibility * VideoDetailLayoutMetrics.pagesPanelHeight;

    _paintSection(
      canvas,
      Offset.zero & size,
      detailSurfaceOpacity,
      () {
        final primaryPaint = _skeletonPaint(detailSurfaceOpacity);
        final subtlePaint = _subtlePaint(detailSurfaceOpacity);
        canvas
          ..drawCircle(
            layout.avatarRect.center,
            layout.avatarRect.width / 2,
            primaryPaint,
          )
          ..drawRRect(
            RRect.fromRectAndRadius(
              layout.followRect,
              const Radius.circular(6),
            ),
            _coloredSkeletonPaint(
              color: colorScheme.secondaryContainer,
              opacity: detailSurfaceOpacity,
            ),
          );
        _drawBar(
          canvas,
          Rect.fromLTWH(
            layout.authorRect.left,
            layout.authorRect.top + 5,
            layout.authorRect.width * 0.58,
            10,
          ),
          primaryPaint,
        );
        _drawBar(
          canvas,
          Rect.fromLTWH(
            layout.authorRect.left,
            layout.authorRect.top + 23,
            layout.authorRect.width * 0.78,
            8,
          ),
          subtlePaint,
        );

        if (showUgcTitlePlaceholder) {
          _drawBar(
            canvas,
            Rect.fromLTWH(
              padding,
              layout.titleRect.top,
              contentWidth * 0.92,
              14,
            ),
            primaryPaint,
          );
          if (layout.titleRect.height > 24) {
            _drawBar(
              canvas,
              Rect.fromLTWH(
                padding,
                layout.titleRect.top + 20,
                contentWidth * 0.64,
                10,
              ),
              subtlePaint,
            );
          }
        }
        _paintStats(canvas, padding, layout.statsTop, subtlePaint);
        if (layout.showsDescription) {
          _drawBar(
            canvas,
            Rect.fromLTWH(
              padding,
              layout.descriptionTop,
              contentWidth * 0.22,
              9,
            ),
            subtlePaint,
          );
          _drawBar(
            canvas,
            Rect.fromLTWH(
              padding,
              layout.descriptionTop + 20,
              contentWidth * 0.94,
              9,
            ),
            subtlePaint,
          );
          _drawBar(
            canvas,
            Rect.fromLTWH(
              padding,
              layout.descriptionTop + 39,
              contentWidth * 0.72,
              9,
            ),
            subtlePaint,
          );
        }
        if (actionRect != null) {
          _paintActions(canvas, actionRect, detailSurfaceOpacity);
        }
        _paintUgcPanels(
          canvas,
          Rect.fromLTWH(padding, layout.panelsTop, contentWidth, panelHeight),
          detailSurfaceOpacity,
        );
      },
    );
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
            center: Offset(rect.left + tabWidth * (index + 0.5), centerY),
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
            center: Offset(rect.left + tabWidth / 2, rect.bottom - 1),
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
    final titleTop = VideoDetailLayoutMetrics.ugcTitleTop(top);
    final secondTitleTop = titleTop + 20;
    final titleHeight = ugcTitleHeight;
    final statsTop = titleTop + titleHeight + gap;
    final descriptionTop = statsTop + 18 + gap;
    final actionTop = descriptionTop + (expandedIntro ? 72 : 0);
    final actionBottom = actionTop + VideoDetailLayoutMetrics.actionHeight;
    final panelHeight =
        seasonPanelVisibility * VideoDetailLayoutMetrics.seasonPanelHeight +
        pagesPanelVisibility * VideoDetailLayoutMetrics.pagesPanelHeight;
    final naturalRecommendationTop =
        actionBottom +
        panelHeight +
        VideoDetailLayoutMetrics.relatedDividerTopPadding;
    final recommendationTop =
        VideoDetailLayoutMetrics.portraitRecommendationTop(
          viewport: size,
          bodyTop: top,
          naturalTop: naturalRecommendationTop,
          reserveVisiblePreview: isVertical == true && showRecommendations,
        );

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
          _coloredSkeletonPaint(
            color: colorScheme.secondaryContainer,
            opacity: detailSurfaceOpacity,
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
        if (showUgcTitlePlaceholder) {
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
          _coloredSkeletonPaint(
            color: colorScheme.secondaryContainer,
            opacity: detailSurfaceOpacity,
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
    var top = rect.top;
    if (seasonPanelVisibility > 0) {
      final extent =
          VideoDetailLayoutMetrics.seasonPanelHeight * seasonPanelVisibility;
      canvas
        ..save()
        ..clipRect(Rect.fromLTWH(rect.left, top, rect.width, extent));
      _paintUgcSeasonPanel(
        canvas,
        Rect.fromLTWH(
          rect.left,
          top,
          rect.width,
          VideoDetailLayoutMetrics.seasonPanelHeight,
        ),
        opacity * seasonPanelVisibility,
      );
      canvas.restore();
      top += extent;
    }
    if (pagesPanelVisibility > 0) {
      final panelOpacity = opacity * pagesPanelVisibility;
      final primaryPaint = _skeletonPaint(panelOpacity);
      final subtlePaint = _subtlePaint(panelOpacity);
      final tilePaint = _thumbnailPaint(panelOpacity);
      final extent =
          VideoDetailLayoutMetrics.pagesPanelHeight * pagesPanelVisibility;
      canvas
        ..save()
        ..clipRect(Rect.fromLTWH(rect.left, top, rect.width, extent));
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
      canvas.restore();
    }
  }

  void _paintUgcSeasonPanel(Canvas canvas, Rect slot, double opacity) {
    final surfaceRect = VideoDetailLayoutMetrics.seasonPanelSurfaceRect(slot);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        surfaceRect,
        const Radius.circular(VideoDetailLayoutMetrics.seasonPanelRadius),
      ),
      _seasonPanelPaint(opacity),
    );

    final contentLeft =
        surfaceRect.left +
        VideoDetailLayoutMetrics.seasonPanelContentHorizontalPadding;
    final contentRight =
        surfaceRect.right -
        VideoDetailLayoutMetrics.seasonPanelContentHorizontalPadding;
    final centerY = surfaceRect.center.dy;
    final arrowLeft =
        contentRight - VideoDetailLayoutMetrics.seasonPanelArrowExtent;
    final countRight = arrowLeft - VideoDetailLayoutMetrics.seasonPanelArrowGap;
    final countLeft =
        countRight - VideoDetailLayoutMetrics.seasonPanelCountPlaceholderWidth;
    final statusRight =
        countLeft - VideoDetailLayoutMetrics.seasonPanelStatusGap;
    final statusLeft =
        statusRight - VideoDetailLayoutMetrics.seasonPanelStatusIconExtent;
    final titleRight =
        statusLeft - VideoDetailLayoutMetrics.seasonPanelLeadingGap;
    final titleWidth = math.max(0.0, titleRight - contentLeft);
    final primaryPaint = _skeletonPaint(opacity);
    final subtlePaint = _subtlePaint(opacity);

    _drawBar(
      canvas,
      Rect.fromCenter(
        center: Offset(contentLeft + titleWidth * 0.44, centerY),
        width: titleWidth * 0.88,
        height: 9,
      ),
      primaryPaint,
    );
    canvas.drawCircle(
      Offset(
        statusLeft + VideoDetailLayoutMetrics.seasonPanelStatusIconExtent / 2,
        centerY,
      ),
      VideoDetailLayoutMetrics.seasonPanelStatusIconExtent / 2,
      _coloredSkeletonPaint(
        color: colorScheme.primary,
        opacity: opacity,
        baseOpacity: 0.46,
      ),
    );
    _drawBar(
      canvas,
      Rect.fromCenter(
        center: Offset((countLeft + countRight) / 2, centerY),
        width: VideoDetailLayoutMetrics.seasonPanelCountPlaceholderWidth,
        height: 8,
      ),
      subtlePaint,
    );
    _drawBar(
      canvas,
      Rect.fromCenter(
        center: Offset(
          arrowLeft + VideoDetailLayoutMetrics.seasonPanelArrowExtent / 2,
          centerY,
        ),
        width: VideoDetailLayoutMetrics.seasonPanelArrowExtent,
        height: 8,
      ),
      subtlePaint,
    );
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

  Paint _skeletonPaint(double opacity) => _shimmerPaint(
    baseColor: colorScheme.onSurfaceVariant,
    baseOpacity: 0.17 * opacity,
    highlightOpacity: 0.56 * opacity,
  );

  Paint _subtlePaint(double opacity) => _shimmerPaint(
    baseColor: colorScheme.onSurfaceVariant,
    baseOpacity: 0.11 * opacity,
    highlightOpacity: 0.48 * opacity,
  );

  Paint _thumbnailPaint(double opacity) => _shimmerPaint(
    baseColor: colorScheme.surfaceContainerHighest,
    baseOpacity: 0.92 * opacity,
    highlightOpacity: 0.98 * opacity,
  );

  Paint _coloredSkeletonPaint({
    required Color color,
    required double opacity,
    double baseOpacity = 0.72,
  }) => _shimmerPaint(
    baseColor: color,
    baseOpacity: baseOpacity * opacity,
    highlightOpacity: 0.98 * opacity,
  );

  Paint _seasonPanelPaint(double opacity) {
    final baseColor = colorScheme.onInverseSurface;
    return _shimmerPaint(
      baseColor: baseColor,
      highlightColor: Color.lerp(
        baseColor,
        colorScheme.onSurfaceVariant,
        0.18,
      )!,
      baseOpacity: opacity,
      highlightOpacity: opacity,
    );
  }

  Paint _shimmerPaint({
    required Color baseColor,
    Color? highlightColor,
    required double baseOpacity,
    required double highlightOpacity,
  }) {
    final resolvedBaseOpacity = baseOpacity.clamp(0.0, 1.0).toDouble();
    final resolvedHighlightOpacity = highlightOpacity
        .clamp(0.0, 1.0)
        .toDouble();
    final resolvedHighlightColor =
        highlightColor ?? _brightShimmerColor(baseColor);
    final sweepWidth = math.max(1.0, shimmerViewportWidth);
    final bandWidth = (sweepWidth * 0.32).clamp(96.0, 220.0).toDouble();
    final center = -bandWidth + shimmer.value * (sweepWidth + 2 * bandWidth);
    final base = baseColor.withValues(alpha: resolvedBaseOpacity);
    final highlight = resolvedHighlightColor.withValues(
      alpha: resolvedHighlightOpacity,
    );
    return Paint()
      ..shader = ui.Gradient.linear(
        Offset(center - bandWidth, 0),
        Offset(center + bandWidth, 0),
        <Color>[base, base, highlight, base, base],
        <double>[0, 0.3, 0.5, 0.7, 1],
      );
  }

  Color _brightShimmerColor(Color baseColor) {
    final highlightTarget = colorScheme.brightness == Brightness.dark
        ? colorScheme.onSurface
        : colorScheme.surface;
    return Color.lerp(baseColor, highlightTarget, 0.78)!;
  }

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
        isPortrait != oldDelegate.isPortrait ||
        isDesktop != oldDelegate.isDesktop ||
        playerBottomOverride != oldDelegate.playerBottomOverride ||
        topInset != oldDelegate.topInset ||
        variant != oldDelegate.variant ||
        expandedIntro != oldDelegate.expandedIntro ||
        showRecommendations != oldDelegate.showRecommendations ||
        seasonPanelVisibility != oldDelegate.seasonPanelVisibility ||
        pagesPanelVisibility != oldDelegate.pagesPanelVisibility ||
        showUgcTitlePlaceholder != oldDelegate.showUgcTitlePlaceholder ||
        tabCount != oldDelegate.tabCount ||
        actionCount != oldDelegate.actionCount ||
        hasEpisodePanel != oldDelegate.hasEpisodePanel ||
        ugcTitleHeight != oldDelegate.ugcTitleHeight ||
        shimmer != oldDelegate.shimmer ||
        shimmerViewportWidth != oldDelegate.shimmerViewportWidth;
  }
}

final class _LandscapeUgcInfoLayout {
  const _LandscapeUgcInfoLayout({
    required this.avatarRect,
    required this.authorRect,
    required this.followRect,
    required this.actionRect,
    required this.titleRect,
    required this.statsTop,
    required this.descriptionTop,
    required this.panelsTop,
    required this.showsDescription,
  });

  final Rect avatarRect;
  final Rect authorRect;
  final Rect followRect;
  final Rect? actionRect;
  final Rect titleRect;
  final double statsTop;
  final double descriptionTop;
  final double panelsTop;
  final bool showsDescription;

  static _LandscapeUgcInfoLayout resolve(
    Size panelSize, {
    required double titleHeight,
    required bool isDesktop,
    required bool expandedIntro,
  }) {
    const padding = VideoDetailLayoutMetrics.horizontalPadding;
    const inlineGap = 10.0;
    final contentWidth = math.max(0.0, panelSize.width - 2 * padding);
    final actionsInline =
        panelSize.height > 0 &&
        panelSize.width / panelSize.height >= kScreenRatio;
    final followWidth = math.min(72.0, contentWidth * 0.2);
    final flexWidth = math.max(
      0.0,
      contentWidth - followWidth - (actionsInline ? inlineGap : 0.0),
    );
    final ownerWidth = actionsInline ? flexWidth / 2 : flexWidth;
    const ownerTop = VideoDetailLayoutMetrics.introTopPadding;
    const ownerHeight = VideoDetailLayoutMetrics.ownerHeight;
    const avatarRect = Rect.fromLTWH(
      padding,
      ownerTop,
      ownerHeight,
      ownerHeight,
    );
    final authorLeft = avatarRect.right + 10;
    final ownerRight = padding + ownerWidth;
    final authorRect = Rect.fromLTWH(
      authorLeft,
      ownerTop,
      math.max(0.0, ownerRight - authorLeft),
      ownerHeight,
    );
    final followRect = Rect.fromLTWH(ownerRight, ownerTop + 3, followWidth, 29);
    final actionRect = actionsInline
        ? Rect.fromLTWH(
            followRect.right + inlineGap,
            ownerTop,
            ownerWidth,
            VideoDetailLayoutMetrics.actionHeight,
          )
        : null;
    final ownerRowHeight = actionsInline
        ? VideoDetailLayoutMetrics.actionHeight
        : ownerHeight;
    final titleTop =
        ownerTop + ownerRowHeight + VideoDetailLayoutMetrics.sectionGap;
    final titleRect = Rect.fromLTWH(
      padding,
      titleTop,
      contentWidth,
      math.max(0.0, titleHeight),
    );
    final statsTop = titleRect.bottom + VideoDetailLayoutMetrics.sectionGap;
    final descriptionTop = statsTop + 18 + VideoDetailLayoutMetrics.sectionGap;
    final showsDescription = expandedIntro || (actionsInline && isDesktop);
    final belowActionsRect = actionsInline
        ? null
        : Rect.fromLTWH(
            padding,
            descriptionTop + (showsDescription ? 72 : 0),
            contentWidth,
            VideoDetailLayoutMetrics.actionHeight,
          );
    return _LandscapeUgcInfoLayout(
      avatarRect: avatarRect,
      authorRect: authorRect,
      followRect: followRect,
      actionRect: actionRect ?? belowActionsRect,
      titleRect: titleRect,
      statsTop: statsTop,
      descriptionTop: descriptionTop,
      panelsTop: actionsInline
          ? descriptionTop + (showsDescription ? 72 : 0)
          : belowActionsRect!.bottom,
      showsDescription: showsDescription,
    );
  }
}
