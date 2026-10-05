import 'package:PiliMax/models/common/enum_with_label.dart';

/// User-facing visual styles for the floating navigation bar.
enum GlassStyle implements EnumWithLabel {
  none('普通悬浮底栏'),
  soft('柔光玻璃');

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
}
