import 'package:PiliMax/pilimax/common/widgets/liquid_glass_quality.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('persists quality indexes defensively', () {
    expect(
      LiquidGlassQuality.fromIndex(LiquidGlassQuality.reflective.index),
      LiquidGlassQuality.reflective,
    );
    expect(LiquidGlassQuality.fromIndex(null), LiquidGlassQuality.automatic);
    expect(
      LiquidGlassQuality.fromIndex(2),
      LiquidGlassQuality.frosted,
    );
    expect(LiquidGlassQuality.fromIndex(99), LiquidGlassQuality.automatic);
    expect(
      LiquidGlassQuality.fromIndex(double.nan),
      LiquidGlassQuality.automatic,
    );
    expect(LiquidGlassQuality.soft.label, '柔光玻璃（半透明）');
    expect(LiquidGlassQuality.frosted.label, '磨砂玻璃（性能优先）');
  });

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
