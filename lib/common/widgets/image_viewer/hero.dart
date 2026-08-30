import 'package:flutter/widgets.dart';

Widget fromHero({
  required Object tag,
  required Widget child,
  bool transitionOnUserGestures = false,
}) => Hero(
  tag: tag,
  transitionOnUserGestures: transitionOnUserGestures,
  createRectTween: createEndRectTween,
  child: child,
);

RectTween createEndRectTween(Rect? begin, Rect? end) {
  // Keep the actual source and destination bounds. Centering the destination
  // size inside the source rect makes predictive-back briefly show a small
  // image in the middle of the screen before it fades out.
  return RectTween(begin: begin, end: end);
}
