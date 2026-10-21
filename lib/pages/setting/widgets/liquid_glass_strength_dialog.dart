import 'package:PiliMax/pilimax/common/widgets/glass/liquid_glass.dart';
import 'package:PiliMax/pilimax/common/widgets/glass_style.dart';
import 'package:PiliMax/pilimax/forks/common/widgets/floating_navigation_bar.dart';
import 'package:material_ui/material_ui.dart';

/// Live preview and strength slider for [GlassStyle.liquid].
///
/// The preview is a real [FloatingNavigationBar] over a gradient, hosted by its
/// own capture layer because it lives in a dialog route rather than under the
/// main page's host. Values are applied to the caller as they change; the
/// caller persists only after confirmation.
class LiquidGlassStrengthDialog extends StatefulWidget {
  const LiquidGlassStrengthDialog({
    super.key,
    required this.initialValue,
    this.onChanged,
  });

  final int initialValue;
  final ValueChanged<int>? onChanged;

  @override
  State<LiquidGlassStrengthDialog> createState() =>
      _LiquidGlassStrengthDialogState();
}

class _LiquidGlassStrengthDialogState extends State<LiquidGlassStrengthDialog> {
  late int _value = widget.initialValue.clamp(0, 100);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('液态玻璃强度'),
      contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: _Preview(value: _value),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text('强度', style: theme.textTheme.labelLarge),
                const Spacer(),
                Text(
                  '$_value%',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            Slider(
              value: _value.toDouble(),
              min: 0,
              max: 100,
              divisions: 20,
              label: '$_value%',
              onChanged: (value) {
                final next = value.round();
                if (next == _value) return;
                setState(() => _value = next);
                widget.onChanged?.call(next);
              },
            ),
            Text(
              '调节折射、色散、边缘高光与光晕。0% 仍是可读的淡玻璃；'
              '只有“液态玻璃”样式会使用这个值。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_value),
          child: const Text('确定'),
        ),
      ],
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.value});

  final int value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const destinations = [
      FloatingNavigationDestination(
        icon: Icon(Icons.home_outlined),
        selectedIcon: Icon(Icons.home),
        label: '首页',
      ),
      FloatingNavigationDestination(
        icon: Icon(Icons.explore_outlined),
        selectedIcon: Icon(Icons.explore),
        label: '动态',
      ),
      FloatingNavigationDestination(
        icon: Icon(Icons.person_outline),
        selectedIcon: Icon(Icons.person),
        label: '我的',
      ),
    ];
    return SizedBox(
      height: 118,
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(
          padding: EdgeInsets.zero,
          viewPadding: EdgeInsets.zero,
        ),
        child: LiquidGlassScope(
          enabled: true,
          quality: LiquidGlassQuality.ultra,
          child: LiquidGlassHost(
            enabled: true,
            child: Stack(
              fit: StackFit.expand,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        scheme.primaryContainer,
                        scheme.tertiaryContainer,
                        scheme.surfaceContainerHighest,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
                Positioned(
                  left: 18,
                  top: 16,
                  child: Text(
                    '液态玻璃预览',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: scheme.onPrimaryContainer.withValues(alpha: 0.7),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 10,
                  child: ExcludeSemantics(
                    child: IgnorePointer(
                      child: FloatingNavigationBar(
                        glassStyle: GlassStyle.liquid,
                        liquidGlassStrength: value / 100,
                        selectedIndex: 1,
                        bottomPadding: 0,
                        destinations: destinations,
                      ),
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
