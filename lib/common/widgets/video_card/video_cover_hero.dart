import 'package:PiliMax/common/style.dart';

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
    final beginRadius = _heroBorderRadius(fromHero.child);
    final endRadius = _heroBorderRadius(toHero.child);
    final shuttleChild = switch (flightDirection) {
      HeroFlightDirection.push => _heroClipChild(fromHero.child),
      HeroFlightDirection.pop => _heroClipChild(toHero.child),
    };
    return AnimatedBuilder(
      animation: animation,
      child: shuttleChild,
      builder: (context, child) => ClipRRect(
        borderRadius:
            BorderRadiusGeometry.lerp(beginRadius, endRadius, animation.value)
            ?? endRadius,
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

  Widget _buildPlaceholder(BuildContext context, Size heroSize, Widget child) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox(
        width: heroSize.width,
        height: heroSize.height,
        child: const ColoredBox(color: Colors.black),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: tag,
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
