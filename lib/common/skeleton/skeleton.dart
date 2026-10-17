import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

class Skeleton extends StatefulWidget {
  final Widget child;

  const Skeleton({super.key, required this.child});

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Color? _color;
  late List<Color> _colors;
  final _matrix = Matrix4.identity();
  bool _animationEnabled = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController.unbounded(vsync: this);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final color = ColorScheme.of(context).surface.withAlpha(10);
    if (_color != color) {
      _color = color;
      _colors = [Colors.transparent, color, color, Colors.transparent];
    }

    final shouldAnimate =
        TickerMode.valuesOf(context).enabled &&
        !(MediaQuery.maybeOf(context)?.disableAnimations ?? false);
    if (shouldAnimate == _animationEnabled) return;

    _animationEnabled = shouldAnimate;
    if (shouldAnimate) {
      _controller.repeat(
        min: -0.5,
        max: 1.5,
        period: const Duration(milliseconds: 1000),
      );
    } else {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_animationEnabled) return widget.child;

    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (Rect bounds) {
          final width = bounds.width;
          final height = bounds.height;
          _matrix[12] = width * _controller.value;
          return ui.Gradient.linear(
            Offset(0, 0.35 * height),
            Offset(width, 0.95 * height),
            _colors,
            const [0.1, 0.3, 0.5, 0.7],
            TileMode.clamp,
            _matrix.storage,
          );
        },
        child: child,
      ),
    );
  }
}
