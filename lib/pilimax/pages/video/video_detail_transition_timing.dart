import 'package:flutter/animation.dart';

/// Shared timeline for the video detail Hero, route, entry skeleton and
/// skeleton-to-detail reveal.
///
/// 400 ms maps to 24, 36 and 48 refresh intervals at 60, 90 and 120 Hz.
const videoDetailTransitionDuration = Duration(milliseconds: 400);

/// Skeleton/profile work should finish shortly after the shared geometry.
const videoDetailRevealDuration = Duration(milliseconds: 180);
const videoDetailProfileTransitionDuration = Duration(milliseconds: 120);
const videoDetailMaximumPostTransitionHold = Duration(milliseconds: 600);

/// Programmatic Android back stays deliberate but is shorter than entry.
const videoDetailProgrammaticExitDuration = Duration(milliseconds: 360);

const videoDetailCommitTailMinDuration = Duration(milliseconds: 160);
const videoDetailCommitTailMaxDuration = Duration(milliseconds: 280);
const videoDetailCancelTailMinDuration = Duration(milliseconds: 140);
const videoDetailCancelTailMaxDuration = Duration(milliseconds: 240);

/// The outgoing detail surface hands off during the final 15% of its path.
const videoDetailSourceHandoffStart = 0.85;
const videoDetailSourceHandoffEnd = 0.98;

/// The live player follows the outgoing page first, then separates from the
/// card body and settles into the source media rectangle.
const videoDetailMediaMorphStart = 0.70;
const videoDetailMediaMorphEnd = 0.98;

/// Keep the live frame authoritative until the media geometry is nearly at
/// rest. The geometry gate in the transition can delay this handoff further.
const videoDetailMediaHandoffStart = 0.94;

/// Fade the source thumbnail over a live player during the final part of a
/// return. This protects the card handoff from a platform texture that has
/// already gone black while the route is still being transformed.
const videoDetailReturnMediaCoverStart = 0.70;
const videoDetailReturnMediaCoverEnd = 0.95;

/// The real detail subtree owns its reveal timing. Media readiness only
/// controls the cover layered over the player rectangle.
bool videoDetailEntryCanReveal({required bool detailLayoutReady}) =>
    detailLayoutReady;

bool videoDetailPlayerHandoffCanRelease({
  required bool playerVisualReady,
  required bool forceRelease,
  required bool detailLayoutReady,
}) => detailLayoutReady || forceRelease;

/// A newly-created desktop video surface can already be advancing while
/// media-kit's Flutter first-frame Future remains pending beneath the route's
/// temporary cover. Reused controllers also cannot use that one-shot Future
/// for a new source. Both cases validate through playback progress followed by
/// the stable-surface gate.
bool videoDetailInitialSurfaceUsesPlaybackProgress({
  required bool isDesktop,
  required bool reusesVideoController,
}) => isDesktop || reusesVideoController;

/// Desktop fullscreen APIs can keep the same Flutter viewport and player
/// rectangle. Mobile rotation still requires an observed geometry change so a
/// pre-rotation surface is never accepted as the settled target.
bool videoDetailFullscreenTransitionObserved({
  required bool requireGeometryChange,
  required bool fullScreenActive,
  required bool metricsChanged,
  required bool viewportChanged,
  required bool playerRectChanged,
}) =>
    metricsChanged ||
    viewportChanged ||
    playerRectChanged ||
    (!requireGeometryChange && fullScreenActive);

double videoDetailReturnMediaCoverOpacity(double exitProgress) {
  final normalized =
      ((exitProgress - videoDetailReturnMediaCoverStart) /
              (videoDetailReturnMediaCoverEnd -
                  videoDetailReturnMediaCoverStart))
          .clamp(0.0, 1.0)
          .toDouble();
  return Curves.easeInOutCubic.transform(normalized);
}

Duration videoDetailCommitTailDuration(double exitProgress) {
  final remaining = 1 - _unitInterval(exitProgress);
  final scaledMilliseconds =
      (videoDetailProgrammaticExitDuration.inMilliseconds * remaining).round();
  return Duration(
    milliseconds: scaledMilliseconds
        .clamp(
          videoDetailCommitTailMinDuration.inMilliseconds,
          videoDetailCommitTailMaxDuration.inMilliseconds,
        )
        .toInt(),
  );
}

Duration videoDetailCancelTailDuration(double exitProgress) {
  final distance = _unitInterval(exitProgress);
  final scaledMilliseconds =
      (videoDetailProgrammaticExitDuration.inMilliseconds * distance).round();
  return Duration(
    milliseconds: scaledMilliseconds
        .clamp(
          videoDetailCancelTailMinDuration.inMilliseconds,
          videoDetailCancelTailMaxDuration.inMilliseconds,
        )
        .toInt(),
  );
}

double _unitInterval(double value) => value.clamp(0.0, 1.0).toDouble();
