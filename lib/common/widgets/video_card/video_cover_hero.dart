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
      transitionOnUserGestures: true,
      placeholderBuilder: _buildPlaceholder,
      child: ClipRRect(
        borderRadius: borderRadius,
        child: child,
      ),
    );
  }
}
