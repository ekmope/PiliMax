import 'dart:math' as math;

import 'package:PiliMax/common/style.dart';
import 'package:PiliMax/pilimax/common/widgets/video_card/video_card_h_layout_metrics.dart';
import 'package:PiliMax/models_new/video/video_detail/data.dart';
import 'package:PiliMax/models_new/video/video_detail/episode.dart';
import 'package:PiliMax/utils/storage_pref.dart';

import 'package:flutter/widgets.dart';

enum VideoDetailSkeletonVariant { ugc, pgc, pugv, local }

/// The page arrangement used while a detail route is entering.
///
/// This is intentionally separate from the video's [isVertical] metadata:
/// landscape detail pages use the normal 16:9 split by default, while the
/// centered vertical arrangement is opt-in on every platform.
enum VideoDetailEntryPageLayout {
  portrait,
  landscape,
  verticalExpanded,
}

final class VideoDetailEntryLayout {
  const VideoDetailEntryLayout({
    required this.pageLayout,
    required this.playerRect,
  });

  final VideoDetailEntryPageLayout pageLayout;
  final Rect playerRect;

  bool get isPortrait => pageLayout == VideoDetailEntryPageLayout.portrait;
}

final class UgcSeasonPanelSelection {
  const UgcSeasonPanelSelection({
    required this.seasonCid,
    required this.sectionIndex,
    required this.episodes,
  });

  final int seasonCid;
  final int sectionIndex;
  final List<EpisodeItem> episodes;
}

int? ugcSeasonPanelInitialCid(
  VideoDetailData videoDetail,
  int? currentCid,
) {
  final pages = videoDetail.pages;
  if (pages?.isNotEmpty == true) {
    return videoDetail.listOrder.isDesc ? pages!.last.cid : pages!.first.cid;
  }
  return currentCid != null && currentCid != 0 ? currentCid : videoDetail.cid;
}

UgcSeasonPanelSelection? resolveUgcSeasonPanel(
  VideoDetailData? videoDetail,
  int? seasonCid,
) {
  if (videoDetail == null || seasonCid == null) {
    return null;
  }
  final sections = videoDetail.ugcSeason?.sections;
  if (sections == null || sections.isEmpty) {
    return null;
  }
  for (var sectionIndex = 0; sectionIndex < sections.length; sectionIndex++) {
    final episodes = sections[sectionIndex].episodes;
    if (episodes?.isNotEmpty != true) {
      continue;
    }
    if (episodes!.any((episode) => episode.cid == seasonCid)) {
      return UgcSeasonPanelSelection(
        seasonCid: seasonCid,
        sectionIndex: sectionIndex,
        episodes: episodes,
      );
    }
  }
  return null;
}

