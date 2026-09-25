import 'dart:ui' as ui;

import 'package:PiliMax/pilimax/common/widgets/glass_capability.dart';
import 'package:PiliMax/pilimax/common/widgets/glass_shader_program.dart';
import 'package:flutter/widgets.dart';

/// Applies the shader-backed backdrop filter when the current renderer can
/// create it, otherwise returns the caller-provided visual fallback.
class LiquidGlassFilter extends StatefulWidget {
  const LiquidGlassFilter({
    super.key,
    required this.child,
    required this.fallback,
    this.onFailure,
    this.refractionAmount = 0.025,
    this.refractionHeight = 0.24,
    this.chromaticAberration = 0.0,
    this.lensRadius = 0.5,
    this.depthEffect = 0.18,
  });

  final Widget child;
  final Widget fallback;
  final VoidCallback? onFailure;
  final double refractionAmount;
  final double refractionHeight;
  final double chromaticAberration;
  final double lensRadius;
  /// Adds the optional radial component to the rounded-box normal.
  ///
  /// The default preserves the original lens appearance.
  final double depthEffect;

  @override
  State<LiquidGlassFilter> createState() => _LiquidGlassFilterState();
}

class _LiquidGlassFilterState extends State<LiquidGlassFilter> {
  late Future<GlassShaderProgramResult> _programFuture;
  ui.FragmentProgram? _program;
  ui.FragmentShader? _shader;
  _ShaderParameters? _lastParameters;
  ui.ImageFilter? _filter;
  bool _shaderFailed = false;
  bool _failureReported = false;

  @override
  void initState() {
    super.initState();
    _programFuture = GlassShaderProgram.load();
  }

  ui.ImageFilter? _filterFor(ui.FragmentProgram program) {
    final parameters = _ShaderParameters(
      refractionAmount: widget.refractionAmount,
      refractionHeight: widget.refractionHeight,
      chromaticAberration: widget.chromaticAberration,
      lensRadius: widget.lensRadius,
      depthEffect: widget.depthEffect,
    );
    try {
      if (_program != program) {
        _shaderFailed = false;
        _filter = null;
        _shader?.dispose();
        _program = program;
        _shader = program.fragmentShader();
        _lastParameters = null;
      }
      if (_shaderFailed) return null;
      if (_shader == null) {
        _shader = program.fragmentShader();
        _lastParameters = null;
      }
      if (_lastParameters != parameters) {
        GlassShaderProgram.configureShader(
          _shader!,
          refractionAmount: parameters.refractionAmount,
          refractionHeight: parameters.refractionHeight,
          chromaticAberration: parameters.chromaticAberration,
          lensRadius: parameters.lensRadius,
          depthEffect: parameters.depthEffect,
        );
        _lastParameters = parameters;
        // The shader instance is reused; rebuilding the filter only changes
        // the native filter wrapper and avoids recompiling the program.
        _filter = ui.ImageFilter.shader(_shader!);
      }
      return _filter;
    } on Object {
      _filter = null;
      _lastParameters = null;
      _shader?.dispose();
      _shader = null;
      _program = program;
      _shaderFailed = true;
      _reportFailure();
      return null;
    }
  }

  void _reportFailure() {
    if (_failureReported || widget.onFailure == null) return;
    _failureReported = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onFailure!.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!GlassCapability.supportsShaderFilter) {
      _reportFailure();
      return widget.fallback;
    }

    return FutureBuilder<GlassShaderProgramResult>(
      future: _programFuture,
      builder: (context, snapshot) {
        final program = snapshot.data?.program;
        if (snapshot.hasError ||
            (snapshot.connectionState == ConnectionState.done &&
                program == null)) {
          _reportFailure();
          return widget.fallback;
        }
        if (program == null) return widget.fallback;

        final filter = _filterFor(program);
        if (filter == null) return widget.fallback;
        // A transparent coverage paint keeps the filter alive even when the
        // child is an otherwise empty SizedBox (the indicator lens uses this
        // form). This mirrors Flutter's own shader-backed stretch effect.
        return BackdropFilter(
          filter: filter,
          child: CustomPaint(
            painter: const _ShaderCoveragePainter(),
            child: widget.child,
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }
}

class _ShaderCoveragePainter extends CustomPainter {
  const _ShaderCoveragePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color.fromARGB(1, 0, 0, 0)
      ..style = PaintingStyle.fill;
    canvas.drawPoints(ui.PointMode.points, <ui.Offset>[
      ui.Offset.zero,
      ui.Offset(size.width - 1, 0),
      ui.Offset(0, size.height - 1),
      ui.Offset(size.width - 1, size.height - 1),
    ], paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

final class _ShaderParameters {
  const _ShaderParameters({
    required this.refractionAmount,
    required this.refractionHeight,
    required this.chromaticAberration,
    required this.lensRadius,
    required this.depthEffect,
  });

  final double refractionAmount;
  final double refractionHeight;
  final double chromaticAberration;
  final double lensRadius;
  final double depthEffect;

  @override
  bool operator ==(Object other) {
    return other is _ShaderParameters &&
        other.refractionAmount == refractionAmount &&
        other.refractionHeight == refractionHeight &&
        other.chromaticAberration == chromaticAberration &&
        other.lensRadius == lensRadius &&
        other.depthEffect == depthEffect;
  }

  @override
  int get hashCode => Object.hash(
    refractionAmount,
    refractionHeight,
    chromaticAberration,
    lensRadius,
    depthEffect,
  );
}
