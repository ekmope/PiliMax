import 'package:flutter/material.dart';

Widget buttonLoadingIndicator({
  double size = 16,
  double strokeWidth = 2,
  Color? color,
}) {
  return SizedBox.square(
    dimension: size,
    child: CircularProgressIndicator(strokeWidth: strokeWidth, color: color),
  );
}

class LoadingButtonChild extends StatelessWidget {
  const LoadingButtonChild({
    super.key,
    required this.isLoading,
    required this.child,
    this.size = 16,
    this.strokeWidth = 2,
    this.color,
  });

  final bool isLoading;
  final Widget child;
  final double size;
  final double strokeWidth;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return buttonLoadingIndicator(
        size: size,
        strokeWidth: strokeWidth,
        color: color,
      );
    }
    return child;
  }
}
