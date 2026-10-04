import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:PiliMax/pilimax/common/widgets/glass_style.dart';
import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/physics.dart' show SpringDescription, SpringSimulation;
import 'package:material_ui/material_ui.dart';

const double _kNavigationHeight = 64.0;
const double _kIndicatorWidth = 86.0;
const double _kIndicatorPadding = 4.0;
const Duration _kPressDuration = Duration(milliseconds: 130);
const BorderRadius _kBorderRadius = BorderRadius.all(
  Radius.circular(_kNavigationHeight / 2),
);

const Color _softIndicatorDark = Color(0x24FFFFFF);
const Color _softIndicatorLight = Color(0x13000000);
const double _kSoftGlassBlurSigma = 18.0;

/// Floating navigation bar used by the PiliMax main shell.
///
/// The bar supports the regular Material surface and the translucent
/// soft-glass surface.
class FloatingNavigationBar extends StatelessWidget {
  FloatingNavigationBar({
    super.key,
    this.animationDuration = const Duration(milliseconds: 500),
    this.selectedIndex = 0,
    required this.destinations,
    this.onDestinationSelected,
    this.backgroundColor,
    this.elevation,
    this.shadowColor,
    this.surfaceTintColor,
    this.indicatorColor,
    this.indicatorShape,
    this.labelBehavior,
    this.overlayColor,
    this.labelTextStyle,
    this.labelPadding,
    this.bottomPadding = 8.0,
    this.bottomLift = 0.0,
    this.glassStyle,
  }) : assert(destinations.length >= 2),
       assert(0 <= selectedIndex && selectedIndex < destinations.length),
       assert(!animationDuration.isNegative),
       assert(elevation == null || elevation >= 0),
       assert(bottomPadding >= 0),
       assert(bottomLift.isFinite && bottomLift >= 0);

  final Duration animationDuration;
  final int selectedIndex;
  final List<Widget> destinations;
  final ValueChanged<int>? onDestinationSelected;
  final Color? backgroundColor;
  final double? elevation;
  final Color? shadowColor;
  final Color? surfaceTintColor;
  final Color? indicatorColor;
  final ShapeBorder? indicatorShape;
  final NavigationDestinationLabelBehavior? labelBehavior;

  /// Kept for API compatibility; the custom indicator owns all feedback.
  final WidgetStateProperty<Color?>? overlayColor;
  final WidgetStateProperty<TextStyle?>? labelTextStyle;
  final EdgeInsetsGeometry? labelPadding;
  final double bottomPadding;
  final double bottomLift;
  final GlassStyle? glassStyle;

