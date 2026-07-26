import 'package:PiliMax/http/download_source.dart';
import 'package:PiliMax/models/common/video/video_decode_type.dart';
import 'package:PiliMax/models/common/video/video_quality.dart';
import 'package:PiliMax/models/video/play/url.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DownloadSourceSelector.selectDashVideo', () {
    test('selects the closest quality from playable streams', () {
      final selection = DownloadSourceSelector.selectDashVideo(
        videos: [
          _video(VideoQuality.high1080, 'avc1.640028'),
          _video(VideoQuality.high720, 'avc1.64001f'),
          _video(VideoQuality.high720, 'av01.0.08M.08'),
        ],
        supportFormats: [
          _format(VideoQuality.high1080),
          _format(VideoQuality.high720),
        ],
        preferredQuality: 70,
        preferredCodecs: const [
          VideoDecodeFormatType.AV1,
          VideoDecodeFormatType.AVC,
        ],
      );

      expect(selection.quality, VideoQuality.high720.code);
      expect(selection.video.codecs, startsWith('av01'));
    });

    test('selects the numerically closest available quality', () {
      expect(
        DownloadSourceSelector.closestQuality(
          [VideoQuality.high1080.code, VideoQuality.high720.code],
          74,
        ),
        VideoQuality.high1080.code,
      );
      expect(
        DownloadSourceSelector.closestQuality(
          [VideoQuality.high1080.code, VideoQuality.high720.code],
          72,
        ),
        VideoQuality.high720.code,
      );
    });

    test('rejects empty and unplayable stream lists', () {
      expect(
        () => DownloadSourceSelector.selectDashVideo(
          videos: const [],
          supportFormats: [_format(VideoQuality.high720)],
          preferredQuality: VideoQuality.high720.code,
          preferredCodecs: const [],
        ),
        throwsA(isA<DownloadSourceException>()),
      );
      expect(
        () => DownloadSourceSelector.selectDashVideo(
          videos: [_video(VideoQuality.high720, 'avc1', url: null)],
          supportFormats: [_format(VideoQuality.high720)],
          preferredQuality: VideoQuality.high720.code,
          preferredCodecs: const [],
        ),
        throwsA(isA<DownloadSourceException>()),
      );
    });

    test('rejects missing supported formats', () {
      expect(
        () => DownloadSourceSelector.selectDashVideo(
          videos: [_video(VideoQuality.high720, 'avc1')],
          supportFormats: const [],
          preferredQuality: VideoQuality.high720.code,
          preferredCodecs: const [],
        ),
        throwsA(isA<DownloadSourceException>()),
      );
    });
  });

  group('DownloadSourceSelector.selectDurl', () {
    test('rejects missing progressive URLs', () {
      expect(
        () => DownloadSourceSelector.selectDurl(null),
        throwsA(isA<DownloadSourceException>()),
      );
      expect(
        () => DownloadSourceSelector.selectDurl(const []),
        throwsA(isA<DownloadSourceException>()),
      );
    });

    test('skips malformed progressive entries', () {
      final valid = Durl(
        order: 1,
        length: 1000,
        size: 2048,
        url: 'https://example.com/video.mp4',
      );
      final selected = DownloadSourceSelector.selectDurl([
        Durl(
          order: 1,
          length: 1000,
          size: 2048,
          backupUrl: const [''],
        ),
        valid,
      ]);

      expect(identical(selected, valid), isTrue);
    });
  });

  test('filters empty URLs before CDN selection', () {
    expect(
      DownloadSourceSelector.playableUrls([
        '',
        '  ',
        'https://example.com/video.m4s',
      ]),
      ['https://example.com/video.m4s'],
    );
  });
}

VideoItem _video(
  VideoQuality quality,
  String codec, {
  String? url = 'https://example.com/video.m4s',
}) => VideoItem(
  id: quality.code,
  baseUrl: url,
  bandWidth: 1000,
  codecs: codec,
  width: 1280,
  height: 720,
  codecid: 7,
  quality: quality,
);

FormatItem _format(VideoQuality quality) => FormatItem(
  quality: quality.code,
  newDesc: quality.desc,
  codecs: const ['avc1', 'av01'],
);
