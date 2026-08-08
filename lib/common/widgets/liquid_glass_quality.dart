import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb, visibleForTesting;

/// Chooses the cost of the liquid-glass treatment without exposing another
/// user-facing preference. The frosted mode keeps the interaction while
/// skipping the magnifier and moving reflection layers.
enum LiquidGlassQuality { automatic, reflective, frosted }

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
