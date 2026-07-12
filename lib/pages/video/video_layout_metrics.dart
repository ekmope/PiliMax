import 'dart:math' as math;

import 'package:PiliMax/common/style.dart';

import 'package:flutter/widgets.dart';

double videoDetailPlayerHeight(Size viewport, {required bool isVertical}) {
  if (isVertical) {
    return math.max(viewport.longestSide * 0.65, viewport.shortestSide);
  }
  return viewport.shortestSide / Style.aspectRatio16x9;
}
