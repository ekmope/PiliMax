import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide PageView;
import 'package:flutter/material.dart' as material show PageView;
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

/// Flutter [material.PageView] driven by a PiliMax-provided horizontal drag
/// recognizer.
///
/// The framework page layout, position, accessibility and snapping remain in
/// use. Only gesture admission is app-owned so diagonal drags and image-edge
/// handoff keep their existing behavior without forking Scrollable.
class PageView<T extends HorizontalDragGestureRecognizer>
    extends StatefulWidget {
  PageView({
    super.key,
    this.scrollDirection = Axis.horizontal,
    this.reverse = false,
    this.controller,
    this.physics,
    this.pageSnapping = true,
    this.onPageChanged,
    List<Widget> children = const [],
    this.dragStartBehavior = DragStartBehavior.start,
    this.allowImplicitScrolling = false,
    this.scrollCacheExtent,
    this.restorationId,
    this.clipBehavior = Clip.hardEdge,
    this.hitTestBehavior = HitTestBehavior.opaque,
    this.scrollBehavior,
    this.padEnds = true,
    required this.horizontalDragGestureRecognizer,
  }) : childrenDelegate = SliverChildListDelegate(children);

  PageView.builder({
    super.key,
    this.scrollDirection = Axis.horizontal,
    this.reverse = false,
    this.controller,
    this.physics,
    this.pageSnapping = true,
    this.onPageChanged,
    required NullableIndexedWidgetBuilder itemBuilder,
    ChildIndexGetter? findChildIndexCallback,
    int? itemCount,
    this.dragStartBehavior = DragStartBehavior.start,
    this.allowImplicitScrolling = false,
    this.scrollCacheExtent,
    this.restorationId,
    this.clipBehavior = Clip.hardEdge,
    this.hitTestBehavior = HitTestBehavior.opaque,
    this.scrollBehavior,
    this.padEnds = true,
    required this.horizontalDragGestureRecognizer,
  }) : childrenDelegate = SliverChildBuilderDelegate(
         itemBuilder,
         findChildIndexCallback: findChildIndexCallback,
         childCount: itemCount,
       );

  const PageView.custom({
    super.key,
    this.scrollDirection = Axis.horizontal,
    this.reverse = false,
    this.controller,
    this.physics,
    this.pageSnapping = true,
    this.onPageChanged,
    required this.childrenDelegate,
    this.dragStartBehavior = DragStartBehavior.start,
    this.allowImplicitScrolling = false,
    this.scrollCacheExtent,
    this.restorationId,
    this.clipBehavior = Clip.hardEdge,
    this.hitTestBehavior = HitTestBehavior.opaque,
    this.scrollBehavior,
    this.padEnds = true,
    required this.horizontalDragGestureRecognizer,
  });

  final Axis scrollDirection;
  final bool reverse;
  final PageController? controller;
  final ScrollPhysics? physics;
  final bool pageSnapping;
  final ValueChanged<int>? onPageChanged;
  final SliverChildDelegate childrenDelegate;
  final DragStartBehavior dragStartBehavior;
  final bool allowImplicitScrolling;
  final ScrollCacheExtent? scrollCacheExtent;
  final String? restorationId;
  final Clip clipBehavior;
  final HitTestBehavior hitTestBehavior;
  final ScrollBehavior? scrollBehavior;
  final bool padEnds;
  final GestureRecognizerFactoryConstructor<T> horizontalDragGestureRecognizer;

  @override
  State<PageView<T>> createState() => _PageViewState<T>();
}

