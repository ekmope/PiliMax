import 'package:flutter/widgets.dart';

/// Geometry shared by horizontal video cards and their paint-only placeholders.
abstract final class VideoCardHLayoutMetrics {
  static const double itemHeight = 110;
  static const double mainAxisSpacing = 2;
  static const double horizontalPadding = 12;
  static const double verticalPadding = 5;
  static const double thumbnailWidth = 160;
  static const double thumbnailHeight = 100;
  static const double contentGap = 10;
  static const double thumbnailRadius = 10;

  static const Size thumbnailSize = Size(thumbnailWidth, thumbnailHeight);
  static const EdgeInsets contentPadding = EdgeInsets.symmetric(
    horizontal: horizontalPadding,
    vertical: verticalPadding,
  );
  static const BorderRadius thumbnailBorderRadius = BorderRadius.all(
    Radius.circular(thumbnailRadius),
  );
}
