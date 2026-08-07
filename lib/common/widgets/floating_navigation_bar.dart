import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart' show SpringDescription, SpringSimulation;

const double _kNavigationHeight = 64.0;
const double _kIndicatorWidth = 86.0;
const double _kIndicatorPadding = 4.0;
const Duration _kLiquidPressDuration = Duration(milliseconds: 130);
final ui.ImageFilter _kLiquidGlassBlur = ui.ImageFilter.blur(
  sigmaX: 12,
  sigmaY: 12,
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

  double get _animatedIndex =>
      _fromIndex + (_targetIndex - _fromIndex) * _selectionController.value;

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
  }

  @override
  void didUpdateWidget(_LiquidGlassNavigationBar oldWidget) {
    super.didUpdateWidget(oldWidget);
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
    setState(() {
      // The lens jumps under the finger on pointer-down, before a long-press
      // or horizontal-drag recognizer reaches its slop threshold.
      _dragIndex = index;
      _isPressed = true;
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
    _lastPointerPosition = event.localPosition;
    _lastPointerTime = event.timeStamp;
    if ((_dragIndex == null || (_dragIndex! - dragIndex).abs() > 0.001) &&
        mounted) {
      setState(() => _dragIndex = dragIndex);
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
      alpha: isDark ? 0.28 : 0.22,
    );
    final glassColor =
        widget.backgroundColor ??
        Color.alphaBlend(
          tintColor.withValues(alpha: isDark ? 0.08 : 0.05),
          defaultGlassColor,
        );
    final borderColor = Colors.white.withValues(
      alpha: isDark ? 0.34 : 0.48,
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

    return UnconstrainedBox(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          viewPadding.left,
          0,
          viewPadding.right,
          widget.bottomPadding + viewPadding.bottom,
        ),
        child: SizedBox(
          height: _kNavigationHeight,
          width: barWidth,
          child: RepaintBoundary(
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
                          filter: _kLiquidGlassBlur,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: glassColor,
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Colors.white.withValues(
                                    alpha: isDark ? 0.08 : 0.16,
                                  ),
                                  Colors.transparent,
                                  Colors.black.withValues(
                                    alpha: isDark ? 0.10 : 0.04,
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
                            final pressProgress = Curves.easeOutCubic.transform(
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
                  AnimatedBuilder(
                    animation: _indicatorListenable,
                    builder: (context, _) {
                      final dragIndex = _dragIndex;
                      final indicatorIndex = dragIndex ?? _animatedIndex;
                      final pressProgress = Curves.easeOutCubic.transform(
                        _pressController.value,
                      );
                      final travel = dragIndex != null
                          ? (indicatorIndex - _dragStartIndex).abs()
                          : (_targetIndex - _fromIndex).abs();
                      final stretchProgress = dragIndex != null
                          ? math.min(1.0, travel)
                          : math.sin(math.pi * _selectionController.value);
                      final baseWidth =
                          widget.labelBehavior ==
                              NavigationDestinationLabelBehavior.alwaysHide
                          ? math.max(48.0, math.min(60.0, _itemExtent - 12))
                          : math.max(56.0, math.min(78.0, _itemExtent - 4));
                      final indicatorWidth =
                          baseWidth +
                          math.min(18.0, travel * 12) * stretchProgress +
                          26 * pressProgress;
                      final indicatorHeight =
                          _kNavigationHeight - 12 + 8 * pressProgress;
                      final centerX =
                          _kIndicatorPadding +
                          _itemExtent * (indicatorIndex + 0.5);
                      final unclampedLeft = centerX - indicatorWidth / 2;
                      final left = unclampedLeft.clamp(
                        _kIndicatorPadding,
                        barWidth - _kIndicatorPadding - indicatorWidth,
                      );

                      return Positioned(
                        key: const ValueKey('liquidGlassIndicator'),
                        left: left,
                        top: (_kNavigationHeight - indicatorHeight) / 2,
                        width: indicatorWidth,
                        height: indicatorHeight,
                        child: ClipPath(
                          clipper: ShapeBorderClipper(
                            shape: effectiveIndicatorShape,
                          ),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              RawMagnifier(
                                size: Size(indicatorWidth, indicatorHeight),
                                magnificationScale:
                                    1.015 + pressProgress * 0.085,
                                decoration: MagnifierDecoration(
                                  opacity:
                                      (isDark ? 0.74 : 0.68) +
                                      pressProgress * 0.14,
                                  shape: effectiveIndicatorShape,
                                ),
                              ),
                              DecoratedBox(
                                decoration: ShapeDecoration(
                                  color: effectiveIndicatorColor.withValues(
                                    alpha:
                                        effectiveIndicatorColor.a *
                                        (0.68 - pressProgress * 0.16),
                                  ),
                                  shape: effectiveIndicatorShape,
                                ),
                              ),
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.white.withValues(
                                        alpha: isDark ? 0.12 : 0.22,
                                      ),
                                      Colors.transparent,
                                      Colors.black.withValues(
                                        alpha: isDark ? 0.12 : 0.05,
                                      ),
                                    ],
                                    stops: const [0.0, 0.48, 1.0],
                                  ),
                                ),
                              ),
                              CustomPaint(
                                painter: _LiquidIndicatorBorderPainter(
                                  shape: effectiveIndicatorShape,
                                  color: Colors.white.withValues(
                                    alpha:
                                        (isDark ? 0.30 : 0.48) +
                                        pressProgress * 0.20,
                                  ),
                                  width: 1 + pressProgress * 0.5,
                                ),
                              ),
                              Align(
                                alignment: Alignment.topCenter,
                                child: FractionallySizedBox(
                                  widthFactor: 0.68,
                                  child: ColoredBox(
                                    color: Colors.white.withValues(
                                      alpha: isDark ? 0.16 : 0.42,
                                    ),
                                    child: const SizedBox(height: 1),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: _handlePointerDown,
                    onPointerMove: _handlePointerMove,
                    onPointerUp: _handlePointerUp,
                    onPointerCancel: _handlePointerCancel,
                    child: Padding(
                      padding: const EdgeInsets.all(_kIndicatorPadding),
                      child: MediaQuery.removePadding(
                        context: context,
                        removeLeft: true,
                        removeTop: true,
                        removeRight: true,
                        removeBottom: true,
                        child: NavigationBar(
                          // The glass lens owns selection motion. Keeping
                          // NavigationBar's icon transition instantaneous
                          // prevents a second animation from competing with
                          // the lens during a press or drag.
                          animationDuration: Duration.zero,
                          selectedIndex: _dragIndex == null
                              ? widget.selectedIndex
                              : _dragIndex!
                                    .round()
                                    .clamp(
                                      0,
                                      widget.destinations.length - 1,
                                    )
                                    .toInt(),
                          destinations: widget.destinations,
                          onDestinationSelected: _handleDestinationSelected,
                          backgroundColor: Colors.transparent,
                          elevation: 0,
                          shadowColor: Colors.transparent,
                          surfaceTintColor: Colors.transparent,
                          indicatorColor: Colors.transparent,
                          height: _kNavigationHeight - 2 * _kIndicatorPadding,
                          labelBehavior: widget.labelBehavior,
                          overlayColor: effectiveOverlayColor,
                          labelTextStyle: widget.labelTextStyle,
                          labelPadding:
                              widget.labelPadding ??
                              navigationBarTheme.labelPadding ??
                              const EdgeInsets.only(top: 2),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
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
  });

  final Widget icon;
  final Widget? selectedIcon;
  final String label;
  final String? tooltip;
  final bool enabled;

  @override
  Widget build(BuildContext context) => NavigationDestination(
    icon: icon,
    selectedIcon: selectedIcon,
    label: label,
    tooltip: tooltip,
    enabled: enabled,
  );
}
