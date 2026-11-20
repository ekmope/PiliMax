import 'dart:ui' as ui;

import 'package:PiliMax/pilimax/common/widgets/glass/liquid_glass.dart';
import 'package:PiliMax/pilimax/common/widgets/glass_style.dart';
import 'package:PiliMax/pilimax/forks/common/widgets/floating_navigation_bar.dart';
import 'package:material_ui/material_ui.dart';

/// Live preview of the strength of [GlassStyle.liquid].
///
/// The preview is a real [FloatingNavigationBar] over sample content, hosted by its
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
  late int _strength = widget.initialValue.clamp(0, 100);

  void _update(int strength) {
    if (strength == _strength) return;
    setState(() => _strength = strength);
    widget.onChanged?.call(strength);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hintStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final supportsRefraction = ui.ImageFilter.isShaderFilterSupported;
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
              child: _Preview(strength: _strength),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Semantics(
                  header: true,
                  child: Text('强度', style: theme.textTheme.labelLarge),
                ),
                ExcludeSemantics(
                  child: Text(
                    '$_strength%',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.primary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
            Semantics(
              label: '强度',
              child: Slider(
                value: _strength.toDouble(),
                min: 0,
                max: 100,
                divisions: 100,
                label: '$_strength%',
                semanticFormatterCallback: (value) => '${value.round()}%',
                onChanged: (value) => _update(value.round()),
              ),
            ),
            Text(
              supportsRefraction ? '强度越高，背景越通透，折射越明显。' : '强度越高，背景磨砂越轻。',
              style: hintStyle,
            ),
            const SizedBox(height: 4),
            Text(
              supportsRefraction
                  ? '按住或拖动预览底栏可观察透镜折射。'
                  : '当前设备使用磨砂。按住或拖动预览底栏可查看透镜变化。',
              style: hintStyle,
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
          onPressed: () => Navigator.of(context).pop(_strength),
          child: const Text('确定'),
        ),
      ],
    );
  }
}

class _Preview extends StatefulWidget {
  const _Preview({required this.strength});

  final int strength;

  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> {
  int _selectedIndex = 1;

  @override
  Widget build(BuildContext context) {
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
      height: 144,
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(
          padding: EdgeInsets.zero,
          viewPadding: EdgeInsets.zero,
        ),
        child: LiquidGlassHost(
          enabled: true,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const ExcludeSemantics(child: _PreviewFeed()),
              Positioned(
                left: 0,
                right: 0,
                bottom: 10,
                child: FloatingNavigationBar(
                  glassStyle: GlassStyle.liquid,
                  liquidGlassStrength: widget.strength / 100,
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: (index) {
                    if (_selectedIndex == index) return;
                    setState(() => _selectedIndex = index);
                  },
                  bottomPadding: 0,
                  destinations: destinations,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Provides distinct thumbnail and text edges behind the preview dock.
class _PreviewFeed extends StatelessWidget {
  const _PreviewFeed();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ColoredBox(
      color: scheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          spacing: 10,
          children: [
            for (final (icon, title, detail, thumbnail, accent, foreground) in [
              (
                Icons.terrain,
                '沿海公路的黄昏',
                '旅行 · 8:24',
                scheme.tertiaryContainer,
                scheme.tertiary,
                scheme.onTertiaryContainer,
              ),
              (
                Icons.local_cafe_outlined,
                '周末手冲咖啡',
                '生活 · 6:18',
                scheme.primaryContainer,
                scheme.primary,
                scheme.onPrimaryContainer,
              ),
            ])
              Expanded(
                child: Row(
                  children: [
                    AspectRatio(
                      aspectRatio: 16 / 10,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          gradient: LinearGradient(
                            begin: Alignment.topRight,
                            end: Alignment.bottomLeft,
                            colors: [
                              thumbnail,
                              Color.lerp(thumbnail, accent, 0.5)!,
                            ],
                          ),
                        ),
                        child: Icon(icon, size: 24, color: foreground),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelLarge,
                            ),
                          ),
                          Flexible(
                            child: Text(
                              detail,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
