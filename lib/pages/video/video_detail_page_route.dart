import 'package:PiliMax/pages/video/video_detail_back_progress.dart';
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
       ) {
    _backProgress = ensureVideoDetailBackProgress(arguments).retain();
  }

  late final VideoDetailBackProgressController _backProgress;

  @override
  Duration get transitionDuration => videoDetailTransitionDuration;

  @override
  Duration get reverseTransitionDuration => videoDetailProgrammaticExitDuration;

  @override
  void handleCancelBackGesture() {
    final animationController = controller;
    final navigatorState = navigator;
    if (animationController == null || !isCurrent) {
      navigatorState?.didStopUserGesture();
      return;
    }
    final exitProgress = 1 - animationController.value;
    // The transition driver owns the visual ease; keep route time linear so
    // Hero/overlay consumers can use the published progress without re-easing.
    final tail = animationController.animateTo(
      animationController.upperBound,
      duration: videoDetailCancelTailDuration(exitProgress),
      curve: Curves.linear,
    );
    _stopUserGestureWhenComplete(navigatorState, tail);
  }

  @override
  void handleCommitBackGesture() {
    final animationController = controller;
    final navigatorState = navigator;
    if (animationController == null || !isCurrent) {
      navigatorState?.didStopUserGesture();
      return;
    }
    final exitProgress = 1 - animationController.value;
    final duration = videoDetailCommitTailDuration(exitProgress);

    if (popDisposition == RoutePopDisposition.doNotPop) {
      onPopInvokedWithResult(false, null);
      final restore = animationController.animateTo(
        animationController.upperBound,
        duration: videoDetailCancelTailDuration(exitProgress),
        curve: Curves.linear,
      );
      _stopUserGestureWhenComplete(navigatorState, restore);
      return;
    }

    navigatorState?.pop();
    final popAccepted = !isCurrent || animationController.isAnimating;
    if (!popAccepted) {
      final restore = animationController.animateTo(
        animationController.upperBound,
        duration: videoDetailCancelTailDuration(exitProgress),
        curve: Curves.linear,
      );
      _stopUserGestureWhenComplete(navigatorState, restore);
      return;
    }
    if (animationController.isDismissed) {
      navigatorState?.didStopUserGesture();
      return;
    }
    final tail = animationController.animateBack(
      animationController.lowerBound,
      duration: duration,
      curve: Curves.linear,
    );
    _stopUserGestureWhenComplete(navigatorState, tail);
  }

  void _stopUserGestureWhenComplete(
    NavigatorState? navigatorState,
    TickerFuture future,
  ) {
    var stopped = false;
    void stop() {
      if (stopped) {
        return;
      }
      stopped = true;
      navigatorState?.didStopUserGesture();
    }

    future.whenCompleteOrCancel(stop);
  }

  @override
  void dispose() {
    _backProgress.release();
    super.dispose();
  }

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
