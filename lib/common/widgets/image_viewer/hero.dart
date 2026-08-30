import 'package:flutter/widgets.dart';

Widget fromHero({
  required Object tag,
  required Widget child,
  bool transitionOnUserGestures = true,
}) => Hero(
  tag: tag,
  transitionOnUserGestures: transitionOnUserGestures,
  createRectTween: createEndRectTween,
  child: child,
);

RectTween createEndRectTween(Rect? begin, Rect? end) {
  // Keep the actual source and destination bounds. A synthetic centered rect
  // would make predictive-back start with a small image in the middle of the
  // screen instead of returning directly to the source thumbnail.
  return RectTween(begin: begin, end: end);
}
