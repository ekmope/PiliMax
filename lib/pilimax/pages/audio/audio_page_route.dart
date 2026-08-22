import 'package:material_ui/material_ui.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:get/get.dart';
import 'package:PiliMax/utils/storage_pref.dart';

const audioPageExitTransitionDuration = Duration(milliseconds: 400);

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
         maintainState: definition.maintainState,
         middlewares: definition.middlewares,
       );

  @override
  Duration get reverseTransitionDuration => audioPageExitTransitionDuration;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // On Android, keep the framework predictive-back transition mounted for
    // the whole gesture. Switching to the custom reverse tree as soon as the
    // animation reports reverse breaks the gesture's progress/cancel path.
    if (defaultTargetPlatform == TargetPlatform.android &&
        Pref.enablePredictiveBack) {
      return super.buildTransitions(
        context,
        animation,
        secondaryAnimation,
        child,
      );
    }
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

    final reversedAnimation = ReverseAnimation(animation);
    final exitProgress = reversedAnimation.drive(
      CurveTween(curve: Curves.easeOutCubic),
    );

    return FadeTransition(
      opacity: Tween<double>(begin: 1, end: 0).animate(exitProgress),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: Offset.zero,
          end: const Offset(0.08, 0),
        ).animate(exitProgress),
        transformHitTests: false,
        child: ScaleTransition(
          scale: Tween<double>(begin: 1, end: 0.94).animate(exitProgress),
          alignment: Alignment.centerLeft,
          child: child,
        ),
      ),
    );
  }
}
