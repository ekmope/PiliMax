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
    if (index < 0 || index >= estimatedChildCount) return null;
    return child;
  }

  @override
  bool shouldRebuild(covariant SliverSingleChildDelegate oldDelegate) {
    return estimatedChildCount != oldDelegate.estimatedChildCount ||
        child != oldDelegate.child;
  }
}
