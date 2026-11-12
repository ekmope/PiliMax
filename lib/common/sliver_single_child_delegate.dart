import 'package:flutter/widgets.dart';

/// Reuses one immutable widget for a bounded number of sliver children.
class SliverSingleChildDelegate extends SliverChildDelegate {
  const SliverSingleChildDelegate({required int count, required this.child})
    : estimatedChildCount = count,
      assert(count >= 0);

  @override
  final int estimatedChildCount;
  final Widget child;

  @override
  Widget? build(BuildContext context, int index) {
    // A child may rebuild its render-object root independently (for example,
    // a skeleton switching its shimmer off when the route's TickerMode changes).
    // Keep the same stable repaint boundary used by the standard delegates so
    // this cannot detach the sliver's direct child outside its rebuild pass.
    if (index < 0 || index >= estimatedChildCount) return null;
    return RepaintBoundary(child: child);
  }

  @override
  bool shouldRebuild(covariant SliverSingleChildDelegate oldDelegate) {
    return estimatedChildCount != oldDelegate.estimatedChildCount ||
        child != oldDelegate.child;
  }
}
