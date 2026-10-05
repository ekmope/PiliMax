/*
 * This file is part of PiliMax
 *
 * PiliMax is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import 'dart:math' as math;

import 'package:PiliMax/common/widgets/slotted_layout_helper.dart';
import 'package:flutter/rendering.dart' show BoxHitTestResult, TransformLayer;
import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart';

enum PlayerBarType { left, right, title }

class PlayerBar
    extends SlottedMultiChildRenderObjectWidget<PlayerBarType, RenderBox> {
  const PlayerBar({
    super.key,
    required this.left,
    required this.right,
    this.title,
  });

  final Widget left;
  final Widget right;
  final Widget? title;

  @override
  RenderPlayerBar createRenderObject(BuildContext context) => RenderPlayerBar();

  @override
  Widget? childForSlot(PlayerBarType slot) => switch (slot) {
    PlayerBarType.left => left,
    PlayerBarType.right => right,
    PlayerBarType.title => title,
  };

  @override
  Iterable<PlayerBarType> get slots => PlayerBarType.values;
}

class RenderPlayerBar extends RenderBox
    with
        SlottedContainerRenderObjectMixin<PlayerBarType, RenderBox>,
        SlottedLayoutMixin<PlayerBarType> {
  RenderBox get left => childForSlot(PlayerBarType.left)!;
  RenderBox get right => childForSlot(PlayerBarType.right)!;
  RenderBox? get title => childForSlot(PlayerBarType.title);

  @override
  Iterable<PlayerBarType> get slots => PlayerBarType.values;

  Matrix4? _transform;

  @override
  void performLayout() {
    _transform = null;
    final maxWidth = constraints.maxWidth;
    final title = this.title;
    if (title != null) {
      final loose = constraints.loosen();
      final left = this.left..layout(loose, parentUsesSize: true);
      final right = this.right..layout(loose, parentUsesSize: true);
      final leftSize = left.size;
      final rightSize = right.size;
      title.layout(
        BoxConstraints(
          maxWidth: math.max(0, maxWidth - leftSize.width - rightSize.width),
        ),
        parentUsesSize: true,
      );
      final titleSize = title.size;
      final height = math.max(
        math.max(leftSize.height, rightSize.height),
        titleSize.height,
      );
      setOffset(left, Offset(0, (height - leftSize.height) / 2));
      setOffset(
        right,
        Offset(maxWidth - rightSize.width, (height - rightSize.height) / 2),
      );
      setOffset(title, Offset(leftSize.width, (height - titleSize.height) / 2));
      size = constraints.constrainDimensions(maxWidth, height);
      return;
    }

    final loose = constraints.copyWith(maxWidth: double.infinity);
    final left = this.left..layout(loose, parentUsesSize: true);
    final right = this.right..layout(loose, parentUsesSize: true);
    final leftSize = left.size;
    final rightSize = right.size;
    final totalWidth = leftSize.width + rightSize.width;
    final height = math.max(leftSize.height, rightSize.height);
    size = constraints.constrainDimensions(maxWidth, height);
    setOffset(left, Offset(0, (height - leftSize.height) / 2));
    if (totalWidth <= maxWidth) {
      setOffset(
        right,
        Offset(maxWidth - rightSize.width, (height - rightSize.height) / 2),
      );
    } else {
      final scale = maxWidth / totalWidth;
      _transform = Matrix4.identity()
        ..translateByDouble(0, height * (1 - scale) / 2, 0, 1)
        ..scaleByDouble(scale, scale, scale, 1);
      setOffset(
        right,
        Offset(leftSize.width, (height - rightSize.height) / 2),
      );
    }
  }

  void defaultPaint(PaintingContext context, Offset offset) {
    for (final child in children) {
      context.paintChild(child, getOffset(child) + offset);
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_transform != null) {
      layer = context.pushTransform(
        needsCompositing,
        offset,
        _transform!,
        defaultPaint,
        oldLayer: layer as TransformLayer?,
      );
    } else {
      defaultPaint(context, offset);
      layer = null;
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return result.addWithPaintTransform(
      transform: _transform,
      position: position,
      hitTest: (result, position) =>
          super.hitTestChildren(result, position: position),
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final offset = getOffset(child);
    if (_transform != null) {
      transform
        ..translateByDouble(
          offset.dx * _transform!.storage[0],
          offset.dy,
          0,
          1,
        )
        ..multiply(_transform!);
    } else {
      transform.translateByDouble(offset.dx, offset.dy, 0, 1);
    }
  }
}
