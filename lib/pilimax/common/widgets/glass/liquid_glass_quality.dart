import 'package:PiliMax/models/common/enum_with_label.dart';

/// The rendering quality of an enabled liquid glass surface.
enum LiquidGlassQuality with EnumWithLabel {
  standard('标准'),
  ultra('超清');

  const LiquidGlassQuality(this.label);

  @override
  final String label;

  static LiquidGlassQuality? tryFromName(Object? value) => switch (value) {
    'standard' => standard,
    'ultra' => ultra,
    _ => null,
  };
}
