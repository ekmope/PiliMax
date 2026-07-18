import 'package:flutter/material.dart';

/// A vertical presentation of Flutter's public [Slider].
///
/// Rotating the framework widget keeps its theming, keyboard interaction,
/// semantics and future framework fixes intact. Value indicators are disabled
/// because rotating a horizontal [Slider] would also rotate their text.
class VerticalSlider extends StatelessWidget {
  const VerticalSlider({
    super.key,
    required this.value,
    this.secondaryTrackValue,
    required this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
    this.min = 0,
    this.max = 1,
    this.divisions,
    this.activeColor,
    this.inactiveColor,
    this.secondaryActiveColor,
    this.thumbColor,
    this.overlayColor,
    this.mouseCursor,
    this.semanticFormatterCallback,
    this.focusNode,
    this.autofocus = false,
    this.allowedInteraction,
    this.padding,
    this.year2023,
  });

  final double value;
  final double? secondaryTrackValue;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double>? onChangeEnd;
  final double min;
  final double max;
  final int? divisions;
  final Color? activeColor;
  final Color? inactiveColor;
  final Color? secondaryActiveColor;
  final Color? thumbColor;
  final WidgetStateProperty<Color?>? overlayColor;
  final MouseCursor? mouseCursor;
  final SemanticFormatterCallback? semanticFormatterCallback;
  final FocusNode? focusNode;
  final bool autofocus;
  final SliderInteraction? allowedInteraction;
  final EdgeInsetsGeometry? padding;
  final bool? year2023;

  @override
  Widget build(BuildContext context) => RotatedBox(
    quarterTurns: 3,
    child: Slider(
      value: value,
      secondaryTrackValue: secondaryTrackValue,
      onChanged: onChanged,
      onChangeStart: onChangeStart,
      onChangeEnd: onChangeEnd,
      min: min,
      max: max,
      divisions: divisions,
      activeColor: activeColor,
      inactiveColor: inactiveColor,
      secondaryActiveColor: secondaryActiveColor,
      thumbColor: thumbColor,
      overlayColor: overlayColor,
      mouseCursor: mouseCursor,
      semanticFormatterCallback: semanticFormatterCallback,
      focusNode: focusNode,
      autofocus: autofocus,
      allowedInteraction: allowedInteraction,
      padding: padding,
      showValueIndicator: ShowValueIndicator.never,
      // ignore: deprecated_member_use
      year2023: year2023,
    ),
  );
}
