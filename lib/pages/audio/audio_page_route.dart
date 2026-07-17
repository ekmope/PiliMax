import 'package:flutter/material.dart';
import 'package:get/get.dart';

const audioPageExitTransitionDuration = Duration(milliseconds: 300);

/// Keeps GetX's audio-page lifecycle while providing a dedicated exit motion.
final class AudioPageRoute<T> extends GetPageRoute<T> {
  bool _usingExitTransition = false;

  AudioPageRoute({
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
  Duration get transitionDuration => audioPageExitTransitionDuration;

  @override
  Duration get reverseTransitionDuration => audioPageExitTransitionDuration;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (animation.status == AnimationStatus.reverse) {
      _usingExitTransition = true;
    }
    if (!_usingExitTransition) {
      return super.buildTransitions(
        context,
        animation,
        secondaryAnimation,
        child,
      );
    }

    final exitAnimation = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
    );

    return FadeTransition(
      opacity: exitAnimation,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.96, end: 1).animate(exitAnimation),
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.04),
            end: Offset.zero,
          ).animate(exitAnimation),
          child: child,
        ),
      ),
    );
  }
}
