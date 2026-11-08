import 'package:flutter/widgets.dart';

/// Exposes the actual paint bounds of the app-wide background gradient.
///
/// Pinned slivers use these bounds to sample the same gradient coordinates as
/// the background, including when their viewport is kept alive offscreen.
class MainBackgroundGradientScope extends InheritedWidget {
  const MainBackgroundGradientScope({
    super.key,
    required this.boundsKey,
    required super.child,
  });

  final GlobalKey boundsKey;

  static MainBackgroundGradientScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MainBackgroundGradientScope>();

  @override
  bool updateShouldNotify(MainBackgroundGradientScope oldWidget) =>
      boundsKey != oldWidget.boundsKey;
}