  @override
  Widget build(BuildContext context) {
    final navigationBarTheme = NavigationBarTheme.of(context);
    final viewPadding = MediaQuery.viewPaddingOf(context);
    final isSoft = glassStyle == GlassStyle.soft;
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;
    final barWidth = destinations.length * _kIndicatorWidth;
    final effectiveIndicatorColor =
        indicatorColor ??
        (isSoft
            ? (isDark ? _softIndicatorDark : _softIndicatorLight)
            : navigationBarTheme.indicatorColor ??
                  colorScheme.secondaryContainer);
    final effectiveBackground =
        backgroundColor ??
        (isSoft
            ? colorScheme.surfaceContainer.withValues(
                alpha: isDark ? 0.56 : 0.48,
              )
            : navigationBarTheme.backgroundColor ??
                  colorScheme.surfaceContainer);
    final effectiveBorder = isSoft
        ? (isDark ? const Color(0x24FFFFFF) : const Color(0xB8FFFFFF))
        : colorScheme.outlineVariant.withValues(alpha: 0.52);
    final effectiveShadow =
        shadowColor ??
        navigationBarTheme.shadowColor ??
        Colors.black.withValues(alpha: isDark ? 0.28 : 0.14);
    final shellDecoration = BoxDecoration(
      // The soft surface tint is painted inside BackdropFilter. Painting the
      // same opaque-ish color here would tint the backdrop before it can be
      // sampled and make the blur appear ineffective.
      color: isSoft ? Colors.transparent : effectiveBackground,
      borderRadius: _kBorderRadius,
      border: Border.all(color: effectiveBorder),
      boxShadow: [
        BoxShadow(
          color: effectiveShadow,
          blurRadius: isSoft ? (isDark ? 16 : 10) : 12,
          spreadRadius: isSoft ? -2 : 0,
          offset: const Offset(0, 4),
        ),
      ],
    );

    final bar = DecoratedBox(
      key: const ValueKey('glassVisualShell'),
      decoration: shellDecoration,
      child: ClipRRect(
        borderRadius: _kBorderRadius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (isSoft)
              BackdropFilter(
                key: const ValueKey('softGlassBackdropFilter'),
                filter: ui.ImageFilter.blur(
                  sigmaX: _kSoftGlassBlurSigma,
                  sigmaY: _kSoftGlassBlurSigma,
                ),
                child: ColoredBox(
                  key: const ValueKey('softGlassSurfaceTint'),
                  color: effectiveBackground,
                ),
              )
            else
              ColoredBox(
                key: const ValueKey('softGlassSurfaceTint'),
                color: effectiveBackground,
              ),
            MediaQuery.removePadding(
              context: context,
              removeLeft: true,
              removeTop: true,
              removeRight: true,
              removeBottom: true,
              child: _InteractiveFloatingNavigationBar(
                key: const ValueKey('glassNavigationBar'),
                animationDuration: animationDuration,
                selectedIndex: selectedIndex,
                destinations: destinations,
                onDestinationSelected: onDestinationSelected,
                elevation: elevation ?? 0,
                surfaceTintColor: surfaceTintColor ?? Colors.transparent,
                indicatorColor: effectiveIndicatorColor,
                indicatorShape: indicatorShape,
                labelBehavior: labelBehavior,
                labelTextStyle: labelTextStyle,
                labelPadding:
                    labelPadding ??
                    navigationBarTheme.labelPadding ??
                    const EdgeInsets.only(top: 2),
              ),
            ),
          ],
        ),
      ),
    );

    return Transform.translate(
      offset: Offset(0, -bottomLift),
      child: Align(
        heightFactor: 1,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            viewPadding.left,
            0,
            viewPadding.right,
            bottomPadding + viewPadding.bottom,
          ),
          child: SizedBox(
            width: barWidth,
            height: _kNavigationHeight,
            child: bar,
          ),
        ),
      ),
    );
  }
}

/// Adds drag and press interactions while leaving the actual destination
/// semantics to Flutter's NavigationBar.
class _InteractiveFloatingNavigationBar extends StatefulWidget {
  const _InteractiveFloatingNavigationBar({
    super.key,
    required this.animationDuration,
    required this.selectedIndex,
    required this.destinations,
    required this.onDestinationSelected,
    required this.elevation,
    required this.surfaceTintColor,
    required this.indicatorColor,
    required this.indicatorShape,
    required this.labelBehavior,
    required this.labelTextStyle,
    required this.labelPadding,
  });

  final Duration animationDuration;
  final int selectedIndex;
  final List<Widget> destinations;
  final ValueChanged<int>? onDestinationSelected;
  final double elevation;
  final Color surfaceTintColor;
  final Color indicatorColor;
  final ShapeBorder? indicatorShape;
  final NavigationDestinationLabelBehavior? labelBehavior;
  final WidgetStateProperty<TextStyle?>? labelTextStyle;
  final EdgeInsetsGeometry labelPadding;

  @override
  State<_InteractiveFloatingNavigationBar> createState() =>
      _InteractiveFloatingNavigationBarState();
}

