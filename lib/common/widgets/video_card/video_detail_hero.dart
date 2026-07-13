import 'dart:math' as math;

import 'package:PiliMax/common/style.dart';
import 'package:PiliMax/common/widgets/video_card/video_transition_registry.dart';
import 'package:PiliMax/pages/video/video_layout_metrics.dart';
import 'package:PiliMax/utils/grid.dart';
import 'package:PiliMax/utils/storage_pref.dart';

import 'package:flutter/gestures.dart' show kPrimaryButton;
import 'package:flutter/material.dart';

/// Registers the whole card as the predictive-back return target.
///
/// A descendant [VideoDetailHero.source] owns the independent media Hero.
class VideoDetailTransitionSource extends StatefulWidget {
  const VideoDetailTransitionSource({
    super.key,
    required this.tag,
    required this.child,
    this.borderRadius = Style.mdRadius,
  });

  final Object tag;
  final Widget child;
  final BorderRadiusGeometry borderRadius;

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
        oldWidget.borderRadius != widget.borderRadius) {
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
    final child = RepaintBoundary(
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
        onPointerDown: (event) {
          if (event.buttons & kPrimaryButton != 0) {
            registration.prepare();
          }
        },
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
    this.style,
    this.maxLines,
    this.textAlign,
    this.overflow,
  }) : assert(maxLines == null || maxLines > 0);

  final String text;
  final Widget child;
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
  Widget build(BuildContext context) => RepaintBoundary(
    key: _titleBoundaryKey,
    child: widget.child,
  );
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
    this.borderRadius = Style.mdRadius,
  }) : tag = null,
       _isDetailTarget = false;

  const VideoDetailHero.target({
    super.key,
    required this.tag,
    this.child = const VideoDetailHeroShell(),
    this.borderRadius = BorderRadius.zero,
  }) : _isDetailTarget = true;

  final Object? tag;
  final Widget child;
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
    final detailChild = fromChild.isDetailTarget ? fromChild : toChild;
    final sourceContext = fromChild.isDetailTarget
        ? toHeroContext
        : fromHeroContext;
    final detailContext = fromChild.isDetailTarget
        ? fromHeroContext
        : toHeroContext;
    final sourceSize = _contextSize(sourceContext);
    final detailSize = _contextSize(detailContext);
    final isPop = flightDirection == HeroFlightDirection.pop;

    final sourceFlightChild = _FixedSizeFlightChild(
      layoutSize: sourceSize,
      child: sourceChild.child,
    );
    final detailFlightChild = _detailFlightSurface(
      detailChild.child,
      layoutSize: detailSize,
      isPop: isPop,
    );

    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final flightProgress = switch (flightDirection) {
          HeroFlightDirection.push => animation.value,
          HeroFlightDirection.pop => 1 - animation.value,
        };
        final radius =
            (isPop
                ? BorderRadiusGeometry.lerp(
                    detailChild.borderRadius,
                    sourceChild.borderRadius,
                    flightProgress,
                  )
                : BorderRadiusGeometry.lerp(
                    sourceChild.borderRadius,
                    detailChild.borderRadius,
                    flightProgress,
                  )) ??
            detailChild.borderRadius;
        const sourceOpacity = 1.0;
        final detailOpacity = isPop ? 1 - flightProgress : flightProgress;

        return RepaintBoundary(
          child: ClipRRect(
            borderRadius: radius,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Opacity(opacity: sourceOpacity, child: sourceFlightChild),
                Opacity(opacity: detailOpacity, child: detailFlightChild),
              ],
            ),
          ),
        );
      },
    );
  }

  static Widget _detailFlightSurface(
    Widget child, {
    required Size layoutSize,
    required bool isPop,
  }) {
    if (child case final VideoDetailHeroShell shell) {
      return _FixedSizeFlightChild(
        layoutSize: layoutSize,
        alignment: Alignment.topCenter,
        child: VideoDetailHeroShell(
          // Keep the live player/cover visible under every reverse flight.
          playerSurfaceOpacity: isPop ? 0 : shell.playerSurfaceOpacity,
          navigationSurfaceOpacity: shell.navigationSurfaceOpacity,
          detailSurfaceOpacity: shell.detailSurfaceOpacity,
          recommendationSurfaceOpacity: shell.recommendationSurfaceOpacity,
          recommendationCount: shell.recommendationCount,
          isVertical: shell.isVertical,
          playerBottomOverride: shell.playerBottomOverride,
          variant: shell.variant,
          title: shell.title,
          expandedIntro: shell.expandedIntro,
          showRecommendations: shell.showRecommendations,
          hasSeasonPanel: shell.hasSeasonPanel,
          hasPagesPanel: shell.hasPagesPanel,
        ),
      );
    }
    return _FixedSizeFlightChild(layoutSize: layoutSize, child: child);
  }

  static _VideoDetailHeroChild _heroChild(Widget child) {
    if (child case final _VideoDetailHeroChild heroChild) {
      return heroChild;
    }
    return _VideoDetailHeroChild(
      borderRadius: BorderRadius.zero,
      isDetailTarget: false,
      child: child,
    );
  }

  static Size _contextSize(BuildContext context) {
    final renderObject = context.findRenderObject();
    if (renderObject is RenderBox && renderObject.hasSize) {
      return renderObject.size;
    }
    return Size.zero;
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
    required Widget child,
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
        child: child,
      ),
    );
  }
}

class _VideoDetailMediaHeroSource extends StatefulWidget {
  const _VideoDetailMediaHeroSource({
    required this.borderRadius,
    required this.child,
  });

