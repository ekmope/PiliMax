import 'dart:math' as math;

import 'package:PiliMax/common/style.dart';
import 'package:PiliMax/common/widgets/video_card/video_card_h_layout_metrics.dart';

import 'package:flutter/widgets.dart';

enum VideoDetailSkeletonVariant { ugc, pgc, pugv, local }

/// Geometry shared by the real portrait detail page and its paint-only shell.
abstract final class VideoDetailLayoutMetrics {
  static const double tabBarHeight = 45;
  static const int defaultTabCount = 2;
  static const double navigationTabLabelHorizontalPadding = 10;
  static const double navigationSendDanmakuWidth = 64;
  static const double navigationSendDanmakuHeight = 32;
  static const double navigationDanmakuToggleExtent = 38;
  static const double navigationRightPadding = 14;
  static const double navigationRightControlsWidth =
      navigationSendDanmakuWidth +
      navigationDanmakuToggleExtent +
      navigationRightPadding;
  static const int navigationActionRegionFlex = 1;

  static const double horizontalPadding = Style.safeSpace;
  static const double introTopPadding = 10;
  static const double ownerHeight = 35;
  static const double sectionGap = 8;

  static const double actionHeight = 48;
  static const double actionIconBoxExtent = 28;
  static const double actionIconGlyphExtent = 18;
  static const double actionEstimatedLabelHeight = 14;
  static const double actionContentHeight =
      actionIconBoxExtent + actionEstimatedLabelHeight;
  static const double actionContentTop =
      (actionHeight - actionContentHeight) / 2;
  static const double actionIconCenterOffset =
      actionContentTop + actionIconBoxExtent / 2;
  static const double actionLabelCenterOffset =
      actionContentTop + actionIconBoxExtent + actionEstimatedLabelHeight / 2;
  static const int ugcActionCount = 6;
  static const int ugcAiActionCount = 7;
  static const int pgcActionCount = 5;
  static const int pugvActionCount = 0;
  static const int localActionCount = 0;

  static const double seasonPanelHeight = 48;
  static const double pagesPanelHeight = 79;

  static const double pgcContentTopPadding = Style.safeSpace;
  static const double pgcCoverWidth = 115;
  static const double pgcCoverHeight = 153;
  static const double pgcCoverRadius = 10;
  static const double pgcInfoGap = 10;
  static const double pgcActionTopGap = 6;
  static const double episodePanelHeaderHeight = 42;
  static const double episodeItemWidth = 140;
  static const double episodeItemHeight = 60;
  static const double episodeItemStride = 150;
  static const double episodePanelHeight =
      episodePanelHeaderHeight + episodeItemHeight;

  static const double localTopPadding = 7;
  static const double localItemHeight = VideoCardHLayoutMetrics.itemHeight;
  static const double localItemSpacing =
      VideoCardHLayoutMetrics.mainAxisSpacing;
  static const double localItemExtent = localItemHeight + localItemSpacing;

  static const double relatedDividerTopPadding = Style.safeSpace;
  static const double relatedDividerHeight = 1;
  static const double relatedTopPadding = 7;
  static const double relatedCardHeight = VideoCardHLayoutMetrics.itemHeight;
  static const double relatedCardSpacing =
      VideoCardHLayoutMetrics.mainAxisSpacing;

  static int navigationTabRegionFlex(int tabCount) => tabCount >= 3 ? 2 : 1;

  static int portraitTabCount({
    required VideoDetailSkeletonVariant variant,
    required bool showReply,
  }) =>
      variant == VideoDetailSkeletonVariant.local ? 1 : 1 + (showReply ? 1 : 0);

  static int actionCountFor(
    VideoDetailSkeletonVariant variant, {
    bool includeAiAction = false,
  }) => switch (variant) {
    VideoDetailSkeletonVariant.ugc =>
      includeAiAction ? ugcAiActionCount : ugcActionCount,
    VideoDetailSkeletonVariant.pgc => pgcActionCount,
    VideoDetailSkeletonVariant.pugv => pugvActionCount,
    VideoDetailSkeletonVariant.local => localActionCount,
  };

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

  static Rect entryPlayerRect(
    Size viewport, {
    required bool? isVertical,
    required double topInset,
  }) {
    final top = topInset.clamp(0.0, viewport.height).toDouble();
    final height = entryPlayerHeight(
      viewport,
      isVertical: isVertical,
    ).clamp(0.0, viewport.height - top).toDouble();
    return Rect.fromLTWH(0, top, viewport.width, height);
  }

  static double entryPlayerBottom(
    Size viewport, {
    required bool? isVertical,
    required double topInset,
  }) => entryPlayerRect(
    viewport,
    isVertical: isVertical,
    topInset: topInset,
  ).bottom;
}

double videoDetailPlayerHeight(Size viewport, {required bool isVertical}) {
  if (isVertical) {
    return math.max(viewport.longestSide * 0.65, viewport.shortestSide);
  }
  return viewport.shortestSide / Style.aspectRatio16x9;
}
