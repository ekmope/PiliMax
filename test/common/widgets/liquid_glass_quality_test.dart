import 'package:PiliMax/common/widgets/liquid_glass_quality.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses frosted glass for constrained Android devices', () {
    expect(
      LiquidGlassQualityResolver.fromAndroidCapabilities(
        sdkInt: 35,
        isLowRamDevice: true,
        physicalRamSize: 8192,
      ),
      LiquidGlassQuality.frosted,
    );
    expect(
      LiquidGlassQualityResolver.fromAndroidCapabilities(
        sdkInt: 35,
        isLowRamDevice: false,
        physicalRamSize: 4096,
      ),
      LiquidGlassQuality.frosted,
    );
    expect(
      LiquidGlassQualityResolver.fromAndroidCapabilities(
        sdkInt: 28,
        isLowRamDevice: false,
        physicalRamSize: 8192,
      ),
      LiquidGlassQuality.frosted,
    );
  });

  test('uses reflective glass for capable Android devices', () {
    expect(
      LiquidGlassQualityResolver.fromAndroidCapabilities(
        sdkInt: 29,
        isLowRamDevice: false,
        physicalRamSize: 8192,
      ),
      LiquidGlassQuality.reflective,
    );
  });
}
