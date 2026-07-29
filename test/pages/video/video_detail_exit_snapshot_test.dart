import 'package:PiliMax/pages/video/video_detail_exit_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VideoDetailExitSnapshotPolicy', () {
    test('keeps the page live while danmaku is visible', () {
      expect(
        VideoDetailExitSnapshotPolicy.shouldCapture(
          hasVisibleDanmaku: true,
        ),
        isFalse,
      );
    });

    test('allows the optimized snapshot without danmaku', () {
      expect(
        VideoDetailExitSnapshotPolicy.shouldCapture(
          hasVisibleDanmaku: false,
        ),
        isTrue,
      );
    });
  });
}
