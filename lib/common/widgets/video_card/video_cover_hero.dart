import 'package:PiliMax/common/style.dart';

import 'package:flutter/material.dart';

class VideoCoverHero extends StatelessWidget {
  const VideoCoverHero({
    super.key,
    required this.tag,
    required this.child,
    this.borderRadius = Style.mdRadius,
    this.transitionOnUserGestures = false,
    this.popFlightFadeIn = false,
  });

  final Object tag;
  final Widget child;
  final BorderRadiusGeometry borderRadius;
  final bool transitionOnUserGestures;
  final bool popFlightFadeIn;

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
    final beginRadius = _heroBorderRadius(fromHero.child);
    final endRadius = _heroBorderRadius(toHero.child);
    final fadeInOnPop =
        flightDirection == HeroFlightDirection.pop &&
        (_heroPopFlightFadeIn(fromHero.child) ||
            _heroPopFlightFadeIn(toHero.child));
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
        final opacity = fadeInOnPop
            ? Curves.easeOut.transform(
                (animation.value / 0.12).clamp(0.0, 1.0).toDouble(),
              )
            : 1.0;
        return Opacity(
          opacity: opacity,
          child: ClipRRect(
            borderRadius:
                BorderRadiusGeometry.lerp(
                  beginRadius,
                  endRadius,
                  radiusProgress,
                ) ??
                endRadius,
            child: _fillFlightBounds(shuttleChild),
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
    if (child is _VideoCoverHeroChild) {
      return child.borderRadius;
    }
    return child is ClipRRect ? child.borderRadius : BorderRadius.zero;
  }

  static bool _heroPopFlightFadeIn(Widget child) {
    return child is _VideoCoverHeroChild && child.popFlightFadeIn;
  }

  static Widget _heroClipChild(Widget child) {
    if (child is _VideoCoverHeroChild) {
      return child.child;
    }
    if (child is ClipRRect && child.child != null) {
      return child.child!;
    }
    return child;
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
      transitionOnUserGestures: transitionOnUserGestures,
      placeholderBuilder: _buildPlaceholder,
      child: _VideoCoverHeroChild(
        borderRadius: borderRadius,
        popFlightFadeIn: popFlightFadeIn,
        child: child,
      ),
    );
  }
}

class _VideoCoverHeroChild extends StatelessWidget {
  const _VideoCoverHeroChild({
    required this.borderRadius,
    required this.popFlightFadeIn,
    required this.child,
  });

  final BorderRadiusGeometry borderRadius;
  final bool popFlightFadeIn;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(borderRadius: borderRadius, child: child);
  }
}
