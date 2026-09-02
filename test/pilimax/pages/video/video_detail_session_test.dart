import 'package:PiliMax/models/common/video/video_type.dart';
import 'package:PiliMax/pilimax/pages/video/video_detail_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VideoDetailSkeletonProfile', () {
    test('uses stable defaults for a generic detail page', () {
      const profile = VideoDetailSkeletonProfile();

      expect(profile.hasSeasonPanel, isFalse);
      expect(profile.hasPagesPanel, isFalse);
      expect(profile.tabCount, 2);
      expect(profile.actionCount, 6);
      expect(profile.hasEpisodePanel, isFalse);
    });

    test(
      'copyWith changes selected fields without losing the profile shape',
      () {
        const profile = VideoDetailSkeletonProfile(
          hasSeasonPanel: true,
          hasPagesPanel: false,
          tabCount: 3,
          actionCount: 7,
          hasEpisodePanel: true,
        );

        final updated = profile.copyWith(
          hasPagesPanel: true,
          actionCount: 5,
        );

        expect(updated.hasSeasonPanel, isTrue);
        expect(updated.hasPagesPanel, isTrue);
        expect(updated.tabCount, 3);
        expect(updated.actionCount, 5);
        expect(updated.hasEpisodePanel, isTrue);
      },
    );
  });

  group('VideoDetailSession.contentKey', () {
    test('prefers the most specific identifier for each video type', () {
      expect(
        VideoDetailSession.contentKey(
          videoType: VideoType.ugc,
          aid: 1,
          bvid: 'BV1source',
          cid: 10,
          seasonId: 30,
          epId: 20,
        ),
        'ugc:BV1source:10',
      );
      expect(
        VideoDetailSession.contentKey(
          videoType: VideoType.pgc,
          aid: 1,
          bvid: 'BV1source',
          cid: 10,
          seasonId: 30,
          epId: 20,
        ),
        'pgc:20:10',
      );
      expect(
        VideoDetailSession.contentKey(
          videoType: VideoType.pugv,
          aid: 1,
          bvid: 'BV1source',
          cid: 10,
          seasonId: 30,
          epId: null,
        ),
        'pugv:30:10',
      );
    });

    test(
      'falls back deterministically when optional identifiers are absent',
      () {
        expect(
          VideoDetailSession.contentKey(
            videoType: VideoType.ugc,
            aid: 42,
            bvid: null,
            cid: null,
            seasonId: null,
            epId: null,
          ),
          'ugc:42:unknown',
        );
        expect(
          VideoDetailSession.contentKey(
            videoType: VideoType.pgc,
            aid: null,
            bvid: null,
            cid: null,
            seasonId: null,
            epId: null,
          ),
          'pgc:unknown:unknown',
        );
      },
    );

    test('contentKeyFor defaults a missing or serialized type to UGC', () {
      expect(
        VideoDetailSession.contentKeyFor(<dynamic, dynamic>{
          'bvid': 'BV1ugc',
          'cid': 11,
        }),
        'ugc:BV1ugc:11',
      );
      expect(
        VideoDetailSession.contentKeyFor(<dynamic, dynamic>{
          'videoType': 'pgc',
          'bvid': 'BV1serialized',
          'cid': 12,
        }),
        'ugc:BV1serialized:12',
      );
      expect(
        VideoDetailSession.contentKeyFor(<dynamic, dynamic>{
          'videoType': VideoType.pgc,
          'epId': 99,
          'cid': 13,
        }),
        'pgc:99:13',
      );
    });
  });
}
