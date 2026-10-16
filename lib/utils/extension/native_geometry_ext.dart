import 'package:flutter/widgets.dart' show Offset, Orientation, Rect, Size;
import 'package:nativeapi/nativeapi.dart'
    as nativeapi
    show Point, Rectangle, Size;

extension NativePointConversions on nativeapi.Point {
  Offset toOffset() => Offset(x, y);
}

extension NativeSizeConversions on nativeapi.Size {
  Size toSize() => Size(width, height);
}

extension NativeRectangleConversions on nativeapi.Rectangle {
  Rect toRect() => Rect.fromLTWH(x, y, width, height);
}

extension NativeSizeOrientation on nativeapi.Size {
  Orientation get orientation => height > width ? .portrait : .landscape;
}

extension NativeRectangleSize on nativeapi.Rectangle {
  nativeapi.Size get size => nativeapi.Size(width: width, height: height);
}
