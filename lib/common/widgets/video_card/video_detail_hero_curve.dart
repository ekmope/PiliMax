import 'package:flutter/animation.dart';

const Curve videoDetailHeroForwardCurve = _VideoDetailCubic(
  0.215,
  0.61,
  0.355,
  1,
);
const Curve _videoDetailHeroInverseCurve = _VideoDetailCubic(
  0.61,
  0.215,
  1,
  0.355,
);

double videoDetailRawProgressForEasedFlight(
  double easedProgress, {
  required bool isPop,
}) {
  final progress = easedProgress.clamp(0.0, 1.0).toDouble();
  if (isPop) {
    return 1 - _videoDetailHeroInverseCurve.transform(1 - progress);
  }
  return _videoDetailHeroInverseCurve.transform(progress);
}

/// Uses a tighter solve tolerance than [Cubic] so the inverse stays accurate
/// near the flat end of easeOutCubic.
final class _VideoDetailCubic extends Curve {
  const _VideoDetailCubic(this.a, this.b, this.c, this.d);

  final double a;
  final double b;
  final double c;
  final double d;

  static double _evaluate(double first, double second, double t) {
    final inverse = 1 - t;
    return 3 * first * inverse * inverse * t +
        3 * second * inverse * t * t +
        t * t * t;
  }

  @override
  double transformInternal(double t) {
    var start = 0.0;
    var end = 1.0;
    for (var iteration = 0; iteration < 18; iteration++) {
      final midpoint = (start + end) / 2;
      if (_evaluate(a, c, midpoint) < t) {
        start = midpoint;
      } else {
        end = midpoint;
      }
    }
    return _evaluate(b, d, (start + end) / 2);
  }
}
