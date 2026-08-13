import 'dart:math' as math;

import 'package:PiliMax/pilimax/pages/video/video_layout_metrics.dart';
import 'package:flutter/widgets.dart';

/// Caches the two-line UGC title metric used by video-detail transition shells.
final class VideoDetailUgcTitleHeightCache {
  static const double fallbackHeight = 38;

  Object? _signature;
  double _height = fallbackHeight;
  int _debugLayoutCount = 0;

  @visibleForTesting
  int get debugLayoutCount => _debugLayoutCount;

  double resolve({
    required String? title,
    required double viewportWidth,
    required TextStyle style,
    required TextScaler textScaler,
    required TextDirection textDirection,
    double? override,
  }) {
    if (override != null) {
      return override;
    }
    if (title == null || title.isEmpty) {
      return fallbackHeight;
    }

    final finiteViewportWidth = viewportWidth.isFinite
        ? math.max(0.0, viewportWidth)
        : 0.0;
    final maxWidth = math.max(
      0.0,
      finiteViewportWidth - 2 * VideoDetailLayoutMetrics.horizontalPadding,
    );
    final signature = (title, maxWidth, style, textScaler, textDirection);
    if (signature == _signature) {
      return _height;
    }

    final painter = TextPainter(
      text: TextSpan(text: title, style: style),
      maxLines: 2,
      textDirection: textDirection,
      textScaler: textScaler,
    );
    try {
      painter.layout(maxWidth: maxWidth);
      _height = painter.height;
    } finally {
      painter.dispose();
    }
    _signature = signature;
    assert(() {
      _debugLayoutCount++;
      return true;
    }());
    return _height;
  }
}
