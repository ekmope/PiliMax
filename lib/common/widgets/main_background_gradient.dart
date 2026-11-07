import 'package:material_ui/material_ui.dart'
    show Alignment, Brightness, ColorScheme, LinearGradient;

LinearGradient mainBackgroundGradient(ColorScheme colorScheme) {
  final isDark = colorScheme.brightness == Brightness.dark;
  return LinearGradient(
    colors: [
      colorScheme.primary.withValues(alpha: isDark ? .30 : .36),
      colorScheme.primaryContainer.withValues(alpha: isDark ? .40 : .36),
      colorScheme.surface.withValues(alpha: .60),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    stops: const [.1, .4, .7],
  );
}