bool hasRenderableUgcSeasonPanel(
  VideoDetailData? videoDetail,
  int? currentCid,
) {
  if (videoDetail == null) {
    return false;
  }
  return resolveUgcSeasonPanel(
        videoDetail,
        ugcSeasonPanelInitialCid(videoDetail, currentCid),
      ) !=
      null;
}

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
  static const double ugcTitleFontSize = 16;
  static const int ugcTitleMaxLines = 2;

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
  static const double seasonPanelTopPadding = 8;
  static const double seasonPanelHorizontalInset = 2;
  static const double seasonPanelRadius = 6;
  static const double seasonPanelContentHorizontalPadding = 8;
  static const double seasonPanelContentVerticalPadding = 12;
  static const double seasonPanelSurfaceHeight =
      seasonPanelHeight - seasonPanelTopPadding;
  static const double seasonPanelLeadingGap = 15;
  static const double seasonPanelStatusIconExtent = 12;
  static const double seasonPanelStatusGap = 10;
  static const double seasonPanelCountPlaceholderWidth = 30;
  static const double seasonPanelArrowGap = 6;
  static const double seasonPanelArrowExtent = 13;
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
  static const double relatedPreviewHeight =
      relatedDividerHeight + relatedTopPadding + relatedCardHeight;

  /// Keeps the first related-video skeleton visible below a tall vertical
  /// player without moving it above the detail body.
  static double portraitRecommendationTop({
    required Size viewport,
    required double bodyTop,
    required double naturalTop,
    required bool reserveVisiblePreview,
  }) {
    if (!reserveVisiblePreview) {
      return naturalTop;
    }
    final minimumTop = bodyTop.clamp(0.0, viewport.height).toDouble();
    final previewTop = math.max(
      minimumTop,
      viewport.height - relatedPreviewHeight,
    );
    return naturalTop.clamp(minimumTop, previewTop).toDouble();
  }

  /// Includes a partially visible final row, matching the scrollable sidebar.
  static int landscapeRecommendationCountForSidebarHeight(
    double sidebarHeight,
  ) {
    final availableHeight = math.max(
      0.0,
      sidebarHeight - tabBarHeight - relatedTopPadding,
    );
    if (availableHeight <= 0) {
      return 0;
    }
    return (availableHeight / (relatedCardHeight + relatedCardSpacing)).ceil();
  }

  /// The information pane below a standard landscape player, or to the left
  /// of a vertically expanded player. The painter and entry cover use this
  /// geometry so their safe-area bounds stay aligned with the detail page.
  static Rect landscapeInfoPanelRect(
    Size viewport,
    VideoDetailEntryLayout entryLayout, {
    required EdgeInsets pagePadding,
  }) {
    final panelLeft = pagePadding.left.clamp(0.0, viewport.width).toDouble();
    final panelRight = (viewport.width - pagePadding.right)
        .clamp(panelLeft, viewport.width)
        .toDouble();
    final playerRect = entryLayout.playerRect;
    return switch (entryLayout.pageLayout) {
      VideoDetailEntryPageLayout.landscape => Rect.fromLTRB(
        panelLeft,
        playerRect.bottom,
        playerRect.right.clamp(panelLeft, panelRight).toDouble(),
        viewport.height,
      ),
      VideoDetailEntryPageLayout.verticalExpanded => Rect.fromLTRB(
        panelLeft,
        playerRect.top,
        playerRect.left.clamp(panelLeft, panelRight).toDouble(),
        viewport.height,
      ),
      VideoDetailEntryPageLayout.portrait => Rect.zero,
    };
  }

  /// The tab and related-video pane on the right of a landscape detail page.
  static Rect landscapeSidebarPanelRect(
    Size viewport,
    VideoDetailEntryLayout entryLayout, {
    required EdgeInsets pagePadding,
  }) {
    final panelLeft = pagePadding.left.clamp(0.0, viewport.width).toDouble();
    final panelRight = (viewport.width - pagePadding.right)
        .clamp(panelLeft, viewport.width)
        .toDouble();
    final playerRect = entryLayout.playerRect;
    return switch (entryLayout.pageLayout) {
      VideoDetailEntryPageLayout.landscape ||
      VideoDetailEntryPageLayout.verticalExpanded => Rect.fromLTRB(
        playerRect.right.clamp(panelLeft, panelRight).toDouble(),
        playerRect.top,
        panelRight,
        viewport.height,
      ),
      VideoDetailEntryPageLayout.portrait => Rect.zero,
    };
  }

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

  static double ugcTitleTop(double bodyTop) =>
      bodyTop + introTopPadding + ownerHeight + sectionGap;

  static Rect ugcTitleRect(
    Size viewport, {
    required double bodyTop,
    required double titleHeight,
  }) {
    final top = ugcTitleTop(bodyTop);
    final width = math.max(0.0, viewport.width - 2 * horizontalPadding);
    final height = titleHeight
        .clamp(0.0, math.max(0.0, viewport.height - top))
        .toDouble();
    return Rect.fromLTWH(horizontalPadding, top, width, height);
  }

  static Rect seasonPanelSurfaceRect(Rect slot) => Rect.fromLTWH(
    slot.left + seasonPanelHorizontalInset,
    slot.top + seasonPanelTopPadding,
    math.max(0.0, slot.width - 2 * seasonPanelHorizontalInset),
    seasonPanelSurfaceHeight,
  );

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

  /// Resolves the entry geometry shared by the Hero target, skeleton, and
  /// player-handoff cover.
  ///
  /// [isPortrait] describes the page/window layout rather than the video's
  /// content orientation. Test-only callers can override the preference input
  /// without mutating global storage.
  static VideoDetailEntryLayout entryLayout(
    Size viewport, {
    required bool? isVertical,
    required double topInset,
    EdgeInsets? pagePadding,
    bool isPortrait = true,
    bool? enableVerticalExpand,
  }) {
    final padding = pagePadding ?? EdgeInsets.only(top: topInset);
    final top = padding.top.clamp(0.0, viewport.height).toDouble();
    final left = padding.left.clamp(0.0, viewport.width).toDouble();
    final right = padding.right
        .clamp(0.0, math.max(0.0, viewport.width - left))
        .toDouble();
    final bottom = padding.bottom
        .clamp(0.0, math.max(0.0, viewport.height - top))
        .toDouble();
    final shouldExpandVertical =
        !isPortrait &&
        isVertical == true &&
        (enableVerticalExpand ?? Pref.enableVerticalExpand);
    final pageLayout = isPortrait
        ? VideoDetailEntryPageLayout.portrait
        : shouldExpandVertical
        ? VideoDetailEntryPageLayout.verticalExpanded
        : VideoDetailEntryPageLayout.landscape;
    final availableHeight = math.max(0.0, viewport.height - top).toDouble();
    final landscapeWidth = math
        .max(0.0, viewport.width - left - right)
        .toDouble();
    final landscapeHeight = math.max(0.0, availableHeight - bottom).toDouble();
    final playerRect = switch (pageLayout) {
      VideoDetailEntryPageLayout.portrait => () {
        final height = entryPlayerHeight(
          viewport,
          isVertical: isVertical,
        ).clamp(0.0, availableHeight).toDouble();
        return Rect.fromLTWH(0, top, viewport.width, height);
      }(),
      VideoDetailEntryPageLayout.verticalExpanded =>
        _verticalExpandedPlayerRect(
          left: left,
          top: top,
          availableWidth: landscapeWidth,
          availableHeight: landscapeHeight,
        ),
      VideoDetailEntryPageLayout.landscape => _landscapePlayerRect(
        left: left,
        top: top,
        availableWidth: landscapeWidth,
        availableHeight: landscapeHeight,
      ),
    };
    return VideoDetailEntryLayout(
      pageLayout: pageLayout,
      playerRect: playerRect,
    );
  }

  static Rect entryPlayerRect(
    Size viewport, {
    required bool? isVertical,
    required double topInset,
    EdgeInsets? pagePadding,
    bool isPortrait = true,
    bool? enableVerticalExpand,
  }) => entryLayout(
    viewport,
    isVertical: isVertical,
    topInset: topInset,
    pagePadding: pagePadding,
    isPortrait: isPortrait,
    enableVerticalExpand: enableVerticalExpand,
  ).playerRect;

  static Rect _landscapePlayerRect({
    required double left,
    required double top,
    required double availableWidth,
    required double availableHeight,
  }) {
    final width = _landscapePlayerWidth(availableWidth, availableHeight);
    final height = math.min(
      width / Style.aspectRatio16x9,
      availableHeight,
    );
    return Rect.fromLTWH(left, top, width, height);
  }

  static Rect _verticalExpandedPlayerRect({
    required double left,
    required double top,
    required double availableWidth,
    required double availableHeight,
  }) {
    final width = math.min(
      availableHeight / Style.aspectRatio16x9,
      availableWidth,
    );
    return Rect.fromLTWH(
      left + (availableWidth - width) / 2,
      top,
      width,
      availableHeight,
    );
  }

  static double _landscapePlayerWidth(
    double availableWidth,
    double availableHeight,
  ) {
    if (availableWidth <= 0) {
      return 0;
    }
    var width =
        ((availableHeight / availableWidth * 1.08).clamp(0.5, 0.7) *
                availableWidth)
            .toDouble();
    if (availableWidth >= 560) {
      width =
          availableWidth -
          (availableWidth - width).clamp(280.0, 425.0).toDouble();
    }
    return width.clamp(0.0, availableWidth).toDouble();
  }

  static double entryPlayerBottom(
    Size viewport, {
    required bool? isVertical,
    required double topInset,
    EdgeInsets? pagePadding,
    bool isPortrait = true,
    bool? enableVerticalExpand,
  }) => entryPlayerRect(
    viewport,
    isVertical: isVertical,
    topInset: topInset,
    pagePadding: pagePadding,
    isPortrait: isPortrait,
    enableVerticalExpand: enableVerticalExpand,
  ).bottom;
}

double videoDetailPlayerHeight(Size viewport, {required bool isVertical}) {
  if (isVertical) {
    return math.max(viewport.longestSide * 0.65, viewport.shortestSide);
  }
  return viewport.shortestSide / Style.aspectRatio16x9;
}
