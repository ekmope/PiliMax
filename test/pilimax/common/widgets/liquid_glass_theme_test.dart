import 'package:PiliMax/pilimax/common/widgets/glass/liquid_glass_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  for (final scheme in [const ColorScheme.light(), const ColorScheme.dark()]) {
    test(
      '${scheme.brightness.name} shell keeps the clear sample from 67a0b1180',
      () {
        final styles = [0.0, 0.68, 0.69, 0.70, 1.0]
            .map((strength) => liquidNavigationBarStyle(scheme, strength))
            .toList();
        for (var index = 1; index < styles.length; index++) {
          final previous = styles[index - 1];
          final current = styles[index];
          expect(current.refraction, greaterThan(previous.refraction));
          expect(current.haze, greaterThan(previous.haze));
        }
        expect(styles.map((style) => style.blur), everyElement(0));
        final defaultShell = styles[3];
        expect(defaultShell.haze, closeTo(0.6228, 0.00001));
        expect(defaultShell.hazeBlur, 15.6);
        expect(defaultShell.refraction, closeTo(48.3, 0.00001));
        expect(defaultShell.bevel, 20);
        expect(defaultShell.brightness, 1);
        final low = liquidNavigationLensStyle(scheme, 0);
        final high = liquidNavigationLensStyle(scheme, 1);
        expect(high.refraction.abs(), greaterThan(low.refraction.abs()));
        final defaultLens = liquidNavigationLensStyle(scheme, 0.7);
        expect(defaultLens.refraction, closeTo(-3.4615, 0.00001));
        expect(defaultLens.bevel, 5.5);
        expect(defaultLens.dispersion, closeTo(4.55, 0.00001));
      },
    );
  }

  test('dark shell tint keeps the same opacity and follows the theme', () {
    const first = ColorScheme.dark(surfaceContainerHighest: Color(0xFF202536));
    const second = ColorScheme.dark(surfaceContainerHighest: Color(0xFF364021));
    final firstTint = liquidNavigationBarStyle(first, 0.7).tint;
    final secondTint = liquidNavigationBarStyle(second, 0.7).tint;

    expect(firstTint.a, closeTo(0.43968, 0.00001));
    expect(secondTint.a, firstTint.a);
    expect(firstTint.withValues(alpha: 1), first.surfaceContainerHighest);
    expect(secondTint.withValues(alpha: 1), second.surfaceContainerHighest);
  });
}
