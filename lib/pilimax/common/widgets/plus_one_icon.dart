import 'package:flutter/material.dart';

class PlusOneIcon extends StatelessWidget {
  const PlusOneIcon({
    super.key,
    this.color,
    this.size = 20,
  });

  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final foreground =
        color ??
        IconTheme.of(context).color ??
        ColorScheme.of(context).onSurface;
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: foreground, width: 1.2),
          borderRadius: const BorderRadius.all(Radius.circular(3)),
        ),
        child: Center(
          child: Text(
            '+1',
            style: TextStyle(
              color: foreground,
              fontSize: size * 0.55,
              height: 1,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
