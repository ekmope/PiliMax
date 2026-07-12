import 'dart:math' as math;

import 'package:PiliMax/common/style.dart';
import 'package:PiliMax/common/widgets/video_card/video_transition_registry.dart';
import 'package:PiliMax/pages/video/video_layout_metrics.dart';

import 'package:flutter/gestures.dart' show kPrimaryButton;
import 'package:flutter/material.dart';

/// Expands a complete video card into the lightweight detail-page shell.
///
/// Both ends opt in to user-gesture transitions so Android predictive back can
/// drive the same flight. Keep the target child lightweight; the default
/// [VideoDetailHeroShell] intentionally contains no player or scrolling state.
class VideoDetailHero extends StatefulWidget {
  const VideoDetailHero.source({
    super.key,
    required this.tag,
    required this.child,
    this.borderRadius = Style.mdRadius,
  }) : _isDetailTarget = false;

  const VideoDetailHero.target({
    super.key,
    required this.tag,
    this.child = const VideoDetailHeroShell(),
    this.borderRadius = BorderRadius.zero,
  }) : _isDetailTarget = true;

  final Object tag;
  final Widget child;
  final BorderRadiusGeometry borderRadius;
  final bool _isDetailTarget;

  @override
  State<VideoDetailHero> createState() => _VideoDetailHeroState();

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
        final isUnknownEntry =
            !isPop &&
            detailChild.child is VideoDetailHeroShell &&
            (detailChild.child as VideoDetailHeroShell).isVertical == null;
        final sourceOpacity = isPop
            ? _interval(flightProgress, 0.28, 0.88)
            : 1 -
                  _interval(
                    flightProgress,
                    isUnknownEntry ? 0.28 : 0.08,
                    isUnknownEntry ? 0.78 : 0.52,
                  );
        final detailOpacity = isPop
            ? 1 - _interval(flightProgress, 0.14, 0.78)
            : _interval(
                flightProgress,
                isUnknownEntry ? 0.55 : 0.16,
                isUnknownEntry ? 0.96 : 0.82,
              );

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
      return VideoDetailHeroShell(
        // Keep the live player/cover visible under every reverse flight. This
        // also avoids depending on gesture-state timing when predictive back
        // starts or gets cancelled.
        playerSurfaceOpacity: isPop ? 0 : shell.playerSurfaceOpacity,
        bodySurfaceOpacity: shell.bodySurfaceOpacity,
        recommendationCount: shell.recommendationCount,
        isVertical: shell.isVertical,
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

  static double _interval(double value, double begin, double end) {
    if (value <= begin) {
      return 0;
    }
    if (value >= end) {
      return 1;
    }
    return Curves.easeInOutCubic.transform((value - begin) / (end - begin));
  }

  Widget _buildPlaceholder(BuildContext context, Size heroSize, Widget child) {
    return SizedBox.fromSize(size: heroSize);
  }
}

class _VideoDetailHeroState extends State<VideoDetailHero> {
  final GlobalKey _sourceBoundaryKey = GlobalKey();
  VideoTransitionRegistration? _registration;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _registration ??= _registerSource();
  }

