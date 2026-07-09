import 'package:PiliMax/common/widgets/glass_container.dart';
import 'package:flutter/material.dart';

class MainPageSwitchDestination {
  const MainPageSwitchDestination({
    required this.index,
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final int index;
  final String label;
  final Widget icon;
  final Widget selectedIcon;
}

class MainPageSwitchOverlay extends StatelessWidget {
  const MainPageSwitchOverlay({
    super.key,
    required this.destinations,
    required this.currentIndex,
    required this.hoverIndex,
  });

  final List<MainPageSwitchDestination> destinations;
  final int currentIndex;
  final int hoverIndex;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final width = (MediaQuery.widthOf(context) - 32)
        .clamp(260.0, 360.0)
        .toDouble();
    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 92),
        child: SizedBox(
          width: width,
          child: GlassContainer(
            borderRadius: const BorderRadius.all(Radius.circular(28)),
            blurSigma: 22,
            opacity: 0.5,
            borderOpacity: 0.28,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: destinations
                  .map(
                    (destination) => Expanded(
                      child: _SwitchItem(
                        destination: destination,
                        selected: destination.index == hoverIndex,
                        current: destination.index == currentIndex,
                        colorScheme: colorScheme,
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ),
    );
  }
}

class _SwitchItem extends StatelessWidget {
  const _SwitchItem({
    required this.destination,
    required this.selected,
    required this.current,
    required this.colorScheme,
  });

  final MainPageSwitchDestination destination;
  final bool selected;
  final bool current;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    final foreground = selected
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurfaceVariant;
    return AnimatedScale(
      scale: selected ? 1.08 : 0.96,
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        height: 68,
        margin: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.all(Radius.circular(22)),
          color: selected
              ? colorScheme.primaryContainer.withValues(alpha: 0.58)
              : Colors.transparent,
          border: Border.all(
            color: selected
                ? colorScheme.primary.withValues(alpha: 0.44)
                : current
                ? colorScheme.outline.withValues(alpha: 0.28)
                : Colors.transparent,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconTheme(
              data: IconThemeData(color: foreground, size: 24),
              child: selected ? destination.selectedIcon : destination.icon,
            ),
            const SizedBox(height: 5),
            Text(
              destination.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foreground,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
