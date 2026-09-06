import 'package:material_ui/material_ui.dart';

/// https://github.com/qq326646683/interactiveviewer_gallery

/// A [PageRoute] with a semi transparent background.
///
/// Similar to calling [showDialog] except it can be used with a [Navigator] to
/// show a [Hero] animation.
class HeroDialogRoute<T> extends PageRoute<T> {
  HeroDialogRoute({required this.pageBuilder});

  final RoutePageBuilder pageBuilder;

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
  // route snapshot while a Hero flight is in progress.
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
    return FadeTransition(
      opacity: curve,
      child: child,
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
