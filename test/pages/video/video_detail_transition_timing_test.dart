import 'package:PiliMax/pages/video/video_detail_transition_timing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('initial player handoff', () {
    test('releases when the current player visual and layout are ready', () {
      expect(
        videoDetailPlayerHandoffCanRelease(
          playerVisualReady: true,
          forceRelease: false,
          detailLayoutReady: true,
        ),
        isTrue,
      );
    });

    test('soft timeout reveals the layout without releasing media', () {
      expect(
        videoDetailPlayerHandoffCanReveal(
          playerVisualReady: false,
          handoffTimedOut: true,
          detailLayoutReady: true,
        ),
        isTrue,
      );
    });

    test('soft timeout alone never releases the media cover', () {
      expect(
        videoDetailPlayerHandoffCanRelease(
          playerVisualReady: false,
          forceRelease: false,
          detailLayoutReady: true,
        ),
        isFalse,
      );
    });

    test('hard timeout releases once the detail layout is ready', () {
      expect(
        videoDetailPlayerHandoffCanRelease(
          playerVisualReady: false,
          forceRelease: true,
          detailLayoutReady: true,
        ),
        isTrue,
      );
    });

    test('never releases against an unpainted detail layout', () {
      expect(
        videoDetailPlayerHandoffCanRelease(
          playerVisualReady: true,
          forceRelease: true,
          detailLayoutReady: false,
        ),
        isFalse,
      );
    });

    test('waits while neither a visual nor timeout is available', () {
      expect(
        videoDetailPlayerHandoffCanReveal(
          playerVisualReady: false,
          handoffTimedOut: false,
          detailLayoutReady: true,
        ),
        isFalse,
      );
    });
  });

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
