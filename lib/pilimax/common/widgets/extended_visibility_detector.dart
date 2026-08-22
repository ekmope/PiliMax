// Vendored from fluttercandies/extended_nested_scroll_view (MIT), which no
// longer exports this widget as of the Flutter 3.47 dependency update.
import 'package:material_ui/material_ui.dart';
import 'package:visibility_detector/visibility_detector.dart';

/// Tracks the visibility of [child] and exposes the latest [VisibilityInfo]
/// via [ExtendedVisibilityDetector.of].
class ExtendedVisibilityDetector extends StatefulWidget {
  const ExtendedVisibilityDetector({
    super.key,
    required this.child,
    required this.uniqueKey,
  });

  final Widget child;
  final Key uniqueKey;

  @override
  State<ExtendedVisibilityDetector> createState() =>
      _ExtendedVisibilityDetectorState();

  static VisibilityInfo? of(BuildContext context) {
    return context
        .findAncestorStateOfType<_ExtendedVisibilityDetectorState>()
        ?._visibilityInfo;
  }
}

class _ExtendedVisibilityDetectorState
    extends State<ExtendedVisibilityDetector> {
  VisibilityInfo? _visibilityInfo;

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: widget.uniqueKey,
      child: widget.child,
      onVisibilityChanged: (VisibilityInfo visibilityInfo) {
        _visibilityInfo = visibilityInfo;
      },
    );
  }
}
