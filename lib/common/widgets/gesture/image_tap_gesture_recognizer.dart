import 'package:flutter/gestures.dart'
    show TapGestureRecognizer, PointerDownEvent, PointerUpEvent;

/// Tap recognizer that exposes its release timestamp for double-tap filtering.
class ImageTapGestureRecognizer extends TapGestureRecognizer {
  ImageTapGestureRecognizer({
    super.debugOwner,
    super.supportedDevices,
    super.allowedButtonsFilter,
    super.preAcceptSlopTolerance,
    super.postAcceptSlopTolerance,
  });

  Duration timeStamp = Duration.zero;

  @override
  void handleTapUp({
    required PointerDownEvent down,
    required PointerUpEvent up,
  }) {
    timeStamp = up.timeStamp;
    super.handleTapUp(down: down, up: up);
  }
}
