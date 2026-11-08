import 'package:material_ui/material_ui.dart'
    show Alignment, Brightness, Color, ColorScheme, LinearGradient;

LinearGradient mainBackgroundGradient(
  ColorScheme colorScheme, {
  bool opaque = false,
}) {
  final isDark = colorScheme.brightness == Brightness.dark;
  final colors = [
    colorScheme.primary.withValues(alpha: isDark ? .30 : .36),
    colorScheme.primaryContainer.withValues(alpha: isDark ? .40 : .36),
    colorScheme.surface.withValues(alpha: .60),
  ];
  return LinearGradient(
    colors: opaque
        ? colors
              .map((color) => Color.alphaBlend(color, colorScheme.surface))
              .toList()
        : colors,
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    stops: const [.1, .4, .7],
  );
}
