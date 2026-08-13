import 'package:PiliMax/pilimax/pages/video/video_detail_exit_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VideoDetailExitSnapshotPolicy', () {
    test('keeps every video-detail exit live', () {
      expect(VideoDetailExitSnapshotPolicy.shouldCapture(), isFalse);
    });
  });
}
