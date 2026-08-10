import 'package:PiliMax/pages/video/video_detail_transition_timing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('initial player handoff', () {
    test('detail reveal only waits for the mounted layout', () {
      expect(videoDetailEntryCanReveal(detailLayoutReady: true), isTrue);
    });

    test('detail reveal never exposes an unpainted layout', () {
      expect(videoDetailEntryCanReveal(detailLayoutReady: false), isFalse);
    });

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

    test('layout readiness alone never releases the media cover', () {
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

    test('desktop surfaces use playback progress for a fresh controller', () {
      // Desktop media-kit surfaces may not complete the first-frame Future.
      expect(
        videoDetailInitialSurfaceUsesPlaybackProgress(
          isDesktop: true,
          reusesVideoController: false,
        ),
        isTrue,
      );
    });

    test('mobile fresh surfaces still wait for the first-frame signal', () {
      expect(
        videoDetailInitialSurfaceUsesPlaybackProgress(
          isDesktop: false,
          reusesVideoController: false,
        ),
        isFalse,
      );
    });

    test('reused controllers use playback progress on every platform', () {
      expect(
        videoDetailInitialSurfaceUsesPlaybackProgress(
          isDesktop: false,
          reusesVideoController: true,
        ),
        isTrue,
      );
    });
  });

  group('initial fullscreen handoff', () {
    test('desktop fullscreen state can confirm an unchanged viewport', () {
      expect(
        videoDetailFullscreenTransitionObserved(
          requireGeometryChange: false,
          fullScreenActive: true,
          metricsChanged: false,
          viewportChanged: false,
          playerRectChanged: false,
        ),
        isTrue,
      );
    });

    test('mobile fullscreen still requires a geometry signal', () {
      expect(
        videoDetailFullscreenTransitionObserved(
          requireGeometryChange: true,
          fullScreenActive: true,
          metricsChanged: false,
          viewportChanged: false,
          playerRectChanged: false,
        ),
        isFalse,
      );
    });

    test('a player rect change confirms fullscreen on every platform', () {
      expect(
        videoDetailFullscreenTransitionObserved(
          requireGeometryChange: true,
          fullScreenActive: false,
          metricsChanged: false,
          viewportChanged: false,
          playerRectChanged: true,
        ),
        isTrue,
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
