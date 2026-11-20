import 'dart:ui' as ui;

import 'package:PiliMax/pilimax/common/widgets/glass/liquid_glass.dart';
import 'package:PiliMax/pilimax/common/widgets/glass_style.dart';
import 'package:PiliMax/pilimax/forks/common/widgets/floating_navigation_bar.dart';
import 'package:material_ui/material_ui.dart';

/// Live preview of the strength and quality of [GlassStyle.liquid].
///
/// The preview is a real [FloatingNavigationBar] over a gradient, hosted by its
/// own capture layer because it lives in a dialog route rather than under the
/// main page's host. Values are applied to the caller as they change; the
/// caller persists only after confirmation.
class LiquidGlassStrengthDialog extends StatefulWidget {
  const LiquidGlassStrengthDialog({
    super.key,
    required this.initialValue,
    required this.initialQuality,
    this.onChanged,
  });

  final int initialValue;
  final LiquidGlassQuality initialQuality;
  final void Function(int strength, LiquidGlassQuality quality)? onChanged;

  @override
  State<LiquidGlassStrengthDialog> createState() =>
      _LiquidGlassStrengthDialogState();
}

class _LiquidGlassStrengthDialogState extends State<LiquidGlassStrengthDialog> {
  late int _value = widget.initialValue.clamp(0, 100);
  late LiquidGlassQuality _quality = widget.initialQuality;

  void _update(int strength, LiquidGlassQuality quality) {
    if (strength == _value && quality == _quality) return;
    setState(() {
      _value = strength;
      _quality = quality;
    });
    widget.onChanged?.call(strength, quality);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('液态玻璃'),
      scrollable: true,
      contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: _Preview(value: _value, quality: _quality),
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
              onChanged: (value) => _update(value.round(), _quality),
            ),
            Text('画质', style: theme.textTheme.labelLarge),
            Wrap(
              spacing: 8,
              children: [
                for (final quality in LiquidGlassQuality.values)
                  ChoiceChip(
                    label: Text(quality.label),
                    selected: _quality == quality,
                    onSelected: (_) => _update(_value, quality),
                  ),
              ],
            ),
            Text(
              ui.ImageFilter.isShaderFilterSupported
                  ? '按住或拖动预览底栏，查看透镜效果。超清会折射透镜内的图标和文字。'
                  : '当前设备使用磨砂效果。按住或拖动预览底栏可查看透镜反馈。',
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
          onPressed: () => Navigator.of(context).pop(
            (strength: _value, quality: _quality),
          ),
          child: const Text('确定'),
        ),
      ],
    );
  }
}

class _Preview extends StatefulWidget {
  const _Preview({required this.value, required this.quality});

  final int value;
  final LiquidGlassQuality quality;

  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> {
  int _selectedIndex = 1;

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
          quality: widget.quality,
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
                  child: FloatingNavigationBar(
                    glassStyle: GlassStyle.liquid,
                    liquidGlassStrength: widget.value / 100,
                    selectedIndex: _selectedIndex,
                    onDestinationSelected: (index) =>
                        setState(() => _selectedIndex = index),
                    bottomPadding: 0,
                    destinations: destinations,
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
