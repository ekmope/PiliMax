import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart' show PredictiveBackEvent;

/// https://github.com/qq326646683/interactiveviewer_gallery

/// A [PageRoute] with a semi transparent background.
///
/// Similar to calling [showDialog] except it can be used with a [Navigator] to
/// show a [Hero] animation.
class HeroDialogRoute<T> extends PageRoute<T> {
  HeroDialogRoute({
    required this.pageBuilder,
    this.backGestureProgress,
    this.backGestureCommand,
  });

  final RoutePageBuilder pageBuilder;

  /// Advances [0,1] as the Android predictive-back gesture moves. Kept for
  /// callers that need to observe the gesture; the route animation and Hero
  /// flight now own the visual transition.
  final ValueNotifier<double>? backGestureProgress;

  /// 0 = idle, 1 = commit (pop), 2 = cancel (spring back).
  final ValueNotifier<int>? backGestureCommand;

  @override
  bool get opaque => false;

  @override
  bool get barrierDismissible => false;

  @override
  String? get barrierLabel => null;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 300);

  @override
  bool get maintainState => true;

  // The viewer contains a live image/video subtree. Do not replace it with a
  // route snapshot while a predictive-back or Hero flight is in progress.
  @override
  bool get allowSnapshotting => false;

  @override
  Color? get barrierColor => null;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // Fade the whole transparent viewer (mask + image) in/out. The mask must
    // fade, not scale/translate: the previous PredictiveBackPageTransitionsBuilder
    // shrank the entire route (black mask included) and slid it horizontally,
    // which read as "the viewer shrinks / fades from left to right".
    final curve = CurvedAnimation(parent: animation, curve: Curves.easeOut);
    return _PredictiveBackDetector(
      route: this,
      backGestureProgress: backGestureProgress,
      backGestureCommand: backGestureCommand,
      builder: (context) => FadeTransition(
        opacity: curve,
        child: child,
      ),
    );
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      child: pageBuilder(context, animation, secondaryAnimation),
    );
  }
}

/// Claims Android's predictive-back gesture for this custom [PageRoute]
/// without adding a page-scale transition.
///
/// [HeroDialogRoute] overrides [buildTransitions], so the framework does not
/// mount its own predictive-back gesture detector. Without one, an edge-swipe
/// back falls through to the non-predictive path and Android shows
/// "swipe again to go back" instead of popping on the first swipe.
class _PredictiveBackDetector extends StatefulWidget {
  const _PredictiveBackDetector({
    required this.route,
    required this.builder,
    this.backGestureProgress,
    this.backGestureCommand,
  });

  final PageRoute<dynamic> route;
  final WidgetBuilder builder;
  final ValueNotifier<double>? backGestureProgress;
  final ValueNotifier<int>? backGestureCommand;

  @override
  State<_PredictiveBackDetector> createState() =>
      _PredictiveBackDetectorState();
}

class _PredictiveBackDetectorState extends State<_PredictiveBackDetector>
    with WidgetsBindingObserver {
  bool get _enabled => widget.route.isCurrent && widget.route.popGestureEnabled;

  void _log(String message) {
    debugPrint('[PiliMax-PB] $message');
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _log(
      'detector mounted: isCurrent=${widget.route.isCurrent} '
      'popGestureEnabled=${widget.route.popGestureEnabled} '
      'navigatorCanPop=${widget.route.navigator?.canPop()}',
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) {
    _log(
      'start: progress=${backEvent.progress} '
      'touchOffset=${backEvent.touchOffset} swipeEdge=${backEvent.swipeEdge} '
      'isButtonEvent=${backEvent.isButtonEvent} _enabled=$_enabled '
      'isCurrent=${widget.route.isCurrent} '
      'popGestureEnabled=${widget.route.popGestureEnabled} '
      'navigatorCanPop=${widget.route.navigator?.canPop()}',
    );
    if (backEvent.isButtonEvent || !_enabled) {
      _log('start -> REJECT (return false)');
      return false;
    }
    widget.backGestureCommand?.value = 0;
    widget.backGestureProgress?.value = backEvent.progress;
    // This route replaces the framework transition widget, so forward the
    // lifecycle event to PageRoute as well. Without this, the gallery moves
    // visually but Navigator never receives the predictive-back transaction.
    widget.route.handleStartBackGesture(progress: 1 - backEvent.progress);
    _log('start -> ACCEPT (return true)');
    return true;
  }

  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent backEvent) {
    _log('update: progress=${backEvent.progress}');
    widget.backGestureProgress?.value = backEvent.progress;
    widget.route.handleUpdateBackGestureProgress(
      progress: 1 - backEvent.progress,
    );
  }

  @override
  void handleCancelBackGesture() {
    _log('cancel');
    widget.backGestureCommand?.value = 2;
    widget.route.handleCancelBackGesture();
  }

  @override
  void handleCommitBackGesture() {
    _log('commit');
    widget.backGestureCommand?.value = 1;
    // PageRoute performs the single Navigator.pop. GalleryViewer must not
    // issue a second pop from its command listener.
    widget.route.handleCommitBackGesture();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}