class _PageViewState<T extends HorizontalDragGestureRecognizer>
    extends State<PageView<T>> {
  late PageController _controller;
  late bool _ownsController;
  ScrollHoldController? _hold;
  Drag? _drag;

  @override
  void initState() {
    super.initState();
    _initController();
  }

  void _initController() {
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? PageController();
  }

  @override
  void didUpdateWidget(PageView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _handleDragCancel();
      if (_ownsController) {
        _controller.dispose();
      }
      _initController();
    }
  }

  void _handleDragDown(DragDownDetails details) {
    if (!_controller.hasClients) return;
    _hold?.cancel();
    _drag?.cancel();
    _hold = _controller.position.hold(() => _hold = null);
  }

  void _handleDragStart(DragStartDetails details) {
    if (!_controller.hasClients) {
      return;
    }
    _drag = _controller.position.drag(details, () => _drag = null);
    _hold?.cancel();
    _hold = null;
  }

  void _handleDragUpdate(DragUpdateDetails details) => _drag?.update(details);

  void _handleDragEnd(DragEndDetails details) {
    _drag?.end(details);
    _drag = null;
  }

  void _handleDragCancel() {
    _hold?.cancel();
    _hold = null;
    _drag?.cancel();
    _drag = null;
  }

  void _handlePageChanged(int index) {
    widget.onPageChanged?.call(index);
  }

  bool _allowsUserScrolling(ScrollPhysics physics) {
    ScrollPhysics? current = physics;
    while (current != null) {
      if (!current.allowUserScrolling) return false;
      current = current.parent;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    assert(
      widget.scrollDirection == Axis.horizontal,
      'Custom recognizer PageView currently supports horizontal paging only.',
    );
    final scrollBehavior =
        widget.scrollBehavior ?? ScrollConfiguration.of(context);
    final frameworkScrollBehavior = scrollBehavior.copyWith(
      dragDevices: const <PointerDeviceKind>{},
    );
    final dragPhysics = const PageScrollPhysics().applyTo(
      widget.physics ?? scrollBehavior.getScrollPhysics(context),
    );
    Widget child = material.PageView.custom(
      scrollDirection: widget.scrollDirection,
      reverse: widget.reverse,
      controller: _controller,
      physics: widget.physics,
      pageSnapping: widget.pageSnapping,
      onPageChanged: _handlePageChanged,
      childrenDelegate: widget.childrenDelegate,
      dragStartBehavior: widget.dragStartBehavior,
      allowImplicitScrolling: widget.allowImplicitScrolling,
      scrollCacheExtent: widget.scrollCacheExtent,
      restorationId: widget.restorationId,
      clipBehavior: widget.clipBehavior,
      hitTestBehavior: widget.hitTestBehavior,
      scrollBehavior: frameworkScrollBehavior,
      padEnds: widget.padEnds,
    );
    final dragEnabled = _allowsUserScrolling(dragPhysics);
    return RawGestureDetector(
      behavior: widget.hitTestBehavior,
      excludeFromSemantics: true,
      gestures: dragEnabled
          ? <Type, GestureRecognizerFactory>{
              T: GestureRecognizerFactoryWithHandlers<T>(
                widget.horizontalDragGestureRecognizer,
                (recognizer) {
                  recognizer
                    ..onDown = _handleDragDown
                    ..dragStartBehavior = widget.dragStartBehavior
                    ..onStart = _handleDragStart
                    ..onUpdate = _handleDragUpdate
                    ..onEnd = _handleDragEnd
                    ..onCancel = _handleDragCancel
                    ..minFlingDistance = dragPhysics.minFlingDistance
                    ..minFlingVelocity = dragPhysics.minFlingVelocity
                    ..maxFlingVelocity = dragPhysics.maxFlingVelocity
                    ..velocityTrackerBuilder = scrollBehavior
                        .velocityTrackerBuilder(context)
                    ..multitouchDragStrategy = scrollBehavior
                        .getMultitouchDragStrategy(context)
                    ..gestureSettings = MediaQuery.maybeGestureSettingsOf(
                      context,
                    )
                    ..supportedDevices = scrollBehavior.dragDevices;
                },
              ),
            }
          : const <Type, GestureRecognizerFactory>{},
      child: child,
    );
  }

  @override
  void dispose() {
    _handleDragCancel();
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }
}
