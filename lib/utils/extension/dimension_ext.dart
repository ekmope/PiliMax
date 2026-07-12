import 'package:PiliMax/grpc/bilibili/app/archive/v1.pb.dart' show Dimension;

extension DimensionExt on Dimension {
  bool get isVertical => rotate == .ONE ? width > height : height > width;
}

extension StringExt on String {
  bool? get verticalFromUri {
    try {
      final params = Uri.parse(this).queryParameters;
      final width = int.parse(params['player_width']!);
      final height = int.parse(params['player_height']!);
      if (width <= 0 || height <= 0) {
        return null;
      }
      return params['player_rotate'] == '1' ? width > height : height > width;
    } catch (_) {
      return null;
    }
  }

  bool get isVerticalFromUri => verticalFromUri ?? false;
}
