import 'package:PiliMax/pilimax/common/widgets/glass/liquid_glass_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  for (final scheme in [const ColorScheme.light(), const ColorScheme.dark()]) {
    test(
      '${scheme.brightness.name} strength varies clarity and refraction',
      () {
        final styles = [0.0, 0.68, 0.69, 0.70, 1.0]
            .map((strength) => liquidNavigationBarStyle(scheme, strength))
            .toList();
        for (var index = 1; index < styles.length; index++) {
          final previous = styles[index - 1];
          final current = styles[index];
          expect(current.tint.a, lessThan(previous.tint.a));
          expect(current.blur, lessThan(previous.blur));
          expect(current.hazeBlur, lessThan(previous.hazeBlur));
          expect(current.refraction, greaterThan(previous.refraction));
        }
        // The 64 dp shell caps sampled refraction depth at half its height.
        expect(styles.last.refraction, lessThan(32));

        final low = liquidNavigationLensStyle(scheme, 0);
        final high = liquidNavigationLensStyle(scheme, 1);
        expect(high.refraction.abs(), greaterThan(low.refraction.abs()));
      },
    );
  }

  test('dark shell tint keeps the same opacity and follows the theme', () {
    const first = ColorScheme.dark(surfaceContainer: Color(0xFF202536));
    const second = ColorScheme.dark(surfaceContainer: Color(0xFF364021));
    final firstTint = liquidNavigationBarStyle(first, 0.7).tint;
    final secondTint = liquidNavigationBarStyle(second, 0.7).tint;

    expect(firstTint.a, greaterThan(0));
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
