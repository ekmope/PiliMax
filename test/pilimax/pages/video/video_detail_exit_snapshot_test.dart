import 'package:PiliMax/pilimax/pages/video/video_detail_exit_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VideoDetailExitSnapshotPolicy', () {
    test('captures the non-media layers while playback is active', () {
      expect(
        VideoDetailExitSnapshotPolicy.shouldCapture(isPlaying: true),
        isTrue,
      );
    });

    test('keeps paused detail exits live', () {
      expect(
        VideoDetailExitSnapshotPolicy.shouldCapture(isPlaying: false),
        isFalse,
      );
    });
  });
}
