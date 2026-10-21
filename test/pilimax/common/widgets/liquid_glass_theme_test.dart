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
}
