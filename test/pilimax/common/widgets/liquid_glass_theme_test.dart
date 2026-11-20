import 'package:PiliMax/pilimax/common/widgets/glass/liquid_glass_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  test('strength raises optics while keeping a readable tint', () {
    const scheme = ColorScheme.light();
    final low = liquidNavigationBarStyle(scheme, 0);
    final high = liquidNavigationBarStyle(scheme, 1);

    expect(low.tint.a, greaterThan(0));
    expect(high.tint.a, greaterThanOrEqualTo(low.tint.a));
    expect(high.refraction, greaterThan(low.refraction));
    expect(high.rim, greaterThan(low.rim));

    final lensLow = liquidNavigationLensStyle(scheme, 0);
    final lensHigh = liquidNavigationLensStyle(scheme, 1);
    expect(lensHigh.refraction.abs(), greaterThan(lensLow.refraction.abs()));
  });

  test('dark shell tint keeps the same opacity and follows the theme', () {
    const first = ColorScheme.dark(surfaceContainer: Color(0xFF202536));
    const second = ColorScheme.dark(surfaceContainer: Color(0xFF364021));
    final firstTint = liquidNavigationBarStyle(first, 1).tint;
    final secondTint = liquidNavigationBarStyle(second, 1).tint;

    expect(firstTint.a, closeTo(0.48, 0.001));
    expect(secondTint.a, firstTint.a);
    expect(secondTint, isNot(firstTint));
    expect(
      firstTint.computeLuminance(),
      greaterThan(
        first.surfaceContainer.computeLuminance(),
      ),
    );
  });
}
