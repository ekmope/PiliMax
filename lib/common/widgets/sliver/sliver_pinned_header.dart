/*
 * This file is part of PiliMax
 *
 * PiliMax is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * PiliMax is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with PiliMax.  If not, see <https://www.gnu.org/licenses/>.
 */

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show clampDouble;
import 'package:flutter/rendering.dart'
    show RenderSliverSingleBoxAdapter, SliverGeometry;
import 'package:flutter/widgets.dart';

/// ref [SliverPersistentHeader]
class SliverPinnedHeader extends SingleChildRenderObjectWidget {
  const SliverPinnedHeader({
    super.key,
    required Widget super.child,
    this.backgroundColor,
    this.backgroundGradient,
    this.gradientBoundsSize,
  });

  final Color? backgroundColor;
  final Gradient? backgroundGradient;
  final Size? gradientBoundsSize;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderSliverPinnedHeader(
        backgroundColor: backgroundColor,
        backgroundGradient: backgroundGradient,
        gradientBoundsSize: gradientBoundsSize,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderSliverPinnedHeader renderObject,
  ) {
    renderObject
      ..backgroundColor = backgroundColor
      ..backgroundGradient = backgroundGradient
      ..gradientBoundsSize = gradientBoundsSize;
  }
}

class RenderSliverPinnedHeader extends RenderSliverSingleBoxAdapter {
  RenderSliverPinnedHeader({
    required this._backgroundColor,
    this._backgroundGradient,
    this._gradientBoundsSize,
  });

  Color? _backgroundColor;
  set backgroundColor(Color? value) {
    if (_backgroundColor == value) return;
    _backgroundColor = value;
    if (_isPinned) markNeedsPaint();
  }

  Gradient? _backgroundGradient;
  set backgroundGradient(Gradient? value) {
    if (_backgroundGradient == value) return;
    _backgroundGradient = value;
    _backgroundShader = null;
    if (_isPinned) markNeedsPaint();
  }

  Size? _gradientBoundsSize;
  Shader? _backgroundShader;
  set gradientBoundsSize(Size? value) {
    if (_gradientBoundsSize == value) return;
    _gradientBoundsSize = value;
    _backgroundShader = null;
    if (_isPinned) markNeedsPaint();
  }

  bool _isPinned = false;

  @override
  void performLayout() {
    final constraints = this.constraints;
    child!.layout(constraints.asBoxConstraints(), parentUsesSize: true);
    final double childExtent = child!.size.height;
    final double effectiveRemainingPaintExtent = math.max(
      0,
      constraints.remainingPaintExtent - constraints.overlap,
    );
    final double layoutExtent = clampDouble(
      childExtent - constraints.scrollOffset,
      0.0,
      effectiveRemainingPaintExtent,
    );
    _isPinned = constraints.overlap > 0.0 || constraints.scrollOffset > 0.0;
    geometry = SliverGeometry(
      scrollExtent: childExtent,
      paintOrigin: constraints.overlap,
      paintExtent: math.min(childExtent, effectiveRemainingPaintExtent),
      layoutExtent: layoutExtent,
      maxPaintExtent: childExtent,
      maxScrollObstructionExtent: childExtent,
      cacheExtent: layoutExtent > 0.0
          ? -constraints.cacheOrigin + layoutExtent
          : layoutExtent,
      hasVisualOverflow: false,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child != null && geometry!.visible) {
      if (_isPinned && _backgroundColor != null) {
        final size = child!.size;
        final rect = Rect.fromLTWH(
          offset.dx,
          offset.dy - 2,
          size.width,
          size.height + 2,
        );
        context.canvas.drawRect(rect, Paint()..color = _backgroundColor!);
      } else if (_isPinned &&
          _backgroundGradient != null &&
          _gradientBoundsSize != null) {
        final backgroundGradient = _backgroundGradient!;
        final boundsSize = _gradientBoundsSize!;
        final size = child!.size;
        final rect = Rect.fromLTWH(
          offset.dx,
          offset.dy - 2,
          size.width,
          size.height + 2,
        );
        final shaderBounds = Rect.fromLTWH(
          0,
          0,
          boundsSize.width,
          boundsSize.height,
        );
        context.canvas.drawRect(
          rect,
          Paint()
            ..shader = _backgroundShader ??= backgroundGradient.createShader(
              shaderBounds,
            ),
        );
      }
      context.paintChild(child!, offset);
    }
  }

  @override
  double childMainAxisPosition(RenderBox child) => 0.0;

  @override
  bool hitTestSelf({
    required double mainAxisPosition,
    required double crossAxisPosition,
  }) => true;
}
