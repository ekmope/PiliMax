import 'package:flutter/material.dart';
import 'package:get/get.dart';

class VideoDetailTransition extends CustomTransition {
  const VideoDetailTransition();

  static const Curve _curve = Curves.easeOutCubic;
  static const double _beginScale = 0.985;

  @override
  Widget buildTransition(
    BuildContext context,
    Curve? curve,
    Alignment? alignment,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curvedAnimation = CurvedAnimation(
      parent: animation,
      curve: _curve,
      reverseCurve: Curves.easeOut,
    );
    return FadeTransition(
      opacity: curvedAnimation,
      child: ScaleTransition(
        scale: Tween<double>(begin: _beginScale, end: 1).animate(curvedAnimation),
        child: child,
      ),
    );
  }
}