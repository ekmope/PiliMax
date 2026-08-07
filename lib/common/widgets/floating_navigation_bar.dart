import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart' show SpringDescription, SpringSimulation;

const double _kNavigationHeight = 64.0;
const double _kIndicatorWidth = 86.0;
const double _kIndicatorPadding = 4.0;
const Duration _kLiquidSelectionDuration = Duration(milliseconds: 240);
final ui.ImageFilter _kLiquidGlassBlur = ui.ImageFilter.blur(
  sigmaX: 20,
  sigmaY: 20,
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
    with SingleTickerProviderStateMixin {
  late final AnimationController _selectionController;
  late double _fromIndex;
  late double _targetIndex;
  double? _dragIndex;
  double _dragStartIndex = 0;
  double _dragStartX = 0;
  double _itemExtent = _kIndicatorWidth;

  double get _animatedIndex =>
      _fromIndex + (_targetIndex - _fromIndex) * _selectionController.value;

  @override
  void initState() {
    super.initState();
    _fromIndex = widget.selectedIndex.toDouble();
    _targetIndex = _fromIndex;
    _selectionController = AnimationController(vsync: this, value: 1);
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
    super.dispose();
  }

  void _animateTo(double index, {double velocity = 0}) {
    // The indicator keeps a continuous position so taps and drags share one
    // spring instead of restarting separate per-destination animations.
    final currentIndex = _dragIndex ?? _animatedIndex;
    _selectionController.stop();
    _fromIndex = currentIndex;
    _targetIndex = index;
    _dragIndex = null;

    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
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
    _animateTo(index.toDouble());
    widget.onDestinationSelected?.call(index);
  }

  void _handleDragStart(DragStartDetails details) {
    _selectionController.stop();
    _dragStartIndex = _animatedIndex;
    _dragStartX = details.localPosition.dx;
    setState(() => _dragIndex = _dragStartIndex);
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    final maxIndex = (widget.destinations.length - 1).toDouble();
    final dragIndex =
        _dragStartIndex +
        (details.localPosition.dx - _dragStartX) / _itemExtent;
    setState(
      () => _dragIndex = dragIndex.clamp(0.0, maxIndex).toDouble(),
    );
  }

  void _handleDragEnd(DragEndDetails details) {
    final dragIndex = _dragIndex;
    if (dragIndex == null) return;

    final velocity = details.velocity.pixelsPerSecond.dx / _itemExtent;
    final maxIndex = widget.destinations.length - 1;
    final nearestIndex = (dragIndex + velocity * 0.08).round().clamp(
      0,
      maxIndex,
    );
    final targetIndex = _nearestEnabledIndex(nearestIndex);
    if (targetIndex == null) {
      _animateTo(widget.selectedIndex.toDouble());
      return;
    }
    _animateTo(targetIndex.toDouble(), velocity: velocity);
    if (targetIndex != widget.selectedIndex) {
      widget.onDestinationSelected?.call(targetIndex);
    }
  }

  void _handleDragCancel() {
    _animateTo(widget.selectedIndex.toDouble());
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
      alpha: isDark ? 0.52 : 0.46,
    );
    final glassColor =
        widget.backgroundColor ??
        Color.alphaBlend(
          tintColor.withValues(alpha: isDark ? 0.08 : 0.05),
          defaultGlassColor,
        );
    final borderColor = Colors.white.withValues(
      alpha: isDark ? 0.18 : 0.46,
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
        return colorScheme.onSurface.withValues(alpha: 0.05);
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
              child: ClipPath(
                clipper: const ShapeBorderClipper(shape: _kNavigationShape),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Clip the filter to the pill so only the bar's backdrop
                    // is sampled and the rest of the page stays untouched.
                    BackdropFilter(
                      filter: _kLiquidGlassBlur,
                      child: ColoredBox(color: glassColor),
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
                    AnimatedBuilder(
                      animation: _selectionController,
                      builder: (context, _) {
                        final dragIndex = _dragIndex;
                        final indicatorIndex = dragIndex ?? _animatedIndex;
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
                            : math.max(56.0, math.min(72.0, _itemExtent - 8));
                        final indicatorWidth =
                            baseWidth +
                            math.min(18.0, travel * 12) * stretchProgress;
                        final centerX =
                            _kIndicatorPadding +
                            _itemExtent * (indicatorIndex + 0.5);

                        return Positioned(
                          left: centerX - indicatorWidth / 2,
                          top: 6,
                          width: indicatorWidth,
                          height: _kNavigationHeight - 12,
                          child: ClipPath(
                            clipper: ShapeBorderClipper(
                              shape: effectiveIndicatorShape,
                            ),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                DecoratedBox(
                                  decoration: ShapeDecoration(
                                    color: effectiveIndicatorColor,
                                    shape: effectiveIndicatorShape,
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
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragStart: _handleDragStart,
                      onHorizontalDragUpdate: _handleDragUpdate,
                      onHorizontalDragEnd: _handleDragEnd,
                      onHorizontalDragCancel: _handleDragCancel,
                      child: Padding(
                        padding: const EdgeInsets.all(_kIndicatorPadding),
                        child: MediaQuery.removePadding(
                          context: context,
                          removeLeft: true,
                          removeTop: true,
                          removeRight: true,
                          removeBottom: true,
                          child: NavigationBar(
                            animationDuration: _dragIndex == null
                                ? (widget.animationDuration >
                                          _kLiquidSelectionDuration
                                      ? _kLiquidSelectionDuration
                                      : widget.animationDuration)
                                : Duration.zero,
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
      ),
    );
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
