import 'package:PiliMax/models/common/video/video_type.dart';
import 'package:PiliMax/pages/video/video_detail_args.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VideoDetailArgs.normalize', () {
    test('defaults a missing video type to UGC', () {
      final arguments = <dynamic, dynamic>{
        'heroTag': 'video-detail-test',
      };

      final normalized = VideoDetailArgs.normalize(arguments);

      expect(identical(normalized, arguments), isTrue);
      expect(normalized['videoType'], VideoType.ugc);
    });

    test('restores a serialized video type name', () {
      final normalized = VideoDetailArgs.normalize({
        'heroTag': 'video-detail-test',
        'videoType': 'pgc',
      });

      expect(normalized['videoType'], VideoType.pgc);
    });

    test('adds safe defaults for non-map arguments', () {
      final normalized = VideoDetailArgs.normalize(null);

      expect(normalized['videoType'], VideoType.ugc);
      expect(normalized['heroTag'], startsWith('video-detail-unknown-'));
    });
  });
}
