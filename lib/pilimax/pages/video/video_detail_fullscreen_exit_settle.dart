final class VideoDetailFullScreenExitSettleTracker {
  VideoDetailFullScreenExitSettleTracker({this.stableFramesRequired = 2})
    : assert(stableFramesRequired > 0);

  final int stableFramesRequired;

  int? _layoutSignature;
  int _stableFrames = 0;

  bool observe({
    required int layoutSignature,
    required bool targetLayoutReady,
  }) {
    if (!targetLayoutReady) {
      reset();
      return false;
    }
    if (_layoutSignature == layoutSignature) {
      _stableFrames++;
    } else {
      _layoutSignature = layoutSignature;
      _stableFrames = 1;
    }
    return _stableFrames >= stableFramesRequired;
  }

  void reset() {
    _layoutSignature = null;
    _stableFrames = 0;
  }
}