class _InteractiveFloatingNavigationBarState
    extends State<_InteractiveFloatingNavigationBar>
    with TickerProviderStateMixin {
  late final AnimationController _selectionController;
  late final AnimationController _pressController;
  late final Listenable _interactionListenable;
  late double _fromIndex;
  late double _targetIndex;
  double? _dragIndex;
  double _itemExtent = _kIndicatorWidth;
  bool _isPressed = false;
  bool _interactionCommitted = false;
  int? _activePointer;
  int? _pendingPointerUp;
  Offset _pointerDownPosition = Offset.zero;
  Offset _lastPointerPosition = Offset.zero;
  Duration _lastPointerTime = Duration.zero;
  bool _gestureDirectionLocked = false;
  bool _isVerticalGesture = false;
  double _dragVelocity = 0;
  TextDirection _textDirection = TextDirection.ltr;

  double get _animatedIndex =>
      _fromIndex + (_targetIndex - _fromIndex) * _selectionController.value;

  bool get _isRtl => _textDirection == TextDirection.rtl;

  double get _directionSign => _isRtl ? -1 : 1;

  @override
  void initState() {
    super.initState();
    _fromIndex = widget.selectedIndex.toDouble();
    _targetIndex = _fromIndex;
    _selectionController = AnimationController(vsync: this, value: 1);
    _pressController = AnimationController(
      vsync: this,
      duration: _kPressDuration,
      reverseDuration: const Duration(milliseconds: 180),
    );
    _interactionListenable = Listenable.merge([
      _selectionController,
      _pressController,
    ]);
  }

  @override
  void didUpdateWidget(_InteractiveFloatingNavigationBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.destinations.length != widget.destinations.length) {
      final maxIndex = (widget.destinations.length - 1).toDouble();
      _fromIndex = _fromIndex.clamp(0, maxIndex).toDouble();
      _targetIndex = _targetIndex.clamp(0, maxIndex).toDouble();
      _dragIndex = _dragIndex?.clamp(0, maxIndex).toDouble();
    }
    if (_targetIndex != widget.selectedIndex.toDouble()) {
      _animateTo(widget.selectedIndex.toDouble());
    }
  }

  @override
  void dispose() {
    _selectionController.dispose();
    _pressController.dispose();
    super.dispose();
  }

  void _animateTo(double index, {double velocity = 0}) {
    final currentIndex = _dragIndex ?? _animatedIndex;
    _selectionController.stop();
    _fromIndex = currentIndex;
    _targetIndex = index;
    _dragIndex = null;
    _gestureDirectionLocked = false;
    _isVerticalGesture = false;
    _dragVelocity = 0;
    _isPressed = false;
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (disableAnimations) {
      _pressController.value = 0;
      _selectionController.value = 1;
      return;
    }
    _pressController.reverse();
    _selectionController.value = 0;
    _selectionController.animateWith(
      SpringSimulation(
        SpringDescription.withDampingRatio(
          ratio: 0.82,
          stiffness: 420,
          mass: 1,
        ),
        0,
        1,
        velocity.clamp(-3.0, 3.0).toDouble(),
        snapToEnd: true,
      ),
    );
    if (mounted) setState(() {});
  }

  void _handleDestinationSelected(int index) {
    if (_interactionCommitted) return;
    _interactionCommitted = true;
    _animateTo(index.toDouble());
    widget.onDestinationSelected?.call(index);
    if (_activePointer == null && _pendingPointerUp == null) {
      _scheduleInteractionReset();
    }
  }

  void _scheduleInteractionReset() {
    Future<void>.microtask(() {
      if (mounted && _activePointer == null) {
        _interactionCommitted = false;
      }
    });
  }

  double _indexForX(double x) {
    final logicalX = _isRtl ? _itemExtent * widget.destinations.length - x : x;
    return (logicalX / _itemExtent - 0.5)
        .clamp(0.0, (widget.destinations.length - 1).toDouble())
        .toDouble();
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (_activePointer != null) return;
    _selectionController.stop();
    _activePointer = event.pointer;
    _pendingPointerUp = null;
    _pointerDownPosition = event.localPosition;
    _lastPointerPosition = event.localPosition;
    _lastPointerTime = event.timeStamp;
    _gestureDirectionLocked = false;
    _isVerticalGesture = false;
    _dragVelocity = 0;
    _interactionCommitted = false;
    setState(() => _isPressed = true);
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      _pressController.value = 1;
    } else {
      _pressController.forward();
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (event.pointer != _activePointer) return;
    final delta = event.localPosition - _pointerDownPosition;
    if (!_gestureDirectionLocked && delta.distance > kTouchSlop) {
      _gestureDirectionLocked = true;
      _isVerticalGesture = delta.dy.abs() > delta.dx.abs();
      if (_isVerticalGesture) {
        _animateTo(widget.selectedIndex.toDouble());
        return;
      }
    }
    if (_isVerticalGesture) return;

    final elapsed = (event.timeStamp - _lastPointerTime).inMicroseconds;
    final deltaX = event.localPosition.dx - _lastPointerPosition.dx;
    final instantaneousVelocity = elapsed > 0
        ? (deltaX * _directionSign / elapsed * 1000000 / _itemExtent)
              .clamp(-3.0, 3.0)
              .toDouble()
        : 0.0;
    _dragVelocity = (_dragVelocity * 0.82 + instantaneousVelocity * 0.18)
        .clamp(-3.0, 3.0)
        .toDouble();
    _lastPointerPosition = event.localPosition;
    _lastPointerTime = event.timeStamp;
    final nextIndex = _indexForX(event.localPosition.dx);
    if (_dragIndex == null || (nextIndex - _dragIndex!).abs() > 0.001) {
      setState(() => _dragIndex = nextIndex);
    }
  }

  double _pointerVelocity(PointerUpEvent event) {
    final elapsed = (event.timeStamp - _lastPointerTime).inMicroseconds;
    if (elapsed <= 0) return _dragVelocity;
    return ((event.localPosition.dx - _lastPointerPosition.dx) *
            _directionSign /
            elapsed *
            1000000 /
            _itemExtent)
        .clamp(-3.0, 3.0)
        .toDouble();
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (event.pointer != _activePointer) return;
    final dragIndex = _dragIndex ?? _indexForX(event.localPosition.dx);
    final velocity = _pointerVelocity(event);
    _activePointer = null;
    _pendingPointerUp = event.pointer;
    Future<void>.microtask(() {
      if (!mounted || _pendingPointerUp != event.pointer) return;
      _pendingPointerUp = null;
      if (_interactionCommitted) {
        _scheduleInteractionReset();
        return;
      }
      _interactionCommitted = true;
      if (_isVerticalGesture || !_gestureDirectionLocked) {
        _animateTo(widget.selectedIndex.toDouble());
        _scheduleInteractionReset();
        return;
      }
      final nearest = (dragIndex + velocity * 0.08)
          .round()
          .clamp(0, widget.destinations.length - 1)
          .toInt();
      final targetIndex = _nearestEnabledIndex(nearest);
      if (targetIndex == null) {
        _animateTo(widget.selectedIndex.toDouble());
      } else {
        _animateTo(targetIndex.toDouble(), velocity: velocity);
        if (targetIndex != widget.selectedIndex) {
          widget.onDestinationSelected?.call(targetIndex);
        }
      }
      _scheduleInteractionReset();
    });
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (event.pointer != _activePointer) return;
    _activePointer = null;
    _pendingPointerUp = null;
    _interactionCommitted = true;
    _animateTo(widget.selectedIndex.toDouble());
    _scheduleInteractionReset();
  }

  bool _destinationEnabled(int index) {
    final destination = widget.destinations[index];
    if (destination is FloatingNavigationDestination) {
      return destination.enabled;
    }
    if (destination is NavigationDestination) return destination.enabled;
    return true;
  }

  int? _nearestEnabledIndex(int index) {
    final maxIndex = widget.destinations.length - 1;
    final clamped = index.clamp(0, maxIndex).toInt();
    if (_destinationEnabled(clamped)) return clamped;
    for (var distance = 1; distance <= maxIndex; distance++) {
      final left = clamped - distance;
      if (left >= 0 && _destinationEnabled(left)) return left;
      final right = clamped + distance;
      if (right <= maxIndex && _destinationEnabled(right)) return right;
    }
    return null;
  }

  Widget _buildIndicator() {
    final progress = math.max(
      _pressController.value,
      _isPressed ? 0.2 : 0.0,
    );
    final visualIndex = _dragIndex ?? _animatedIndex;
    final logicalCenter = (visualIndex + 0.5) * _itemExtent;
    final center = _isRtl
        ? _itemExtent * widget.destinations.length - logicalCenter
        : logicalCenter;
    final width = _itemExtent * (1 + 0.06 * progress);
    final height = _kNavigationHeight - 2 * _kIndicatorPadding + 4 * progress;
    final shape =
        widget.indicatorShape ??
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(height / 2),
        );
    return Positioned(
      left: center - width / 2,
      top: (_kNavigationHeight - height) / 2,
      width: width,
      height: height,
      child: IgnorePointer(
        child: DecoratedBox(
          key: const ValueKey('floatingNavigationIndicator'),
          decoration: ShapeDecoration(
            color: widget.indicatorColor,
            shape: shape,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _textDirection = Directionality.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : widget.destinations.length * _kIndicatorWidth;
        _itemExtent = width / widget.destinations.length;
        return AnimatedBuilder(
          animation: _interactionListenable,
          builder: (context, _) => Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _handlePointerDown,
            onPointerMove: _handlePointerMove,
            onPointerUp: _handlePointerUp,
            onPointerCancel: _handlePointerCancel,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _buildIndicator(),
                MediaQuery.removePadding(
                  context: context,
                  removeLeft: true,
                  removeTop: true,
                  removeRight: true,
                  removeBottom: true,
                  child: NavigationBar(
                    key: const ValueKey('floatingNavigationSemanticsBar'),
                    animationDuration: Duration.zero,
                    selectedIndex: widget.selectedIndex,
                    destinations: widget.destinations,
                    onDestinationSelected: _handleDestinationSelected,
                    backgroundColor: Colors.transparent,
                    elevation: widget.elevation,
                    shadowColor: Colors.transparent,
                    surfaceTintColor: widget.surfaceTintColor,
                    indicatorColor: Colors.transparent,
                    indicatorShape: widget.indicatorShape,
                    height: _kNavigationHeight,
                    labelBehavior: widget.labelBehavior,
                    // The custom indicator is the only interaction surface.
                    // Disable Material's pressed, hover, and focus overlay so
                    // it cannot paint a second mask over the icon.
                    overlayColor: const WidgetStatePropertyAll(
                      Colors.transparent,
                    ),
                    labelTextStyle: widget.labelTextStyle,
                    labelPadding: widget.labelPadding,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A destination that can wrap its icon, for example to add an unread badge.
class FloatingNavigationDestination extends StatelessWidget {
  const FloatingNavigationDestination({
    super.key,
    required this.icon,
    this.selectedIcon,
    required this.label,
    this.tooltip,
    this.enabled = true,
    this.iconWrapper,
  });

  final Widget icon;
  final Widget? selectedIcon;
  final String label;
  final String? tooltip;
  final bool enabled;
  final Widget Function(Widget icon)? iconWrapper;

  @override
  Widget build(BuildContext context) {
    final wrappedIcon = iconWrapper?.call(icon) ?? icon;
    final wrappedSelectedIcon = selectedIcon == null
        ? null
        : iconWrapper?.call(selectedIcon!) ?? selectedIcon;
    return NavigationDestination(
      icon: wrappedIcon,
      selectedIcon: wrappedSelectedIcon,
      label: label,
      tooltip: tooltip,
      enabled: enabled,
    );
  }
}
