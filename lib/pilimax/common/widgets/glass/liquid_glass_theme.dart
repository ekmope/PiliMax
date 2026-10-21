import 'package:PiliMax/pilimax/common/widgets/glass/liquid_glass.dart';
import 'package:material_ui/material_ui.dart';

/// Builds the glass used by the floating navigation bar's shell.
///
/// [strength] is 0..1. At 0 the pane stays readable: the tint, haze and rim
/// keep a floor while refraction, dispersion and end shading fade out.
LiquidGlassStyle liquidNavigationBarStyle(
  ColorScheme colorScheme,
  double strength,
) {
  return LiquidGlassStyle.pill(colorScheme).atStrength(strength);
}

/// Builds the raised glass lens drawn over the selected destination.
LiquidGlassStyle liquidNavigationLensStyle(
  ColorScheme colorScheme,
  double strength,
) {
  return LiquidGlassStyle.lens(colorScheme).atStrength(strength);
}

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
