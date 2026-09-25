import 'package:device_info_plus/device_info_plus.dart';
import 'package:PiliMax/models/common/enum_with_label.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb, visibleForTesting;

/// Chooses the visual/performance trade-off of the liquid-glass treatment.
/// Frosted mode keeps the interaction while skipping the magnifier and moving
/// reflection layers.
enum LiquidGlassQuality implements EnumWithLabel {
  automatic('自动（推荐）'),
  reflective('液态玻璃'),
  // Keep frosted at index 2 for compatibility with the original reader.
  frosted('磨砂玻璃（性能优先）'),
  soft('柔光玻璃（半透明）');

  const LiquidGlassQuality(this.label);

  @override
  final String label;

  /// Reads the persisted index without allowing a damaged or newer value to
  /// crash startup. Missing and invalid values preserve the old automatic
  /// behavior.
  static LiquidGlassQuality fromIndex(Object? value) {
    final index = switch (value) {
      final int index => index,
      final double index
          when index.isFinite && index == index.truncateToDouble() =>
        index.toInt(),
      _ => -1,
    };
    return index >= 0 && index < values.length ? values[index] : automatic;
  }
}

abstract final class LiquidGlassQualityResolver {
  static LiquidGlassQuality get immediateDefault =>
      _isAndroid ? LiquidGlassQuality.frosted : LiquidGlassQuality.reflective;

  static Future<LiquidGlassQuality> resolve() async {
    if (!_isAndroid) {
      return immediateDefault;
    }

    try {
      final device = await DeviceInfoPlugin().androidInfo;
      return fromAndroidCapabilities(
        sdkInt: device.version.sdkInt,
        isLowRamDevice: device.isLowRamDevice,
        physicalRamSize: device.physicalRamSize,
      );
    } catch (_) {
      // A missing platform response should not make the first interaction
      // expensive on an unknown Android device.
      return LiquidGlassQuality.frosted;
    }
  }

  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @visibleForTesting
  static LiquidGlassQuality fromAndroidCapabilities({
    required int sdkInt,
    required bool isLowRamDevice,
    required int physicalRamSize,
  }) {
    final hasLimitedMemory =
        isLowRamDevice || (physicalRamSize > 0 && physicalRamSize <= 4096);
    return sdkInt < 29 || hasLimitedMemory
        ? LiquidGlassQuality.frosted
        : LiquidGlassQuality.reflective;
  }
}
