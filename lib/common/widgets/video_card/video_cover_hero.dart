import 'package:PiliMax/common/style.dart';
import 'package:PiliMax/common/widgets/video_card/video_detail_hero.dart';

import 'package:flutter/material.dart';

class VideoCoverHero extends StatelessWidget {
  const VideoCoverHero({
    super.key,
    required this.tag,
    required this.child,
    this.borderRadius = Style.mdRadius,
  });

  final Object tag;
  final Widget child;
  final BorderRadiusGeometry borderRadius;

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
    final fromIsDetail = VideoDetailHero.isDetailTargetHeroChild(
      fromHero.child,
    );
    final toIsDetail = VideoDetailHero.isDetailTargetHeroChild(toHero.child);
    if (fromIsDetail || toIsDetail) {
      return _detailFlightShuttleBuilder(
        animation: animation,
        flightDirection: flightDirection,
        fromHero: fromHero,
        toHero: toHero,
        fromIsDetail: fromIsDetail,
      );
    }
    final beginRadius = _heroBorderRadius(fromHero.child);
    final endRadius = _heroBorderRadius(toHero.child);
    final shuttleChild = switch (flightDirection) {
      HeroFlightDirection.push => _heroClipChild(fromHero.child),
      HeroFlightDirection.pop => _heroClipChild(toHero.child),
    };
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final radiusProgress = switch (flightDirection) {
          HeroFlightDirection.push => animation.value,
          HeroFlightDirection.pop => 1 - animation.value,
        };
        return ClipRRect(
          borderRadius:
              BorderRadiusGeometry.lerp(beginRadius, endRadius, radiusProgress)
              ?? endRadius,
          child: _fillFlightBounds(shuttleChild),
        );
      },
    );
  }

  static Widget _detailFlightShuttleBuilder({
    required Animation<double> animation,
    required HeroFlightDirection flightDirection,
    required Hero fromHero,
    required Hero toHero,
    required bool fromIsDetail,
  }) {
    final isPop = flightDirection == HeroFlightDirection.pop;
    final sourceHeroChild = fromIsDetail ? toHero.child : fromHero.child;
    final detailHeroChild = fromIsDetail ? fromHero.child : toHero.child;
    final sourceRadius = _heroBorderRadius(sourceHeroChild);
    final detailRadius = VideoDetailHero.borderRadiusOfHeroChild(
      detailHeroChild,
    );
    final sourceChild = _heroClipChild(sourceHeroChild);
    final detailChild = VideoDetailHero.detailFlightSurfaceForHeroChild(
      detailHeroChild,
      isPop: isPop,
    );

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
                    detailRadius,
                    sourceRadius,
                    progress,
                  )
                : BorderRadiusGeometry.lerp(
                    sourceRadius,
                    detailRadius,
                    progress,
                  )) ??
            detailRadius;
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
                  child: _fillFlightBounds(detailChild),
                ),
                Opacity(
                  opacity: sourceOpacity,
                  child: _fillFlightBounds(sourceChild),
                ),
              ],
            ),
          ),
        );
      },
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

  static BorderRadiusGeometry _heroBorderRadius(Widget child) {
    return child is ClipRRect ? child.borderRadius : BorderRadius.zero;
  }

  static Widget _heroClipChild(Widget child) {
    if (child is ClipRRect && child.child != null) {
      return child.child!;
    }
    return child;
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
    return ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox(
        width: heroSize.width,
        height: heroSize.height,
      ),
    );
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
      child: ClipRRect(
        borderRadius: borderRadius,
        child: child,
      ),
    );
  }
}
