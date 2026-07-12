import 'dart:math' as math;

import 'package:PiliMax/common/style.dart';

import 'package:flutter/widgets.dart';

enum VideoDetailSkeletonVariant { ugc, pgc, pugv, local }

/// Geometry shared by the real portrait detail page and its paint-only shell.
abstract final class VideoDetailLayoutMetrics {
  static const double tabBarHeight = 45;
  static const double horizontalPadding = Style.safeSpace;
  static const double introTopPadding = 10;
  static const double ownerHeight = 35;
  static const double sectionGap = 8;
  static const double actionHeight = 48;
  static const double seasonPanelHeight = 48;
  static const double pagesPanelHeight = 79;
  static const double relatedDividerTopPadding = Style.safeSpace;
  static const double relatedDividerHeight = 1;
  static const double relatedTopPadding = 7;

  static double entryPlayerHeight(
    Size viewport, {
    required bool? isVertical,
  }) => switch (isVertical) {
    true => videoDetailPlayerHeight(viewport, isVertical: true),
    false => videoDetailPlayerHeight(viewport, isVertical: false),
    null => (viewport.width / Style.aspectRatio16x9).clamp(
      viewport.height * 0.2,
      viewport.height * 0.36,
    ),
  };

  static double entryPlayerBottom(
    Size viewport, {
    required bool? isVertical,
    required double topInset,
  }) => math.min(
    viewport.height,
    topInset + entryPlayerHeight(viewport, isVertical: isVertical),
  );
}

double videoDetailPlayerHeight(Size viewport, {required bool isVertical}) {
  if (isVertical) {
    return math.max(viewport.longestSide * 0.65, viewport.shortestSide);
  }
  return viewport.shortestSide / Style.aspectRatio16x9;
}
