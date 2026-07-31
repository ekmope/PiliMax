import 'package:flutter/material.dart';

class VoteDecoration extends Decoration {
  const VoteDecoration({
    required this.color,
    required this.percentage,
    required this.border,
    required this.borderRadius,
  });

  final Color color;
  final double percentage;
  final BoxBorder border;
  final BorderRadius borderRadius;

  @override
  EdgeInsetsGeometry get padding => border.dimensions;

  @override
  Path getClipPath(Rect rect, TextDirection textDirection) {
    return Path()..addRRect(borderRadius.resolve(textDirection).toRRect(rect));
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other.runtimeType != runtimeType) {
      return false;
    }
    return other is VoteDecoration &&
        other.color == color &&
        other.border == border &&
        other.borderRadius == borderRadius &&
        other.percentage == percentage;
  }

  @override
  int get hashCode => Object.hash(color, border, borderRadius, percentage);

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) {
    assert(onChanged != null);
    return _VoteDecorationPainter(this, onChanged);
  }
}

class _VoteDecorationPainter extends BoxPainter {
  _VoteDecorationPainter(this._decoration, super.onChanged);

  final VoteDecoration _decoration;

  Paint? _cachedBackgroundPaint;
  Paint _getBackgroundPaint() {
    if (_cachedBackgroundPaint == null) {
      final paint = Paint()..color = _decoration.color;
      _cachedBackgroundPaint = paint;
    }

    return _cachedBackgroundPaint!;
  }

  void _paintBox(
    Canvas canvas,
    Rect rect,
    Paint paint,
    TextDirection? textDirection,
    bool isComplete,
  ) {
    if (isComplete) {
      canvas.drawRRect(
        _decoration.borderRadius.resolve(textDirection).toRRect(rect),
        paint,
      );
    } else {
      final borderRadius = BorderRadius.horizontal(
        left: _decoration.borderRadius.topLeft,
      );
      canvas.drawRRect(
        borderRadius.resolve(textDirection).toRRect(rect),
        paint,
      );
    }
  }

  void _paintBackgroundColor(
    Canvas canvas,
    Rect rect,
    TextDirection? textDirection,
    bool isComplete,
  ) {
    _paintBox(
      canvas,
      rect,
      _getBackgroundPaint(),
      textDirection,
      isComplete,
    );
  }

  double _calculateAdjustedSide(BorderSide side) {
    if (side.color.a == 1 && side.style == .solid) {
      return side.strokeInset;
    }
    return 0;
  }

  Rect _adjustedRectOnOutlinedBorder(Rect rect, TextDirection? textDirection) {
    final border = _decoration.border as Border;

    final EdgeInsets insets =
        EdgeInsets.fromLTRB(
          _calculateAdjustedSide(border.left),
          _calculateAdjustedSide(border.top),
          _calculateAdjustedSide(border.right),
          _calculateAdjustedSide(border.bottom),
        ) /
        2;

    return Rect.fromLTRB(
      rect.left + insets.left,
      rect.top + insets.top,
      rect.right - insets.right,
      rect.bottom - insets.bottom,
    );
  }

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    assert(configuration.size != null);
    final Rect rect = offset & configuration.size!;
    final TextDirection? textDirection = configuration.textDirection;
    final percentage = _decoration.percentage.clamp(0.0, 1.0).toDouble();
    if (percentage > 0) {
      final contentRect = _adjustedRectOnOutlinedBorder(rect, textDirection);
      if (!contentRect.isEmpty) {
        final bgRect = percentage == 1
            ? contentRect
            : Rect.fromLTWH(
                contentRect.left,
                contentRect.top,
                contentRect.width * percentage,
                contentRect.height,
              );
        if (!bgRect.isEmpty) {
          _paintBackgroundColor(
            canvas,
            bgRect,
            textDirection,
            percentage == 1,
          );
        }
      }
    }
    _decoration.border.paint(
      canvas,
      rect,
      shape: .rectangle,
      borderRadius: _decoration.borderRadius.resolve(textDirection),
      textDirection: configuration.textDirection,
    );
  }

  @override
  String toString() {
    return 'VotePainter for $_decoration';
  }
}
