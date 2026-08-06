import 'package:PiliMax/pages/video/video_detail_transition_timing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('return media cover is clamped to the final handoff interval', () {
    expect(videoDetailReturnMediaCoverOpacity(0), 0);
    expect(
      videoDetailReturnMediaCoverOpacity(videoDetailReturnMediaCoverStart),
      0,
    );
    expect(
      videoDetailReturnMediaCoverOpacity(videoDetailReturnMediaCoverEnd),
      1,
    );
    expect(videoDetailReturnMediaCoverOpacity(1), 1);
  });

  test('return media cover opacity is monotonic while the page shrinks', () {
    var previous = 0.0;
    for (var index = 0; index <= 100; index++) {
      final progress = index / 100;
      final opacity = videoDetailReturnMediaCoverOpacity(progress);
      expect(opacity, greaterThanOrEqualTo(previous));
      previous = opacity;
    }
  });
}
