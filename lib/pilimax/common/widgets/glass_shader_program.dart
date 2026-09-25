import 'dart:ui' as ui;

import 'package:PiliMax/pilimax/common/widgets/glass_capability.dart';

const String liquidGlassShaderAsset = 'shaders/liquid_glass.frag';

enum GlassShaderFailure {
  unsupportedBackend,
  assetLoadFailed,
}

/// Outcome of loading the precompiled liquid-glass shader.
///
/// Loading is intentionally represented as data so a caller can retain the
/// current blur/soft-glass path when a platform or asset cannot use shaders.
final class GlassShaderProgramResult {
  const GlassShaderProgramResult.success(this.program)
    : failure = null,
      error = null,
      stackTrace = null;

  const GlassShaderProgramResult.failure({
    required this.failure,
    this.error,
    this.stackTrace,
  }) : program = null;

  final ui.FragmentProgram? program;
  final GlassShaderFailure? failure;
  final Object? error;
  final StackTrace? stackTrace;

  bool get isAvailable => program != null;
}

/// Loads the runtime-effect program and creates configured shader instances.
///
/// [ui.FragmentProgram.fromAsset] already caches programs in Flutter's engine,
/// but this layer also caches the Future so concurrent callers do not enqueue
/// duplicate loads. A new FragmentShader is created for each filter instance;
/// its mutable uniforms must not be shared by different widgets.
abstract final class GlassShaderProgram {
  static Future<GlassShaderProgramResult>? _loadFuture;

  static Future<GlassShaderProgramResult> load() {
    return _loadFuture ??= _load();
  }

  static Future<GlassShaderProgramResult> _load() async {
    if (!GlassCapability.supportsShaderFilter) {
      return const GlassShaderProgramResult.failure(
        failure: GlassShaderFailure.unsupportedBackend,
      );
    }

    try {
      final program = await ui.FragmentProgram.fromAsset(
        liquidGlassShaderAsset,
      );
      return GlassShaderProgramResult.success(program);
    } catch (error, stackTrace) {
      return GlassShaderProgramResult.failure(
        failure: GlassShaderFailure.assetLoadFailed,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Creates one mutable shader instance and initializes its non-size uniforms.
  ///
  /// The first `vec2` uniform (`u_size`) is reserved by
  /// [ui.ImageFilter.shader] and is populated by the engine. The shader
  /// returns null when its program cannot create or accept an instance, so the
  /// caller can keep the existing visual fallback. Refraction amount, edge
  /// height, chromatic aberration, and lens radius are normalized to the
  /// shorter filter dimension; this keeps them independent of device pixel
  /// ratio.
  static ui.FragmentShader? createShader(
    ui.FragmentProgram program, {
    required double refractionAmount,
    required double refractionHeight,
    required double chromaticAberration,
    required double lensRadius,
    ui.Offset center = const ui.Offset(0.5, 0.5),
  }) {
    ui.FragmentShader? shader;
    try {
      // u_size occupies float slots 0 and 1 and is set by the engine.
      final created = program.fragmentShader();
      shader = created;
      configureShader(
        created,
        refractionAmount: refractionAmount,
        refractionHeight: refractionHeight,
        chromaticAberration: chromaticAberration,
        lensRadius: lensRadius,
        center: center,
      );
      return created;
    } catch (_) {
      shader?.dispose();
      return null;
    }
  }

  /// Updates a reusable shader instance without recompiling its program.
  static void configureShader(
    ui.FragmentShader shader, {
    required double refractionAmount,
    required double refractionHeight,
    required double chromaticAberration,
    required double lensRadius,
    ui.Offset center = const ui.Offset(0.5, 0.5),
  }) {
    shader
      ..setFloat(2, _nonNegative(refractionAmount))
      ..setFloat(3, _nonNegative(refractionHeight))
      ..setFloat(4, _nonNegative(chromaticAberration))
      ..setFloat(5, _nonNegative(lensRadius))
      ..setFloat(6, _unit(center.dx, 0.5))
      ..setFloat(7, _unit(center.dy, 0.5));
  }

  static double _nonNegative(double value) {
    return value.isFinite && value >= 0.0 ? value : 0.0;
  }

  static double _unit(double value, double fallback) {
    if (!value.isFinite) return fallback;
    return value.clamp(0.0, 1.0).toDouble();
  }
}
