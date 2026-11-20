import 'dart:ui' show lerpDouble;

import 'package:PiliMax/pilimax/common/widgets/glass/liquid_glass.dart';
import 'package:material_color_utilities/hct/hct.dart';
import 'package:material_ui/material_ui.dart';

/// Stronger glass exposes more of the backdrop while bending it farther.
/// [strength] is a continuous value from 0 to 1.
LiquidGlassStyle liquidNavigationBarStyle(
  ColorScheme colorScheme,
  double strength,
) {
  final pill = LiquidGlassStyle.pill(colorScheme);
  final dark = colorScheme.brightness == Brightness.dark;
  final surface = dark
      ? Hct.fromInt(colorScheme.surfaceContainer.toARGB32())
      : null;
  final tint = surface == null
      ? pill.tint
      : _withTone(surface, surface.tone + 7);
  final amount = strength.clamp(0.0, 1.0);
  double between(double from, double to) => lerpDouble(from, to, amount)!;

  return pill.copyWith(
    tint: tint.withValues(
      alpha: dark ? between(0.66, 0.50) : between(0.70, 0.55),
    ),
    blur: between(5, 0.8),
    haze: between(0.82, 0.42),
    hazeBlur: between(18, 8),
    refraction: between(8, 27),
    bevel: between(7, 15),
    saturation: between(1.18, 1.85),
    brightness: dark ? between(0.88, 0.76) : pill.brightness,
    rim: pill.rim * between(0.65, 1),
  );
}

/// Builds the raised glass lens drawn over the selected destination.
LiquidGlassStyle liquidNavigationLensStyle(
  ColorScheme colorScheme,
  double strength,
) => LiquidGlassStyle.lens(colorScheme).scale(_lensIntensity(strength));

LiquidGlassStyle liquidNavigationLensContentStyle(
  ColorScheme colorScheme,
  double strength,
) => LiquidGlassStyle.lensContent(colorScheme).scale(_lensIntensity(strength));

double _lensIntensity(double strength) => 0.5 + 0.5 * strength.clamp(0.0, 1.0);

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
