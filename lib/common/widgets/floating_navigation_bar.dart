import 'dart:math' as math;

import 'package:flutter/material.dart';

const double _kNavigationHeight = 64.0;
const double _kIndicatorWidth = 86.0;
const double _kIndicatorPadding = 4.0;
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

  @override
  Widget build(BuildContext context) {
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
