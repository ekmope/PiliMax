import 'package:PiliMax/models/common/enum_with_label.dart';
import 'package:PiliMax/pilimax/common/widgets/liquid_glass_quality.dart';

/// User-facing visual styles for the floating navigation bar.
enum GlassStyle implements EnumWithLabel {
  none('普通悬浮底栏'),
  soft('柔光玻璃'),
  liquid('液态玻璃');

  const GlassStyle(this.label);

  @override
  final String label;

  static GlassStyle? tryFromIndex(Object? value) {
    final index = switch (value) {
      final int index => index,
      final double index
          when index.isFinite && index == index.truncateToDouble() =>
        index.toInt(),
      _ => -1,
    };
    return index >= 0 && index < values.length ? values[index] : null;
  }

  static GlassStyle fromIndex(Object? value) {
    return tryFromIndex(value) ?? none;
  }

  /// Maps the old two-key configuration without writing a new preference.
  ///
  /// Keeping this conversion pure makes the upgrade rule explicit: an old
  /// liquid setting remains a legacy liquid path until the user selects one
  /// of the new styles in settings.
  static GlassStyle fromLegacy({
    required bool floatingNavBar,
    required bool liquidGlassNavBar,
    required LiquidGlassQuality quality,
  }) {
    if (!floatingNavBar || !liquidGlassNavBar) return none;
    return quality == LiquidGlassQuality.soft ? soft : liquid;
  }
}
