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
const videoDetailProgrammaticExitDuration = Duration(milliseconds: 320);

const videoDetailCommitTailMinDuration = Duration(milliseconds: 120);
const videoDetailCommitTailMaxDuration = Duration(milliseconds: 240);
const videoDetailCancelTailMinDuration = Duration(milliseconds: 100);
const videoDetailCancelTailMaxDuration = Duration(milliseconds: 220);

/// The outgoing detail surface hands off during the final 15% of its path.
const videoDetailSourceHandoffStart = 0.85;
const videoDetailSourceHandoffEnd = 0.98;

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
