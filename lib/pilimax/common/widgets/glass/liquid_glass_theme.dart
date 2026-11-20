import 'package:PiliMax/pilimax/common/widgets/glass/liquid_glass.dart';
import 'package:material_ui/material_ui.dart';

/// The shell mixes unblurred detail with a separate haze layer. [strength]
/// varies their balance and the refraction while keeping the dock legible.
LiquidGlassStyle liquidNavigationBarStyle(
  ColorScheme colorScheme,
  double strength,
) => LiquidGlassStyle.pill(colorScheme).atStrength(strength);

/// Builds the glass lens drawn over the selected destination.
LiquidGlassStyle liquidNavigationLensStyle(
  ColorScheme colorScheme,
  double strength,
) => LiquidGlassStyle.lens(colorScheme).atStrength(strength);

LiquidGlassStyle liquidNavigationLensContentStyle(
  ColorScheme colorScheme,
  double strength,
) => LiquidGlassStyle.lensContent(colorScheme).scale(_lensIntensity(strength));

double _lensIntensity(double strength) => 0.5 + 0.5 * strength.clamp(0.0, 1.0);

/// The restrained drop shadow iOS gives a glass bar. Material elevations are
/// deliberately not used here: a wide, faint shadow keeps the pane floating
/// without drawing a dark band under the blur.
List<BoxShadow> liquidDockShadows(ColorScheme colorScheme) {
  return [
    BoxShadow(
      color: colorScheme.shadow.withValues(alpha: 0.013),
      blurRadius: 3.8,
      offset: const Offset(0, 6.5),
    ),
  ];
}
