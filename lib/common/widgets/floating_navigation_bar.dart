import 'dart:async' show unawaited;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:PiliMax/common/widgets/liquid_glass_quality.dart';
import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart' show SpringDescription, SpringSimulation;

const double _kNavigationHeight = 64.0;
const double _kIndicatorWidth = 86.0;
const double _kIndicatorPadding = 4.0;
const Duration _kLiquidPressDuration = Duration(milliseconds: 130);
final ui.ImageFilter _kLiquidReflectiveBlur = ui.ImageFilter.blur(
  sigmaX: 7,
  sigmaY: 7,
  tileMode: ui.TileMode.clamp,
);
final ui.ImageFilter _kLiquidFrostedBlur = ui.ImageFilter.blur(
  sigmaX: 9,
  sigmaY: 9,
  tileMode: ui.TileMode.clamp,
);
const BorderRadius _kBorderRadius = BorderRadius.all(
  Radius.circular(_kNavigationHeight / 2),
);
const ShapeBorder _kNavigationShape = RoundedSuperellipseBorder(
  borderRadius: _kBorderRadius,
);
const Color _indicatorDark = Color(0x15FFFFFF);
const Color _indicatorLight = Color(0x10000000);

/// A compact, floating shell around Flutter's public [NavigationBar].
class FloatingNavigationBar extends StatelessWidget {
  // ignore: prefer_const_constructors_in_immutables
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
    this.liquidGlass = false,
    this.liquidGlassQuality = LiquidGlassQuality.automatic,
  }) : assert(destinations.length >= 2),
       assert(0 <= selectedIndex && selectedIndex < destinations.length),
       assert(!animationDuration.isNegative),
       assert(elevation == null || elevation >= 0),
       assert(bottomPadding >= 0);

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
  final WidgetStateProperty<Color?>? overlayColor;
  final WidgetStateProperty<TextStyle?>? labelTextStyle;
  final EdgeInsetsGeometry? labelPadding;
  final double bottomPadding;
  final bool liquidGlass;
  final LiquidGlassQuality liquidGlassQuality;

  @override
  Widget build(BuildContext context) {
    if (liquidGlass) {
      return _LiquidGlassNavigationBar(
        animationDuration: animationDuration,
        selectedIndex: selectedIndex,
        destinations: destinations,
        onDestinationSelected: onDestinationSelected,
        backgroundColor: backgroundColor,
        elevation: elevation,
        shadowColor: shadowColor,
        surfaceTintColor: surfaceTintColor,
        indicatorColor: indicatorColor,
        indicatorShape: indicatorShape,
        labelBehavior: labelBehavior,
        overlayColor: overlayColor,
        labelTextStyle: labelTextStyle,
        labelPadding: labelPadding,
        bottomPadding: bottomPadding,
        liquidGlassQuality: liquidGlassQuality,
      );
    }

    final theme = Theme.of(context);
    final navigationBarTheme = NavigationBarTheme.of(context);
    final viewPadding = MediaQuery.viewPaddingOf(context);
    final isDark = theme.colorScheme.brightness == Brightness.dark;
    final preferredWidth = destinations.length * _kIndicatorWidth;
    final availableWidth = math.max(
      0.0,
      MediaQuery.sizeOf(context).width - viewPadding.horizontal,
    );
    final barWidth = math.min(preferredWidth, availableWidth);
    final indicatorWidth = barWidth < preferredWidth
        ? math.max(0.0, barWidth - 2 * _kIndicatorPadding) / destinations.length
        : _kIndicatorWidth;

    final effectiveElevation = elevation ?? navigationBarTheme.elevation ?? 3.0;
    final effectiveIndicatorColor =
        indicatorColor ??
        navigationBarTheme.indicatorColor ??
        (isDark ? _indicatorDark : _indicatorLight);
    final effectiveIndicatorShape =
        indicatorShape ??
        navigationBarTheme.indicatorShape ??
        _kNavigationShape;
    final sourceOverlayColor = overlayColor ?? navigationBarTheme.overlayColor;
    final effectiveOverlayColor = WidgetStateProperty.resolveWith<Color?>((
      states,
    ) {
      if (states.contains(WidgetState.pressed)) {
        return Colors.transparent;
      }
      return sourceOverlayColor?.resolve(states);
    });

    return UnconstrainedBox(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          viewPadding.left,
          0,
          viewPadding.right,
          bottomPadding + viewPadding.bottom,
        ),
        child: SizedBox(
          key: const ValueKey('liquidGlassNavigationBar'),
          height: _kNavigationHeight,
          width: barWidth,
          child: Material(
            color:
                backgroundColor ??
                navigationBarTheme.backgroundColor ??
                theme.colorScheme.surfaceContainer,
            elevation: effectiveElevation,
            shadowColor:
                shadowColor ??
                navigationBarTheme.shadowColor ??
                Colors.transparent,
            surfaceTintColor:
                surfaceTintColor ??
                navigationBarTheme.surfaceTintColor ??
                Colors.transparent,
            shape: RoundedSuperellipseBorder(
              side: BorderSide(
                color: isDark
                    ? const Color(0x08FFFFFF)
                    : const Color(0x08000000),
              ),
              borderRadius: _kBorderRadius,
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Padding(
                  padding: const EdgeInsets.all(_kIndicatorPadding),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var index = 0; index < destinations.length; index++)
                        Expanded(
                          child: OverflowBox(
                            minWidth: indicatorWidth,
                            maxWidth: indicatorWidth,
                            child: AnimatedOpacity(
                              opacity: index == selectedIndex ? 1 : 0,
                              duration: const Duration(milliseconds: 100),
                              child: AnimatedScale(
                                scale: index == selectedIndex ? 1 : 0.5,
                                duration: animationDuration,
                                curve: Curves.easeInOutCubicEmphasized,
                                child: DecoratedBox(
                                  decoration: ShapeDecoration(
                                    color: effectiveIndicatorColor,
                                    shape: effectiveIndicatorShape,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(_kIndicatorPadding),
                  child: MediaQuery.removePadding(
                    context: context,
                    removeLeft: true,
                    removeTop: true,
                    removeRight: true,
                    removeBottom: true,
                    child: NavigationBar(
                      animationDuration: animationDuration,
                      selectedIndex: selectedIndex,
                      destinations: destinations,
                      onDestinationSelected: onDestinationSelected,
                      backgroundColor: Colors.transparent,
                      elevation: 0,
                      shadowColor: Colors.transparent,
                      surfaceTintColor: Colors.transparent,
                      indicatorColor: Colors.transparent,
                      height: _kNavigationHeight - 2 * _kIndicatorPadding,
                      labelBehavior: labelBehavior,
                      // The floating bar already paints the complete destination
                      // indicator behind both the icon and label. Keep the
                      // framework's hover/focus feedback, but suppress its
                      // icon-only pressed splash so there is only one effect.
                      overlayColor: effectiveOverlayColor,
                      labelTextStyle: labelTextStyle,
                      labelPadding:
                          labelPadding ??
                          navigationBarTheme.labelPadding ??
                          const EdgeInsets.only(top: 2),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LiquidGlassNavigationBar extends StatefulWidget {
  const _LiquidGlassNavigationBar({
    required this.animationDuration,
    required this.selectedIndex,
    required this.destinations,
    required this.onDestinationSelected,
    required this.backgroundColor,
    required this.elevation,
    required this.shadowColor,
    required this.surfaceTintColor,
    required this.indicatorColor,
    required this.indicatorShape,
    required this.labelBehavior,
    required this.overlayColor,
    required this.labelTextStyle,
    required this.labelPadding,
    required this.bottomPadding,
    required this.liquidGlassQuality,
  });

  final Duration animationDuration;
  final int selectedIndex;
  final List<Widget> destinations;
  final ValueChanged<int>? onDestinationSelected;
  final Color? backgroundColor;
  final double? elevation;
  final Color? shadowColor;
  final Color? surfaceTintColor;
  final ShapeBorder? indicatorShape;
  final Color? indicatorColor;
  final NavigationDestinationLabelBehavior? labelBehavior;
  final WidgetStateProperty<Color?>? overlayColor;
  final WidgetStateProperty<TextStyle?>? labelTextStyle;
  final EdgeInsetsGeometry? labelPadding;
  final double bottomPadding;
  final LiquidGlassQuality liquidGlassQuality;

  @override
  State<_LiquidGlassNavigationBar> createState() =>
      _LiquidGlassNavigationBarState();
}

class _LiquidGlassNavigationBarState extends State<_LiquidGlassNavigationBar>
    with TickerProviderStateMixin {
  late final AnimationController _selectionController;
  late final AnimationController _pressController;
  late final Listenable _indicatorListenable;
  late double _fromIndex;
  late double _targetIndex;
  double? _dragIndex;
  double _dragStartIndex = 0;
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
  double _dragDirection = 0;
  double _dragVelocity = 0;
  double _releaseVisualOffset = 0;
  double _releaseShellOffset = 0;
  double _releaseMotionIndex = 0;
  double _releaseVelocityNorm = 0;
  double _releaseTravel = 0;
  double _releaseDragProgress = 0;
  late LiquidGlassQuality _resolvedQuality;

  double get _animatedIndex =>
      _fromIndex + (_targetIndex - _fromIndex) * _selectionController.value;

  double get _dragVelocityNorm =>
      (_dragVelocity / 4).clamp(-1.0, 1.0).toDouble();

  double _visualMotionIndex(
    double indicatorIndex,
    double transitionProgress,
  ) {
    if (_dragIndex != null) {
      return indicatorIndex - _dragStartIndex;
    }
    return (_targetIndex - _fromIndex) * transitionProgress;
  }

  double get _releaseProgress =>
      (1 - _selectionController.value).clamp(0.0, 1.0).toDouble();

  double get _visualBarOffset {
    final indicatorIndex = _dragIndex ?? _animatedIndex;
    final transitionProgress = math.sin(math.pi * _selectionController.value);
    final motionIndex = _visualMotionIndex(
      indicatorIndex,
      transitionProgress,
    );
    return _dragIndex != null
        ? (motionIndex * 2.6 + _dragVelocityNorm * 3.2)
              .clamp(-7.0, 7.0)
              .toDouble()
        : (motionIndex * 2.6 + _releaseShellOffset * _releaseProgress)
              .clamp(-7.0, 7.0)
              .toDouble();
  }

  bool get _usesReflectiveQuality =>
      widget.liquidGlassQuality == LiquidGlassQuality.reflective ||
      (widget.liquidGlassQuality == LiquidGlassQuality.automatic &&
          _resolvedQuality == LiquidGlassQuality.reflective);

  @override
  void initState() {
    super.initState();
    _fromIndex = widget.selectedIndex.toDouble();
    _targetIndex = _fromIndex;
    _selectionController = AnimationController(vsync: this, value: 1);
    _pressController = AnimationController(
      vsync: this,
      duration: _kLiquidPressDuration,
      reverseDuration: const Duration(milliseconds: 180),
    );
    _indicatorListenable = Listenable.merge([
      _selectionController,
      _pressController,
    ]);
    _resolvedQuality = _initialQuality;
    _resolveAutomaticQuality();
  }

  LiquidGlassQuality get _initialQuality =>
      widget.liquidGlassQuality == LiquidGlassQuality.automatic
      ? LiquidGlassQualityResolver.immediateDefault
      : widget.liquidGlassQuality;

  void _resolveAutomaticQuality() {
    if (widget.liquidGlassQuality != LiquidGlassQuality.automatic) return;
    unawaited(
      LiquidGlassQualityResolver.resolve().then((quality) {
        if (mounted &&
            widget.liquidGlassQuality == LiquidGlassQuality.automatic) {
          setState(() => _resolvedQuality = quality);
        }
      }),
    );
  }

  @override
  void didUpdateWidget(_LiquidGlassNavigationBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.liquidGlassQuality != widget.liquidGlassQuality) {
      _resolvedQuality = _initialQuality;
      _resolveAutomaticQuality();
    }
    if (oldWidget.destinations.length != widget.destinations.length) {
      final maxIndex = (widget.destinations.length - 1).toDouble();
      _fromIndex = _fromIndex.clamp(0.0, maxIndex).toDouble();
      _targetIndex = _targetIndex.clamp(0.0, maxIndex).toDouble();
      _dragIndex = _dragIndex?.clamp(0.0, maxIndex).toDouble();
    }
    final selectedIndex = widget.selectedIndex.toDouble();
    if ((_targetIndex - selectedIndex).abs() > 0.001) {
      _animateTo(selectedIndex);
    }
  }

  @override
  void dispose() {
    _selectionController.dispose();
    _pressController.dispose();
    super.dispose();
  }

  void _animateTo(double index, {double velocity = 0}) {
    // The indicator keeps a continuous position so taps and drags share one
    // spring instead of restarting separate per-destination animations.
    final dragIndex = _dragIndex;
    final currentIndex = dragIndex ?? _animatedIndex;
    final dragVelocityNorm = _dragVelocityNorm;
    final dragMotionIndex = dragIndex == null
        ? 0.0
        : currentIndex - _dragStartIndex;
    _releaseVisualOffset = dragIndex == null
        ? 0
        : (dragMotionIndex * 2.6 + dragVelocityNorm * 4.0)
              .clamp(-9.0, 9.0)
              .toDouble();
    _releaseShellOffset = dragIndex == null
        ? 0
        : (dragMotionIndex * 2.6 + dragVelocityNorm * 3.2)
              .clamp(-7.0, 7.0)
              .toDouble();
    _releaseMotionIndex = dragMotionIndex;
    _releaseVelocityNorm = dragIndex == null ? 0 : dragVelocityNorm;
    _releaseTravel = dragIndex == null ? 0 : dragMotionIndex.abs();
    _releaseDragProgress =
        dragIndex != null && _gestureDirectionLocked && !_isVerticalGesture
        ? 1.0
        : 0.0;
    _selectionController.stop();
    _fromIndex = currentIndex;
    _targetIndex = index;
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final clearPressState = dragIndex != null || _isPressed;
    if (clearPressState) {
      if (disableAnimations) {
        _pressController.value = 0;
      } else {
        _pressController.reverse();
      }
      if (mounted) {
        // AnimatedBuilder only repaints the indicator. Rebuild the navigation
        // destinations as well so a released press cannot leave its selected
        // icon behind.
        setState(() {
          _dragIndex = null;
          _isPressed = false;
          _dragVelocity = 0;
          _dragDirection = 0;
          _gestureDirectionLocked = false;
          _isVerticalGesture = false;
        });
      }
    }

    if (disableAnimations) {
      _selectionController.value = 1;
      return;
    }

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
    final maxIndex = (widget.destinations.length - 1).toDouble();
    return ((x - _kIndicatorPadding) / _itemExtent - 0.5)
        .clamp(0.0, maxIndex)
        .toDouble();
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (_activePointer != null) return;

    _selectionController.stop();
    final index = _indexForX(event.localPosition.dx);
    _activePointer = event.pointer;
    _pendingPointerUp = null;
    _pointerDownPosition = event.localPosition;
    _lastPointerPosition = event.localPosition;
    _lastPointerTime = event.timeStamp;
    _gestureDirectionLocked = false;
    _isVerticalGesture = false;
    _dragStartIndex = index;
    _interactionCommitted = false;
    _dragVelocity = 0;
    _releaseVisualOffset = 0;
    _releaseShellOffset = 0;
    _releaseMotionIndex = 0;
    _releaseVelocityNorm = 0;
    _releaseTravel = 0;
    _releaseDragProgress = 0;
    setState(() {
      // The lens jumps under the finger on pointer-down, before a long-press
      // or horizontal-drag recognizer reaches its slop threshold.
      _dragIndex = index;
      _isPressed = true;
      _dragDirection = 0;
    });
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

    final dragIndex = _indexForX(event.localPosition.dx);
    final deltaX = event.localPosition.dx - _lastPointerPosition.dx;
    final dragDirection = deltaX.abs() > 0.1 ? deltaX.sign : _dragDirection;
    final elapsedMicros = (event.timeStamp - _lastPointerTime).inMicroseconds;
    final instantaneousVelocity = elapsedMicros > 0
        ? (deltaX / elapsedMicros * 1000000 / _itemExtent)
              .clamp(-4.0, 4.0)
              .toDouble()
        : 0.0;
    final smoothedVelocity =
        (_dragVelocity * 0.62 + instantaneousVelocity * 0.38)
            .clamp(-4.0, 4.0)
            .toDouble();
    _lastPointerPosition = event.localPosition;
    _lastPointerTime = event.timeStamp;
    if ((_dragIndex == null || (_dragIndex! - dragIndex).abs() > 0.001) &&
        mounted) {
      setState(() {
        _dragIndex = dragIndex;
        _dragDirection = dragDirection;
        _dragVelocity = smoothedVelocity;
      });
    } else if (mounted &&
        (dragDirection != _dragDirection ||
            (smoothedVelocity - _dragVelocity).abs() > 0.02)) {
      setState(() {
        _dragDirection = dragDirection;
        _dragVelocity = smoothedVelocity;
      });
    }
  }

  double _pointerVelocity(PointerUpEvent event) {
    final elapsedMicros = (event.timeStamp - _lastPointerTime).inMicroseconds;
    if (elapsedMicros <= 0) return 0;
    return (event.localPosition.dx - _lastPointerPosition.dx) /
        elapsedMicros *
        1000000 /
        _itemExtent;
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (event.pointer != _activePointer) return;

    final dragIndex = _dragIndex ?? _indexForX(event.localPosition.dx);
    final velocity = _pointerVelocity(event);
    _activePointer = null;
    _pendingPointerUp = event.pointer;

    // Let NavigationBar's tap recognizer win the arena first. A raw pointer
    // up arrives before onDestinationSelected; deferring this fallback keeps
    // same-tab taps and semantic activations from being swallowed.
    Future<void>.microtask(() {
      if (!mounted || _pendingPointerUp != event.pointer) return;
      _pendingPointerUp = null;
      if (_interactionCommitted) {
        _scheduleInteractionReset();
        return;
      }

      _interactionCommitted = true;
      if (_isVerticalGesture) {
        if (_dragIndex != null || _isPressed) {
          _animateTo(widget.selectedIndex.toDouble());
        }
        _scheduleInteractionReset();
        return;
      }

      // A disabled destination should remain a no-op when it was tapped.
      // Nearest-enabled snapping is reserved for an actual horizontal drag.
      if (!_gestureDirectionLocked) {
        _animateTo(widget.selectedIndex.toDouble());
        _scheduleInteractionReset();
        return;
      }

      final maxIndex = widget.destinations.length - 1;
      final nearestIndex = (dragIndex + velocity * 0.08).round().clamp(
        0,
        maxIndex,
      );
      final targetIndex = _nearestEnabledIndex(nearestIndex);
      if (targetIndex == null) {
        _animateTo(widget.selectedIndex.toDouble());
        _scheduleInteractionReset();
        return;
      }
      _animateTo(targetIndex.toDouble(), velocity: velocity);
      if (targetIndex != widget.selectedIndex) {
        widget.onDestinationSelected?.call(targetIndex);
      }
      _scheduleInteractionReset();
    });
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (event.pointer != _activePointer) return;

    final interactionCommitted = _interactionCommitted;
    _activePointer = null;
    _pendingPointerUp = null;
    if (!interactionCommitted) {
      _interactionCommitted = true;
      _animateTo(widget.selectedIndex.toDouble());
    }
    _scheduleInteractionReset();
  }

  bool _destinationEnabled(int index) {
    final destination = widget.destinations[index];
    if (destination is FloatingNavigationDestination) {
      return destination.enabled;
    }
    if (destination is NavigationDestination) {
      return destination.enabled;
    }
    return true;
  }

  int? _nearestEnabledIndex(int index) {
    final maxIndex = widget.destinations.length - 1;
    final clampedIndex = index.clamp(0, maxIndex).toInt();
    if (_destinationEnabled(clampedIndex)) return clampedIndex;

    for (var distance = 1; distance <= maxIndex; distance++) {
      final left = clampedIndex - distance;
      if (left >= 0 && _destinationEnabled(left)) return left;
      final right = clampedIndex + distance;
      if (right <= maxIndex && _destinationEnabled(right)) return right;
    }
    return null;
  }

  List<Widget> _buildVisualDestinations({
    required double indicatorIndex,
    required ColorScheme colorScheme,
    required NavigationBarThemeData navigationBarTheme,
  }) {
    final defaultIconTheme = navigationBarTheme.iconTheme;
    final inactiveTheme =
        defaultIconTheme?.resolve(const <WidgetState>{}) ??
        IconThemeData(color: colorScheme.onSurfaceVariant, size: 24);
    final activeTheme =
        defaultIconTheme?.resolve(const <WidgetState>{WidgetState.selected}) ??
        IconThemeData(color: colorScheme.onSecondaryContainer, size: 24);

    return List<Widget>.generate(widget.destinations.length, (index) {
      final destination = _LiquidDestinationData.fromWidget(
        widget.destinations[index],
      );
      if (destination == null) return widget.destinations[index];

      final rawProgress = (1 - (indicatorIndex - index).abs()).clamp(0.0, 1.0);
      final selectionProgress = Curves.easeInOutCubic.transform(rawProgress);
      final icon = _LiquidDestinationIcon(
        icon: destination.icon,
        selectedIcon: destination.selectedIcon,
        iconWrapper: destination.iconWrapper,
        selectionProgress: destination.enabled ? selectionProgress : 0,
        inactiveTheme: inactiveTheme,
        activeTheme: activeTheme,
      );
      return NavigationDestination(
        icon: icon,
        selectedIcon: _LiquidDestinationIcon(
          icon: destination.icon,
          selectedIcon: destination.selectedIcon,
          iconWrapper: destination.iconWrapper,
          selectionProgress: destination.enabled ? selectionProgress : 0,
          inactiveTheme: inactiveTheme,
          activeTheme: activeTheme,
        ),
        label: destination.label,
        tooltip: destination.tooltip,
        enabled: destination.enabled,
      );
    });
  }

  Widget _buildLiquidLens({
    required bool reflective,
    required bool isDark,
    required Color effectiveIndicatorColor,
    required ShapeBorder effectiveIndicatorShape,
  }) {
    return AnimatedBuilder(
      animation: _indicatorListenable,
      builder: (context, _) {
        final dragIndex = _dragIndex;
        final indicatorIndex = dragIndex ?? _animatedIndex;
        final pressProgress = Curves.easeOutCubic.transform(
          _pressController.value,
        );
        final releaseProgress = _releaseProgress;
        final travel = dragIndex != null
            ? (indicatorIndex - _dragStartIndex).abs()
            : _releaseTravel * releaseProgress;
        final stretchAmount = dragIndex != null
            ? math.min(22.0, travel * 14) * math.min(1.0, travel)
            : math.min(22.0, _releaseTravel * 14) * releaseProgress;
        final dragProgress = dragIndex != null
            ? (_gestureDirectionLocked && !_isVerticalGesture ? 1.0 : 0.0)
            : _releaseDragProgress * releaseProgress;
        final baseWidth =
            widget.labelBehavior ==
                NavigationDestinationLabelBehavior.alwaysHide
            ? math.max(48.0, math.min(60.0, _itemExtent - 12))
            : math.max(56.0, math.min(78.0, _itemExtent - 4));
        final indicatorWidth =
            baseWidth + stretchAmount + 24 * pressProgress + 8 * dragProgress;
        final indicatorHeight =
            _kNavigationHeight - 12 + 20 * pressProgress + 3 * dragProgress;
        final centerX =
            _kIndicatorPadding + _itemExtent * (indicatorIndex + 0.5);
        final transitionProgress = math.sin(
          math.pi * _selectionController.value,
        );
        final motionIndex = _visualMotionIndex(
          indicatorIndex,
          transitionProgress,
        );
        final opticalMotionIndex = dragIndex != null
            ? motionIndex
            : motionIndex + _releaseMotionIndex * _releaseProgress;
        final velocityNorm = dragIndex != null
            ? _dragVelocityNorm
            : _releaseVelocityNorm * _releaseProgress;
        final visualOffset = dragIndex != null
            ? (motionIndex * 2.6 + velocityNorm * 4.0)
                  .clamp(-9.0, 9.0)
                  .toDouble()
            : (motionIndex * 2.6 + _releaseVisualOffset * _releaseProgress)
                  .clamp(-9.0, 9.0)
                  .toDouble();
        final left = centerX - indicatorWidth / 2 + visualOffset;
        final reflectionStrength =
            (0.22 + pressProgress * 0.58 + dragProgress * 0.16)
                .clamp(0.0, 1.0)
                .toDouble();
        final rawReflectionPhase =
            indicatorIndex * 0.43 +
            pressProgress * 0.27 +
            opticalMotionIndex * 0.04 +
            velocityNorm * 0.09;
        final reflectionPhase = rawReflectionPhase;
        final refractionOffset =
            (opticalMotionIndex * 2.2 +
                    velocityNorm * (2.5 + pressProgress * 3))
                .clamp(-10.0, 10.0)
                .toDouble();
        final signedDragOffset = dragIndex != null
            ? motionIndex * _itemExtent
            : _releaseMotionIndex * _itemExtent * releaseProgress;
        final lensShape = _LiquidLensShape(
          baseShape: effectiveIndicatorShape,
          pressProgress: pressProgress,
          dragOffset: signedDragOffset,
          velocity: velocityNorm,
        );

        return Positioned(
          key: const ValueKey('liquidGlassIndicator'),
          left: left,
          top: (_kNavigationHeight - indicatorHeight) / 2,
          width: indicatorWidth,
          height: indicatorHeight,
          child: IgnorePointer(
            child: ClipPath(
              clipper: ShapeBorderClipper(shape: lensShape),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (reflective)
                    RawMagnifier(
                      size: Size(indicatorWidth, indicatorHeight),
                      magnificationScale: 1.055 + pressProgress * 0.12,
                      focalPointOffset: Offset(-refractionOffset, 0),
                      decoration: MagnifierDecoration(
                        opacity: (isDark ? 0.90 : 0.88) + pressProgress * 0.08,
                        shape: lensShape,
                      ),
                    ),
                  DecoratedBox(
                    decoration: ShapeDecoration(
                      color: effectiveIndicatorColor.withValues(
                        alpha:
                            (effectiveIndicatorColor.a *
                                        (reflective ? 0.22 : 0.40) -
                                    pressProgress * 0.05)
                                .clamp(0.0, 1.0)
                                .toDouble(),
                      ),
                      shape: lensShape,
                    ),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withValues(
                            alpha: reflective
                                ? (isDark ? 0.10 : 0.16)
                                : (isDark ? 0.07 : 0.11),
                          ),
                          Colors.transparent,
                          Colors.black.withValues(
                            alpha: isDark ? 0.06 : 0.025,
                          ),
                        ],
                        stops: const [0.0, 0.48, 1.0],
                      ),
                    ),
                  ),
                  CustomPaint(
                    painter: _LiquidIndicatorBorderPainter(
                      shape: lensShape,
                      color: Colors.white.withValues(
                        alpha: (isDark ? 0.28 : 0.42) + pressProgress * 0.24,
                      ),
                      width: 1 + pressProgress * 0.5,
                    ),
                  ),
                  if (reflective)
                    CustomPaint(
                      painter: _LiquidReflectionPainter(
                        shape: lensShape,
                        phase: reflectionPhase,
                        velocity: velocityNorm,
                        pressProgress: pressProgress,
                        progress: reflectionStrength,
                        isDark: isDark,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final navigationBarTheme = NavigationBarTheme.of(context);
    final colorScheme = theme.colorScheme;
    final viewPadding = MediaQuery.viewPaddingOf(context);
    final isDark = colorScheme.brightness == Brightness.dark;
    final preferredWidth = widget.destinations.length * _kIndicatorWidth;
    final availableWidth = math.max(
      0.0,
      MediaQuery.sizeOf(context).width - viewPadding.horizontal,
    );
    final barWidth = math.min(preferredWidth, availableWidth);
    _itemExtent = math.max(
      1.0,
      (barWidth - 2 * _kIndicatorPadding) / widget.destinations.length,
    );

    final tintColor =
        widget.surfaceTintColor ??
        navigationBarTheme.surfaceTintColor ??
        colorScheme.surfaceTint;
    final defaultGlassColor = colorScheme.surfaceContainer.withValues(
      alpha: isDark ? 0.22 : 0.15,
    );
    final glassColor =
        widget.backgroundColor ??
        Color.alphaBlend(
          tintColor.withValues(alpha: isDark ? 0.06 : 0.035),
          defaultGlassColor,
        );
    final borderColor = Colors.white.withValues(
      alpha: isDark ? 0.30 : 0.42,
    );
    final effectiveShadowColor =
        widget.shadowColor ??
        navigationBarTheme.shadowColor ??
        Colors.black.withValues(alpha: isDark ? 0.34 : 0.18);
    final effectiveElevation =
        widget.elevation ?? navigationBarTheme.elevation ?? 3.0;
    final effectiveIndicatorColor =
        widget.indicatorColor ??
        Color.alphaBlend(
          colorScheme.primary.withValues(alpha: isDark ? 0.20 : 0.13),
          Colors.white.withValues(alpha: isDark ? 0.10 : 0.26),
        );
    final effectiveIndicatorShape =
        widget.indicatorShape ??
        navigationBarTheme.indicatorShape ??
        _kNavigationShape;
    final sourceOverlayColor =
        widget.overlayColor ?? navigationBarTheme.overlayColor;
    final effectiveOverlayColor = WidgetStateProperty.resolveWith<Color?>((
      states,
    ) {
      if (states.contains(WidgetState.pressed)) {
        return Colors.transparent;
      }
      return sourceOverlayColor?.resolve(states);
    });
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final reflective = _usesReflectiveQuality && !disableAnimations;

    return UnconstrainedBox(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          viewPadding.left,
          0,
          viewPadding.right,
          widget.bottomPadding + viewPadding.bottom,
        ),
        child: SizedBox(
          key: const ValueKey('liquidGlassNavigationBar'),
          height: _kNavigationHeight,
          width: barWidth,
          child: AnimatedBuilder(
            animation: _indicatorListenable,
            // The bar follows the liquid motion visually, while the fixed
            // layout coordinates keep touch targets aligned with the page.
            builder: (context, child) => Transform.translate(
              offset: Offset(_visualBarOffset, 0),
              transformHitTests: false,
              child: child,
            ),
            child: RepaintBoundary(
              key: const ValueKey('liquidGlassVisualShell'),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: _kBorderRadius,
                  boxShadow: [
                    BoxShadow(
                      color: effectiveShadowColor,
                      blurRadius: 20 + effectiveElevation * 2,
                      spreadRadius: -6,
                      offset: Offset(0, 5 + effectiveElevation),
                    ),
                  ],
                ),
                child: Stack(
                  fit: StackFit.expand,
                  clipBehavior: Clip.none,
                  children: [
                    ClipPath(
                      clipper: const ShapeBorderClipper(
                        shape: _kNavigationShape,
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          // Clip the filter to the pill so only the bar's
                          // backdrop is sampled and the rest of the page stays
                          // untouched.
                          BackdropFilter(
                            filter: reflective
                                ? _kLiquidReflectiveBlur
                                : _kLiquidFrostedBlur,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: glassColor,
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Colors.white.withValues(
                                      alpha: isDark ? 0.06 : 0.11,
                                    ),
                                    Colors.transparent,
                                    Colors.black.withValues(
                                      alpha: isDark ? 0.07 : 0.025,
                                    ),
                                  ],
                                  stops: const [0.0, 0.44, 1.0],
                                ),
                              ),
                            ),
                          ),
                          AnimatedBuilder(
                            animation: _pressController,
                            builder: (context, child) {
                              final pressProgress = Curves.easeOutCubic
                                  .transform(
                                    _pressController.value,
                                  );
                              return ColoredBox(
                                color: Colors.white.withValues(
                                  alpha: (isDark ? 0.07 : 0.04) * pressProgress,
                                ),
                                child: child,
                              );
                            },
                            child: const SizedBox.expand(),
                          ),
                          IgnorePointer(
                            child: DecoratedBox(
                              decoration: ShapeDecoration(
                                color: Colors.transparent,
                                shape: RoundedSuperellipseBorder(
                                  side: BorderSide(color: borderColor),
                                  borderRadius: _kBorderRadius,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: _handlePointerDown,
                      onPointerMove: _handlePointerMove,
                      onPointerUp: _handlePointerUp,
                      onPointerCancel: _handlePointerCancel,
                      child: AnimatedBuilder(
                        animation: _indicatorListenable,
                        builder: (context, _) {
                          final visualIndex = _dragIndex ?? _animatedIndex;
                          return Padding(
                            padding: const EdgeInsets.all(_kIndicatorPadding),
                            child: MediaQuery.removePadding(
                              context: context,
                              removeLeft: true,
                              removeTop: true,
                              removeRight: true,
                              removeBottom: true,
                              child: NavigationBar(
                                // NavigationBar keeps its committed semantic
                                // selection. The icons below interpolate from
                                // the continuous glass position instead of
                                // switching at a rounded drag index.
                                animationDuration: Duration.zero,
                                selectedIndex: widget.selectedIndex,
                                destinations: _buildVisualDestinations(
                                  indicatorIndex: visualIndex,
                                  colorScheme: colorScheme,
                                  navigationBarTheme: navigationBarTheme,
                                ),
                                onDestinationSelected:
                                    _handleDestinationSelected,
                                backgroundColor: Colors.transparent,
                                elevation: 0,
                                shadowColor: Colors.transparent,
                                surfaceTintColor: Colors.transparent,
                                indicatorColor: Colors.transparent,
                                height:
                                    _kNavigationHeight - 2 * _kIndicatorPadding,
                                labelBehavior: widget.labelBehavior,
                                overlayColor: effectiveOverlayColor,
                                labelTextStyle: widget.labelTextStyle,
                                labelPadding:
                                    widget.labelPadding ??
                                    navigationBarTheme.labelPadding ??
                                    const EdgeInsets.only(top: 2),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    _buildLiquidLens(
                      reflective: reflective,
                      isDark: isDark,
                      effectiveIndicatorColor: effectiveIndicatorColor,
                      effectiveIndicatorShape: effectiveIndicatorShape,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LiquidDestinationData {
  const _LiquidDestinationData({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.tooltip,
    required this.enabled,
    required this.iconWrapper,
  });

  final Widget icon;
  final Widget? selectedIcon;
  final String label;
  final String? tooltip;
  final bool enabled;
  final Widget Function(Widget icon)? iconWrapper;

  static _LiquidDestinationData? fromWidget(Widget widget) {
    if (widget is FloatingNavigationDestination) {
      return _LiquidDestinationData(
        icon: widget.icon,
        selectedIcon: widget.selectedIcon,
        label: widget.label,
        tooltip: widget.tooltip,
        enabled: widget.enabled,
        iconWrapper: widget.iconWrapper,
      );
    }
    if (widget is NavigationDestination) {
      return _LiquidDestinationData(
        icon: widget.icon,
        selectedIcon: widget.selectedIcon,
        label: widget.label,
        tooltip: widget.tooltip,
        enabled: widget.enabled,
        iconWrapper: null,
      );
    }
    return null;
  }
}

class _LiquidDestinationIcon extends StatelessWidget {
  const _LiquidDestinationIcon({
    required this.icon,
    required this.selectedIcon,
    required this.iconWrapper,
    required this.selectionProgress,
    required this.inactiveTheme,
    required this.activeTheme,
  });

  final Widget icon;
  final Widget? selectedIcon;
  final Widget Function(Widget icon)? iconWrapper;
  final double selectionProgress;
  final IconThemeData inactiveTheme;
  final IconThemeData activeTheme;

  @override
  Widget build(BuildContext context) {
    final progress = selectionProgress.clamp(0.0, 1.0).toDouble();
    final color = Color.lerp(
      inactiveTheme.color ?? Colors.transparent,
      activeTheme.color ?? Colors.transparent,
      progress,
    )!;
    final highlightColor = Color.lerp(
      color,
      Colors.white,
      Theme.of(context).brightness == Brightness.dark ? 0.08 : 0.14,
    )!;
    final iconTheme = IconThemeData.lerp(
      inactiveTheme,
      activeTheme,
      progress,
    ).copyWith(color: color);

    Widget layer(Widget child, double opacity) => Opacity(
      opacity: opacity,
      child: IconTheme(data: iconTheme, child: child),
    );

    final transitionIcon = ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [highlightColor, color],
      ).createShader(bounds),
      child: Stack(
        alignment: Alignment.center,
        children: [
          layer(icon, 1 - progress),
          layer(selectedIcon ?? icon, progress),
        ],
      ),
    );
    return ExcludeSemantics(
      child: iconWrapper?.call(transitionIcon) ?? transitionIcon,
    );
  }
}

class _LiquidLensShape extends ShapeBorder {
  const _LiquidLensShape({
    required this.baseShape,
    required this.pressProgress,
    required this.dragOffset,
    required this.velocity,
  });

  final ShapeBorder baseShape;
  final double pressProgress;
  final double dragOffset;
  final double velocity;

  @override
  EdgeInsetsGeometry get dimensions => baseShape.dimensions;

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    if (pressProgress <= 0.001 &&
        dragOffset.abs() <= 0.001 &&
        velocity.abs() <= 0.001) {
      return baseShape.getOuterPath(rect, textDirection: textDirection);
    }
    return _buildLiquidLensPath(
      rect,
      baseShape: baseShape,
      pressProgress: pressProgress,
      dragOffset: dragOffset,
      velocity: velocity,
      textDirection: textDirection,
    );
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    final innerRect = rect.deflate(1.0);
    if (pressProgress <= 0.001 &&
        dragOffset.abs() <= 0.001 &&
        velocity.abs() <= 0.001) {
      return baseShape.getInnerPath(innerRect, textDirection: textDirection);
    }
    return _buildLiquidLensPath(
      innerRect,
      baseShape: baseShape,
      pressProgress: pressProgress,
      dragOffset: dragOffset,
      velocity: velocity,
      textDirection: textDirection,
    );
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (pressProgress <= 0.001 &&
        dragOffset.abs() <= 0.001 &&
        velocity.abs() <= 0.001) {
      baseShape.paint(canvas, rect, textDirection: textDirection);
    }
  }

  @override
  ShapeBorder scale(double t) => _LiquidLensShape(
    baseShape: baseShape.scale(t),
    pressProgress: pressProgress * t,
    dragOffset: dragOffset * t,
    velocity: velocity * t,
  );
}

Path _buildLiquidLensPath(
  Rect rect, {
  required ShapeBorder baseShape,
  required double pressProgress,
  required double dragOffset,
  required double velocity,
  TextDirection? textDirection,
}) {
  final bounds = rect.deflate(0.6);
  if (bounds.width <= 1 || bounds.height <= 1) {
    return Path()..addRect(rect);
  }

  final basePath = baseShape.getOuterPath(
    bounds,
    textDirection: textDirection,
  );
  final metrics = basePath.computeMetrics(forceClosed: true).toList();
  if (metrics.isEmpty) return basePath;
  final metric = metrics.reduce(
    (longest, current) => current.length > longest.length ? current : longest,
  );
  if (metric.length <= 0) return basePath;

  final motion =
      (dragOffset / math.max(1.0, bounds.width * 0.45) + velocity * 0.24)
          .clamp(-1.0, 1.0)
          .toDouble();
  final pressure = pressProgress.clamp(0.0, 1.0).toDouble();
  final center = bounds.center;
  const sampleCount = 64;
  final points = <Offset>[];

  for (var index = 0; index < sampleCount; index++) {
    final distance = metric.length * index / sampleCount;
    final tangent = metric.getTangentForOffset(distance);
    if (tangent == null) continue;

    final point = tangent.position;
    var normal = Offset(-tangent.vector.dy, tangent.vector.dx);
    final normalLength = normal.distance;
    if (normalLength <= 0.0001) continue;
    normal /= normalLength;
    final radial = point - center;
    if (normal.dx * radial.dx + normal.dy * radial.dy < 0) {
      normal = -normal;
    }

    final signedExposure = normal.dx * motion;
    final leadingWeight = _smoothStep(
      ((signedExposure + 0.08) / 0.92).clamp(0.0, 1.0).toDouble(),
    );
    final trailingWeight = _smoothStep(
      ((-signedExposure + 0.08) / 0.92).clamp(0.0, 1.0).toDouble(),
    );
    final dragStrength = motion.abs();
    final pressSwell = pressure * 1.5;
    final dragBulge =
        dragStrength * (leadingWeight * 4.6 - trailingWeight * 1.2);
    final displacement = (pressSwell + dragBulge).clamp(-1.6, 5.2).toDouble();
    points.add(point + normal * displacement);
  }

  if (points.length < 4) return basePath;

  final smoothPath = Path()..moveTo(points.first.dx, points.first.dy);
  const tension = 0.82;
  const controlScale = tension / 6.0;
  for (var index = 0; index < points.length; index++) {
    final previous = points[(index - 1 + points.length) % points.length];
    final current = points[index];
    final next = points[(index + 1) % points.length];
    final nextNext = points[(index + 2) % points.length];
    final firstControl = current + (next - previous) * controlScale;
    final secondControl = next - (nextNext - current) * controlScale;
    smoothPath.cubicTo(
      firstControl.dx,
      firstControl.dy,
      secondControl.dx,
      secondControl.dy,
      next.dx,
      next.dy,
    );
  }
  return smoothPath..close();
}

double _smoothStep(double value) {
  final t = value.clamp(0.0, 1.0).toDouble();
  return t * t * (3.0 - 2.0 * t);
}

class _LiquidReflectionPainter extends CustomPainter {
  const _LiquidReflectionPainter({
    required this.shape,
    required this.phase,
    required this.velocity,
    required this.pressProgress,
    required this.progress,
    required this.isDark,
  });

  final ShapeBorder shape;
  final double phase;
  final double velocity;
  final double pressProgress;
  final double progress;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final path = shape.getOuterPath(rect.deflate(0.7));
    final energy = (progress * (0.72 + pressProgress * 0.28))
        .clamp(0.0, 1.0)
        .toDouble();
    final phaseAngle = phase * math.pi * 2;
    final tone = isDark ? 0.84 : 1.0;
    final edgeColors = [
      const Color(0xFF43E6FF).withValues(alpha: 0.34 * tone * energy),
      const Color(0xFF6C9BFF).withValues(alpha: 0.28 * tone * energy),
      Colors.white.withValues(alpha: 0.34 * tone * energy),
      const Color(0xFFFFC65A).withValues(alpha: 0.30 * tone * energy),
      const Color(0xFFFF71C8).withValues(alpha: 0.22 * tone * energy),
      const Color(0xFF43E6FF).withValues(alpha: 0.34 * tone * energy),
    ];
    final rotation = GradientRotation(phaseAngle * 0.62 + velocity * 0.25);

    canvas
      ..save()
      ..clipPath(path);

    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.6 + pressProgress * 2.2
      ..strokeCap = StrokeCap.round
      ..blendMode = BlendMode.screen
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2.8 + pressProgress)
      ..shader = SweepGradient(
        colors: edgeColors,
        stops: const [0.0, 0.18, 0.38, 0.58, 0.78, 1.0],
        transform: rotation,
      ).createShader(rect.inflate(2.0));
    canvas.drawPath(path, glowPaint);

    final rimPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0 + energy * 1.15 + pressProgress * 0.45
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        colors: edgeColors,
        stops: const [0.0, 0.18, 0.38, 0.58, 0.78, 1.0],
        transform: rotation,
      ).createShader(rect);
    canvas.drawPath(path, rimPaint);

    final innerPath = shape.getOuterPath(rect.deflate(2.0));
    final innerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.65 + pressProgress * 0.45
      ..color = Colors.white.withValues(alpha: (0.14 + energy * 0.20) * tone);
    canvas
      ..drawPath(innerPath, innerPaint)
      ..restore();
  }

  @override
  bool shouldRepaint(_LiquidReflectionPainter oldDelegate) =>
      oldDelegate.shape != shape ||
      oldDelegate.phase != phase ||
      oldDelegate.velocity != velocity ||
      oldDelegate.pressProgress != pressProgress ||
      oldDelegate.progress != progress ||
      oldDelegate.isDark != isDark;
}

class _LiquidIndicatorBorderPainter extends CustomPainter {
  const _LiquidIndicatorBorderPainter({
    required this.shape,
    required this.color,
    required this.width,
  });

  final ShapeBorder shape;
  final Color color;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final path = shape.getOuterPath((Offset.zero & size).deflate(width / 2));
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width,
    );
  }

  @override
  bool shouldRepaint(_LiquidIndicatorBorderPainter oldDelegate) {
    return oldDelegate.shape != shape ||
        oldDelegate.color != color ||
        oldDelegate.width != width;
  }
}

/// Compatibility wrapper for existing PiliMax call sites.
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
  Widget build(BuildContext context) => NavigationDestination(
    icon: iconWrapper?.call(icon) ?? icon,
    selectedIcon: selectedIcon == null
        ? null
        : iconWrapper?.call(selectedIcon!) ?? selectedIcon,
    label: label,
    tooltip: tooltip,
    enabled: enabled,
  );
}
