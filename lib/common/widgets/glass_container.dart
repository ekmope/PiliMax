import 'dart:ui' show ImageFilter;

import 'package:PiliMax/utils/storage_pref.dart';
import 'package:flutter/material.dart';

class GlassContainer extends StatelessWidget {
  const GlassContainer({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius = const BorderRadius.all(Radius.circular(24)),
    this.blurSigma = 18,
    this.opacity,
    this.borderOpacity,
    this.shadowOpacity,
    this.color,
    this.enabled,
    this.clipBehavior = Clip.antiAlias,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final BorderRadiusGeometry borderRadius;
  final double blurSigma;
  final double? opacity;
  final double? borderOpacity;
  final double? shadowOpacity;
  final Color? color;
  final bool? enabled;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final useGlass = enabled ?? Pref.enableLiquidGlass;
    final fillOpacity = opacity ?? (isDark ? 0.34 : 0.56);
    final borderAlpha = borderOpacity ?? (isDark ? 0.16 : 0.38);
    final shadowAlpha = shadowOpacity ?? (isDark ? 0.18 : 0.12);
    final fill = color ?? colorScheme.surface;

    Widget current = DecoratedBox(
      decoration: BoxDecoration(
        color: fill.withValues(alpha: useGlass ? fillOpacity : 0.96),
        borderRadius: borderRadius,
        border: Border.all(
          color: colorScheme.onSurface.withValues(alpha: borderAlpha),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: shadowAlpha),
            blurRadius: useGlass ? 22 : 8,
            spreadRadius: useGlass ? 1 : 0,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: padding == null ? child : Padding(padding: padding!, child: child),
    );

    current = ClipRRect(
      borderRadius: borderRadius,
      clipBehavior: clipBehavior,
      child: useGlass
          ? BackdropFilter(
              filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
              child: current,
            )
          : current,
    );

    if (margin case final margin?) {
      current = Padding(padding: margin, child: current);
    }
    return current;
  }
}
