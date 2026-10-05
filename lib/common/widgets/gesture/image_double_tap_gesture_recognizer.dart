import 'package:flutter/gestures.dart'
    show
        DoubleTapGestureRecognizer,
        GestureBinding,
        PointerCancelEvent,
        PointerDownEvent,
        PointerEvent,
        PointerUpEvent;

/// Double-tap recognizer that exposes the completion timestamp to the viewer.
/// This lets a single-tap close action ignore the second tap in a double tap.
class ImageDoubleTapGestureRecognizer extends DoubleTapGestureRecognizer {
  ImageDoubleTapGestureRecognizer({
    super.debugOwner,
    super.supportedDevices,
    super.allowedButtonsFilter,
  });

  Duration timeStamp = Duration.zero;

  final Set<int> _trackedPointers = <int>{};

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    _trackedPointers.add(event.pointer);
    GestureBinding.instance.pointerRouter.addRoute(
      event.pointer,
      _handleTimestamp,
    );
  }

  void _handleTimestamp(PointerEvent event) {
    if (event is PointerUpEvent) {
      timeStamp = event.timeStamp;
      _stopTimestampTracking(event.pointer);
    } else if (event is PointerCancelEvent) {
      _stopTimestampTracking(event.pointer);
    }
  }

  void _stopTimestampTracking(int pointer) {
    if (_trackedPointers.remove(pointer)) {
      GestureBinding.instance.pointerRouter.removeRoute(
        pointer,
        _handleTimestamp,
      );
    }
  }

  @override
  void dispose() {
    for (final pointer in _trackedPointers.toList()) {
      _stopTimestampTracking(pointer);
    }
    super.dispose();
  }
}
