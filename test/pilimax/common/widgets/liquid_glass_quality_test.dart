import 'package:PiliMax/pilimax/common/widgets/glass_capability.dart';
import 'package:PiliMax/pilimax/common/widgets/glass_style.dart';
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
    expect(LiquidGlassQuality.fromIndex(1.5), LiquidGlassQuality.automatic);
    expect(GlassStyle.fromIndex(1.5), GlassStyle.none);
    expect(GlassStyle.tryFromIndex(2), GlassStyle.liquid);
    expect(GlassStyle.tryFromIndex(3), isNull);
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

  test('keeps the runtime fallback order explicit', () {
    expect(
      GlassCapability.liquidFallbackMode(LiquidGlassQuality.frosted),
      GlassFallbackMode.frosted,
    );
    expect(
      GlassCapability.nextFallback(GlassFallbackMode.shader),
      anyOf(GlassFallbackMode.reflective, GlassFallbackMode.frosted),
    );
    expect(
      GlassCapability.nextFallback(GlassFallbackMode.reflective),
      GlassFallbackMode.frosted,
    );
    expect(
      GlassCapability.nextFallback(GlassFallbackMode.frosted),
      GlassFallbackMode.soft,
    );
    expect(
      GlassCapability.nextFallback(GlassFallbackMode.soft),
      GlassFallbackMode.solid,
    );
  });

  test('new liquid style prefers the shader capability path', () {
    final expected = GlassCapability.supportsShaderFilter
        ? GlassFallbackMode.shader
        : GlassCapability.supportsReflective
        ? GlassFallbackMode.reflective
        : GlassFallbackMode.frosted;
    expect(GlassCapability.preferredLiquidMode(), expected);
  });

  test(
    'maps legacy glass settings without changing the selected appearance',
    () {
      expect(
        GlassStyle.fromLegacy(
          floatingNavBar: false,
          liquidGlassNavBar: true,
          quality: LiquidGlassQuality.reflective,
        ),
        GlassStyle.none,
      );
      expect(
        GlassStyle.fromLegacy(
          floatingNavBar: true,
          liquidGlassNavBar: false,
          quality: LiquidGlassQuality.reflective,
        ),
        GlassStyle.none,
      );
      expect(
        GlassStyle.fromLegacy(
          floatingNavBar: true,
          liquidGlassNavBar: true,
          quality: LiquidGlassQuality.soft,
        ),
        GlassStyle.soft,
      );
      expect(
        GlassStyle.fromLegacy(
          floatingNavBar: true,
          liquidGlassNavBar: true,
          quality: LiquidGlassQuality.reflective,
        ),
        GlassStyle.liquid,
      );
    },
  );
}
