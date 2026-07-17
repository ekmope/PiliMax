import 'package:PiliMax/pages/video/video_detail_transition_timing.dart';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Keeps the video Hero and entry overlay on one fixed route timeline.
///
/// This remains a [GetPageRoute] so GetX routing arguments, observers, bindings,
/// disposal reporting and route restoration keep their existing lifecycle.
final class VideoDetailPageRoute<T> extends GetPageRoute<T> {
  VideoDetailPageRoute({
    required GetPage<dynamic> definition,
    required Map<dynamic, dynamic> arguments,
  }) : super(
         page: definition.page,
         parameter: definition.parameters,
         settings: RouteSettings(name: definition.name, arguments: arguments),
         binding: definition.binding,
         bindings: definition.bindings,
         routeName: definition.name,
         title: definition.title,
         maintainState: definition.maintainState,
         middlewares: definition.middlewares,
       );

  @override
  Duration get transitionDuration => videoDetailTransitionDuration;

  @override
  Duration get reverseTransitionDuration => videoDetailTransitionDuration;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return Theme.of(context).pageTransitionsTheme.buildTransitions<T>(
      this,
      context,
      animation,
      secondaryAnimation,
      child,
    );
  }
}
