import 'package:PiliMax/common/style.dart';

import 'package:flutter/material.dart';

class VideoDetailHero extends StatelessWidget {
  const VideoDetailHero.source({
    super.key,
    required this.tag,
    required this.child,
    this.borderRadius = Style.mdRadius,
  }) : _isDetailTarget = false;

  const VideoDetailHero.target({
    super.key,
    required this.tag,
    required this.child,
  }) : borderRadius = BorderRadius.zero,
       _isDetailTarget = true;

  final Object tag;
  final Widget child;
  final BorderRadiusGeometry borderRadius;
  final bool _isDetailTarget;

  static Tween<Rect?> _createRectTween(Rect? begin, Rect? end) =>
      MaterialRectArcTween(begin: begin, end: end);

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
    final isPop = flightDirection == HeroFlightDirection.pop;
    final sourceChild = fromChild.isDetailTarget ? toChild : fromChild;
    final detailChild = fromChild.isDetailTarget ? fromChild : toChild;

    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final progress = switch (flightDirection) {
          HeroFlightDirection.push => animation.value,
          HeroFlightDirection.pop => 1 - animation.value,
        };
        final radius =
            (isPop
                ? BorderRadiusGeometry.lerp(
                    detailChild.borderRadius,
                    sourceChild.borderRadius,
                    progress,
                  )
                : BorderRadiusGeometry.lerp(
                    sourceChild.borderRadius,
                    detailChild.borderRadius,
                    progress,
                  )) ??
            detailChild.borderRadius;
        final detailOpacity = isPop
            ? 1 - _interval(progress, 0.08, 0.72)
            : _interval(progress, 0.10, 0.88);
        final sourceOpacity = isPop
            ? _interval(progress, 0.24, 1)
            : 1 - _interval(progress, 0, 0.45);

        return RepaintBoundary(
          child: ClipRRect(
            borderRadius: radius,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Opacity(
                  opacity: detailOpacity,
                  child: _fillFlightBounds(
                    _detailFlightSurface(detailChild.child, isPop: isPop),
                  ),
                ),
                Opacity(
                  opacity: sourceOpacity,
                  child: _fillFlightBounds(sourceChild.child),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static Widget _detailFlightSurface(Widget child, {required bool isPop}) {
    if (child is VideoDetailHeroShell) {
      return VideoDetailHeroShell(
        playerSurfaceOpacity: isPop ? 0.08 : 1,
        bodySurfaceOpacity: isPop ? 0.88 : 1,
      );
    }
    return child;
  }

  static bool isDetailTargetHeroChild(Widget child) {
    return child is _VideoDetailHeroChild && child.isDetailTarget;
  }

  static BorderRadiusGeometry borderRadiusOfHeroChild(Widget child) {
    return _heroChild(child).borderRadius;
  }

  static Widget detailFlightSurfaceForHeroChild(
    Widget child, {
    required bool isPop,
  }) {
    return _detailFlightSurface(_heroChild(child).child, isPop: isPop);
  }

  static _VideoDetailHeroChild _heroChild(Widget child) {
    if (child is _VideoDetailHeroChild) {
      return child;
    }
    return _VideoDetailHeroChild(
      borderRadius: BorderRadius.zero,
      isDetailTarget: false,
      child: child,
    );
  }

  static Widget _fillFlightBounds(Widget child) {
    return LayoutBuilder(
      builder: (context, constraints) => SizedBox(
        width: constraints.hasBoundedWidth ? constraints.maxWidth : null,
        height: constraints.hasBoundedHeight ? constraints.maxHeight : null,
        child: child,
      ),
    );
  }

  static double _interval(double value, double begin, double end) {
    if (value <= begin) {
      return 0;
    }
    if (value >= end) {
      return 1;
    }
    return Curves.easeOutCubic.transform((value - begin) / (end - begin));
  }

  Widget _buildPlaceholder(BuildContext context, Size heroSize, Widget child) {
    return SizedBox(width: heroSize.width, height: heroSize.height);
  }

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: tag,
      curve: Curves.linear,
      reverseCurve: Curves.linear,
      createRectTween: _createRectTween,
      flightShuttleBuilder: _flightShuttleBuilder,
      transitionOnUserGestures: true,
      placeholderBuilder: _buildPlaceholder,
      child: _VideoDetailHeroChild(
        borderRadius: borderRadius,
        isDetailTarget: _isDetailTarget,
        child: child,
      ),
    );
  }
}

class VideoDetailHeroShell extends StatelessWidget {
  const VideoDetailHeroShell({
    super.key,
    this.playerSurfaceOpacity = 1,
    this.bodySurfaceOpacity = 1,
  });

  final double playerSurfaceOpacity;
  final double bodySurfaceOpacity;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final mediaSize = MediaQuery.sizeOf(context);
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : mediaSize.width;
        final height = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : mediaSize.height;
        final playerHeight = (width / Style.aspectRatio).clamp(
          height * 0.26,
          height * 0.46,
        ).toDouble();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: playerHeight,
              width: double.infinity,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(
                    alpha: playerSurfaceOpacity,
                  ),
                ),
              ),
            ),
            if (height > 120)
              _VideoDetailTabOutline(
                colorScheme: colorScheme,
                opacity: bodySurfaceOpacity,
              ),
            if (height > 180)
              Expanded(
                child: _VideoDetailBodySurface(
                  colorScheme: colorScheme,
                  opacity: bodySurfaceOpacity,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _VideoDetailTabOutline extends StatelessWidget {
  const _VideoDetailTabOutline({
    required this.colorScheme,
    required this.opacity,
  });

  final ColorScheme colorScheme;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: opacity),
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.35),
          ),
        ),
      ),
      child: Row(
        children: [
          _TabMarker(colorScheme: colorScheme, width: 46, opacity: opacity),
          const SizedBox(width: 18),
          _TabMarker(
            colorScheme: colorScheme,
            width: 46,
            opacity: opacity * 0.62,
          ),
        ],
      ),
    );
  }
}

class _VideoDetailBodySurface extends StatelessWidget {
  const _VideoDetailBodySurface({
    required this.colorScheme,
    required this.opacity,
  });

  final ColorScheme colorScheme;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            colorScheme.surface.withValues(alpha: 0.96 * opacity),
            colorScheme.surface.withValues(alpha: 0.88 * opacity),
          ],
        ),
      ),
      child: const SizedBox.expand(),
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
  Widget build(BuildContext context) {
    if (isDetailTarget) {
      return child;
    }
    return ClipRRect(borderRadius: borderRadius, child: child);
  }
}

class _TabMarker extends StatelessWidget {
  const _TabMarker({
    required this.colorScheme,
    required this.width,
    required this.opacity,
  });

  final ColorScheme colorScheme;
  final double width;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 22,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          height: 3,
          decoration: BoxDecoration(
            color: colorScheme.primary.withValues(alpha: 0.42 * opacity),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}
