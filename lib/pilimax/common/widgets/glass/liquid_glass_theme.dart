import 'package:PiliMax/pilimax/common/widgets/glass/liquid_glass.dart';
import 'package:material_color_utilities/hct/hct.dart';
import 'package:material_ui/material_ui.dart';

/// Builds the glass used by the floating navigation bar's shell.
///
/// [strength] is 0..1. At 0 the pane stays readable: the tint, haze and rim
/// keep a floor while refraction, dispersion and end shading fade out.
LiquidGlassStyle liquidNavigationBarStyle(
  ColorScheme colorScheme,
  double strength,
) {
  final pill = LiquidGlassStyle.pill(colorScheme);
  if (colorScheme.brightness == Brightness.light) {
    return pill.atStrength(strength);
  }
  final surface = Hct.fromInt(colorScheme.surfaceContainer.toARGB32());
  final tint = _withTone(surface, surface.tone + 7);
  return pill
      .copyWith(tint: tint.withValues(alpha: pill.tint.a))
      .atStrength(strength);
}

/// Builds the raised glass lens drawn over the selected destination.
LiquidGlassStyle liquidNavigationLensStyle(
  ColorScheme colorScheme,
  double strength,
) {
  return LiquidGlassStyle.lens(colorScheme).atStrength(strength);
}

LiquidGlassStyle liquidNavigationLensContentStyle(
  ColorScheme colorScheme,
  double strength,
) => LiquidGlassStyle.lensContent(colorScheme).atStrength(strength);

Color liquidNavigationSelectionColor(ColorScheme colorScheme) {
  final secondary = Hct.fromInt(colorScheme.secondary.toARGB32());
  final tone = colorScheme.brightness == Brightness.dark ? 4.0 : 90.0;
  return _withTone(secondary, tone).withValues(alpha: 0.85);
}

Color _withTone(Hct color, double tone) =>
    Color(Hct.from(color.hue, color.chroma, tone.clamp(0.0, 100.0)).toInt());

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