  @override
  void didUpdateWidget(VideoDetailHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tag != widget.tag ||
        oldWidget._isDetailTarget != widget._isDetailTarget ||
        oldWidget.borderRadius != widget.borderRadius) {
      _syncRegistration();
    }
  }

  void _syncRegistration() {
    _registration?.dispose();
    _registration = _registerSource();
  }

  VideoTransitionRegistration? _registerSource() {
    if (widget._isDetailTarget) {
      return null;
    }
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
    final child = widget._isDetailTarget
        ? widget.child
        : RepaintBoundary(key: _sourceBoundaryKey, child: widget.child);
    final hero = Hero(
      tag: widget.tag,
      curve: Curves.linear,
      reverseCurve: Curves.linear,
      createRectTween: VideoDetailHero._createRectTween,
      flightShuttleBuilder: VideoDetailHero._flightShuttleBuilder,
      transitionOnUserGestures: true,
      placeholderBuilder: widget._buildPlaceholder,
      child: _VideoDetailHeroChild(
        borderRadius: widget.borderRadius,
        isDetailTarget: widget._isDetailTarget,
        child: child,
      ),
    );
    if (widget._isDetailTarget) {
      return hero;
    }
    return Listener(
      onPointerDown: (event) {
        if (event.buttons & kPrimaryButton != 0) {
          _registration?.prepare();
        }
      },
      child: hero,
    );
  }
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
    this.bodySurfaceOpacity = 1,
    this.recommendationCount = 4,
    this.isVertical,
  }) : assert(playerSurfaceOpacity >= 0 && playerSurfaceOpacity <= 1),
       assert(bodySurfaceOpacity >= 0 && bodySurfaceOpacity <= 1),
       assert(recommendationCount >= 0);

  final double playerSurfaceOpacity;
  final double bodySurfaceOpacity;
  final int recommendationCount;
  final bool? isVertical;

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
              bodySurfaceOpacity: bodySurfaceOpacity,
              recommendationCount: recommendationCount,
              isVertical: isVertical,
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
  const _FixedSizeFlightChild({required this.layoutSize, required this.child});

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
    required this.bodySurfaceOpacity,
    required this.recommendationCount,
    required this.isVertical,
  });

  final ColorScheme colorScheme;
  final double playerSurfaceOpacity;
  final double bodySurfaceOpacity;
  final int recommendationCount;
  final bool? isVertical;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }

    canvas
      ..save()
      ..clipRect(Offset.zero & size);

    final playerHeight = switch (isVertical) {
      true => videoDetailPlayerHeight(size, isVertical: true),
      false => videoDetailPlayerHeight(size, isVertical: false),
      null => (size.width / Style.aspectRatio16x9).clamp(
        size.height * 0.2,
        size.height * 0.36,
      ),
    };
    final playerRect = Rect.fromLTWH(0, 0, size.width, playerHeight);
    if (playerSurfaceOpacity > 0) {
      canvas.drawRect(
        playerRect,
        Paint()
          ..color = (isVertical == null ? colorScheme.surface : Colors.black)
              .withValues(alpha: playerSurfaceOpacity),
      );
    }

    final bodyRect = Rect.fromLTRB(
      0,
      playerHeight,
      size.width,
      size.height,
    );
    if (bodySurfaceOpacity > 0) {
      canvas.drawRect(
        bodyRect,
        Paint()
          ..color = colorScheme.surface.withValues(
            alpha: bodySurfaceOpacity,
          ),
      );
      _paintBody(canvas, size, playerHeight);
    }

    canvas.restore();
  }

  void _paintBody(Canvas canvas, Size size, double top) {
    final scale = (size.width / 400).clamp(0.68, 1.15);
    final padding = 14 * scale;
    final gap = 10 * scale;
    final avatarDiameter = 38 * scale;
    final skeletonPaint = Paint()
      ..color = colorScheme.onSurfaceVariant.withValues(
        alpha: 0.17 * bodySurfaceOpacity,
      );
    final subtlePaint = Paint()
      ..color = colorScheme.onSurfaceVariant.withValues(
        alpha: 0.11 * bodySurfaceOpacity,
      );
    final cardPaint = Paint()
      ..color = colorScheme.surfaceContainerLow.withValues(
        alpha: 0.9 * bodySurfaceOpacity,
      );
    final thumbnailPaint = Paint()
      ..color = colorScheme.surfaceContainerHighest.withValues(
        alpha: 0.9 * bodySurfaceOpacity,
      );

    var y = top + padding;
    canvas.drawCircle(
      Offset(padding + avatarDiameter / 2, y + avatarDiameter / 2),
      avatarDiameter / 2,
      skeletonPaint,
    );

    final authorLineX = padding + avatarDiameter + gap;
    final authorLineWidth = math.max(0.0, size.width - authorLineX - padding);
    _drawBar(
      canvas,
      Rect.fromLTWH(
        authorLineX,
        y + 5 * scale,
        authorLineWidth * 0.46,
        11 * scale,
      ),
      skeletonPaint,
    );
    _drawBar(
      canvas,
      Rect.fromLTWH(
        authorLineX,
        y + 24 * scale,
        authorLineWidth * 0.3,
        8 * scale,
      ),
      subtlePaint,
    );

    y += avatarDiameter + 13 * scale;
    final contentWidth = math.max(0.0, size.width - 2 * padding);
    _drawBar(
      canvas,
      Rect.fromLTWH(padding, y, contentWidth * 0.92, 12 * scale),
      skeletonPaint,
    );
    y += 20 * scale;
    _drawBar(
      canvas,
      Rect.fromLTWH(padding, y, contentWidth * 0.66, 10 * scale),
      subtlePaint,
    );
    y += 28 * scale;

    final cardRadius = Radius.circular(7 * scale);
    final cardHeight = 88 * scale;
    final thumbnailWidth = math.min(contentWidth * 0.36, 126 * scale);
    final thumbnailHeight = math.min(
      cardHeight - 12 * scale,
      thumbnailWidth / Style.aspectRatio,
    );

    for (var index = 0; index < recommendationCount; index++) {
      if (y >= size.height) {
        break;
      }
      final cardRect = Rect.fromLTWH(
        padding,
        y,
        contentWidth,
        cardHeight,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(cardRect, cardRadius),
        cardPaint,
      );

      final thumbnailRect = Rect.fromLTWH(
        padding + 6 * scale,
        y + (cardHeight - thumbnailHeight) / 2,
        thumbnailWidth,
        thumbnailHeight,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(thumbnailRect, Radius.circular(6 * scale)),
        thumbnailPaint,
      );

      final textX = thumbnailRect.right + gap;
      final textWidth = math.max(0.0, cardRect.right - textX - 8 * scale);
      _drawBar(
        canvas,
        Rect.fromLTWH(
          textX,
          y + 14 * scale,
          textWidth * 0.94,
          10 * scale,
        ),
        skeletonPaint,
      );
      _drawBar(
        canvas,
        Rect.fromLTWH(
          textX,
          y + 33 * scale,
          textWidth * 0.72,
          9 * scale,
        ),
        skeletonPaint,
      );
      _drawBar(
        canvas,
        Rect.fromLTWH(
          textX,
          y + 61 * scale,
          textWidth * 0.42,
          7 * scale,
        ),
        subtlePaint,
      );
      y += cardHeight + 10 * scale;
    }
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
        bodySurfaceOpacity != oldDelegate.bodySurfaceOpacity ||
        recommendationCount != oldDelegate.recommendationCount ||
        isVertical != oldDelegate.isVertical;
  }
}
