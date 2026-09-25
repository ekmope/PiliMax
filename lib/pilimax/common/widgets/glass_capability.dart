import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:PiliMax/pilimax/common/widgets/liquid_glass_quality.dart';

enum GlassFallbackMode {
  shader,
  reflective,
  frosted,
  soft,
  solid,
}

/// Runtime capabilities used by the liquid-glass rendering path.
///
/// Shader-backed image filters are allowed on Apple platforms as well as
/// Android. The renderer check below remains authoritative, so a Skia or
/// otherwise unsupported backend immediately uses the normal fallback chain.
abstract final class GlassCapability {
  static bool get supportsShaderFilter {
    final supportedPlatform = switch (defaultTargetPlatform) {
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.macOS => true,
      _ => false,
    };
    if (kIsWeb || !supportedPlatform) {
      return false;
    }
    return ui.ImageFilter.isShaderFilterSupported;
  }

  /// Whether the existing magnifier-based treatment is safe on this backend.
  /// Desktop and web stay on the blur/soft paths instead of constructing a
  /// platform-dependent magnifier.
  static bool get supportsReflective {
    return !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS);
  }

  /// Resolves the first stable visual for a new liquid-glass selection.
  /// The order is centralized here so individual visual layers do not make
  /// their own platform decisions: shader -> reflective -> frosted -> soft.
  static GlassFallbackMode liquidFallbackMode(LiquidGlassQuality quality) {
    return switch (quality) {
      LiquidGlassQuality.soft => GlassFallbackMode.soft,
      // An explicit frosted selection is a performance choice. Do not
      // upgrade it to the magnifier path merely because the platform allows
      // reflective effects.
      LiquidGlassQuality.frosted => GlassFallbackMode.frosted,
      LiquidGlassQuality.reflective when supportsShaderFilter =>
        GlassFallbackMode.shader,
      LiquidGlassQuality.automatic when supportsShaderFilter =>
        GlassFallbackMode.shader,
      LiquidGlassQuality.reflective when supportsReflective =>
        GlassFallbackMode.reflective,
      LiquidGlassQuality.reflective || LiquidGlassQuality.automatic =>
        supportsReflective
            ? GlassFallbackMode.reflective
            : GlassFallbackMode.frosted,
    };
  }

  /// Resolves the first mode for an explicitly selected new liquid style.
  ///
  /// The explicit style is intentionally treated as the shader-backed choice;
  /// the legacy automatic quality resolver remains separate so old installs do
  /// not change their visual treatment during upgrade.
  static GlassFallbackMode preferredLiquidMode() {
    return liquidFallbackMode(LiquidGlassQuality.reflective);
  }

  /// Returns the next safe mode after a runtime visual failure.
  static GlassFallbackMode nextFallback(GlassFallbackMode mode) {
    return switch (mode) {
      GlassFallbackMode.shader =>
        supportsReflective
            ? GlassFallbackMode.reflective
            : GlassFallbackMode.frosted,
      GlassFallbackMode.reflective => GlassFallbackMode.frosted,
      GlassFallbackMode.frosted => GlassFallbackMode.soft,
      GlassFallbackMode.soft => GlassFallbackMode.solid,
      GlassFallbackMode.solid => GlassFallbackMode.solid,
    };
  }
}