  final BorderRadiusGeometry borderRadius;
  final Widget child;

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
      child: widget.child,
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
  }) : assert(playerSurfaceOpacity >= 0 && playerSurfaceOpacity <= 1),
       assert(
         navigationSurfaceOpacity >= 0 && navigationSurfaceOpacity <= 1,
       ),
       assert(detailSurfaceOpacity >= 0 && detailSurfaceOpacity <= 1),
       assert(
         recommendationSurfaceOpacity >= 0 && recommendationSurfaceOpacity <= 1,
       ),
       assert(recommendationCount >= 0);

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
    final colorScheme = Theme.of(context).colorScheme;
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
    required this.child,
  });

  final BorderRadiusGeometry borderRadius;
  final bool isDetailTarget;
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

class _FixedSizeFlightChild extends StatelessWidget {
  const _FixedSizeFlightChild({
    required this.layoutSize,
    required this.child,
    this.alignment = Alignment.center,
  });

  final Size layoutSize;
  final Widget child;
  final AlignmentGeometry alignment;

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
            alignment: alignment,
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
      _drawBar(
        canvas,
        Rect.fromLTWH(12, centerY - 5, 42, 10),
        primaryPaint,
      );
      _drawBar(
        canvas,
        Rect.fromLTWH(72, centerY - 5, 48, 10),
        subtlePaint,
      );
      _drawBar(
        canvas,
        Rect.fromLTWH(math.max(132.0, rect.right - 106), centerY - 4, 52, 8),
        subtlePaint,
      );
      canvas
        ..drawCircle(
          Offset(rect.right - 25, centerY),
          9,
          primaryPaint,
        )
        ..drawRect(
          Rect.fromLTWH(12, rect.bottom - 2, 42, 2),
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
    final contentTop = top + padding;
    final coverHeight = math.min(
      153.0,
      math.max(0.0, size.height - contentTop),
    );
    final coverWidth = math.min(115.0, math.max(0.0, size.width * 0.32));
    final actionTop = contentTop + coverHeight + 6;
    final episodeTop = showActions
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
          RRect.fromRectAndRadius(coverRect, const Radius.circular(6)),
          _thumbnailPaint(detailSurfaceOpacity),
        );

        final infoX = coverRect.right + 10;
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
        if (showActions) {
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

    _paintEpisodeRows(canvas, size, episodeTop);
  }

  void _paintLocalBody(Canvas canvas, Size size, double top) {
    final bodyRect = _sectionRect(size, top, size.height);
    _paintSection(canvas, bodyRect, detailSurfaceOpacity, () {
      const padding = VideoDetailLayoutMetrics.horizontalPadding;
      final primaryPaint = _skeletonPaint(detailSurfaceOpacity);
      final subtlePaint = _subtlePaint(detailSurfaceOpacity);
      var y = top;
      for (var index = 0; index < recommendationCount; index++) {
        if (y >= size.height) {
          break;
        }
        final thumbnailRect = Rect.fromLTWH(padding, y + 5, 160, 100);
        canvas.drawRRect(
          RRect.fromRectAndRadius(thumbnailRect, Style.imgRadius),
          _thumbnailPaint(detailSurfaceOpacity),
        );
        final textX = thumbnailRect.right + 10;
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
        y += 112;
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
    const count = 6;
    final itemWidth = rect.width / count;
    for (var index = 0; index < count; index++) {
      final centerX = rect.left + itemWidth * (index + 0.5);
      canvas.drawCircle(Offset(centerX, rect.top + 13), 9, iconPaint);
      _drawBar(
        canvas,
        Rect.fromCenter(
          center: Offset(centerX, rect.top + 33),
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
    const padding = VideoDetailLayoutMetrics.horizontalPadding;
    final primaryPaint = _skeletonPaint(recommendationSurfaceOpacity);
    final subtlePaint = _subtlePaint(recommendationSurfaceOpacity);
    const cardHeight = Grid.videoCardHMainAxisExtent;
    final maxCrossAxisExtent = math.max(1.0, Grid.smallCardWidth * 2);
    final crossAxisCount = math.max(
      1,
      (size.width / maxCrossAxisExtent).ceil(),
    );
    final tileWidth = size.width / crossAxisCount;
    for (var index = 0; index < recommendationCount; index++) {
      final row = index ~/ crossAxisCount;
      final column = index % crossAxisCount;
      final y = top + row * (cardHeight + Grid.videoCardHMainAxisSpacing);
      if (y >= size.height) {
        break;
      }
      final tileLeft = column * tileWidth;
      final contentWidth = math.max(0.0, tileWidth - 2 * padding);
      final thumbnailWidth = math.min(
        160.0,
        math.max(0.0, contentWidth - 96),
      );
      final thumbnailHeight = math.min(
        cardHeight - 10,
        thumbnailWidth / Style.aspectRatio,
      );
      final thumbnailRect = Rect.fromLTWH(
        tileLeft + padding,
        y + (cardHeight - thumbnailHeight) / 2,
        thumbnailWidth,
        thumbnailHeight,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(thumbnailRect, const Radius.circular(6)),
        _thumbnailPaint(recommendationSurfaceOpacity),
      );
      final textX = thumbnailRect.right + 10;
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
      const itemWidth = 140.0;
      const itemHeight = 60.0;
      const itemStride = 150.0;
      final y = top + 42;
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
        textScaler != oldDelegate.textScaler ||
        titleStyle != oldDelegate.titleStyle;
  }
}
