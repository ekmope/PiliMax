import 'dart:async';

import 'package:PiliMax/http/loading_state.dart';
import 'package:PiliMax/models/common/video/video_type.dart';
import 'package:PiliMax/models/video/play/url.dart';
import 'package:PiliMax/pilimax/pages/video/video_detail_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  VideoDetailPlayUrlRequest request({
    String bvid = 'BV1xx411c7mD',
    int cid = 10,
    int? epId = 20,
    int? seasonId = 30,
    int qn = 80,
    bool tryLook = false,
    VideoType videoType = VideoType.ugc,
    String? language = 'zh-CN',
    bool voiceBalance = false,
    int videoAccountIdentity = 40,
    int videoAccountMid = 50,
  }) => VideoDetailPlayUrlRequest(
    bvid: bvid,
    cid: cid,
    epId: epId,
    seasonId: seasonId,
    qn: qn,
    tryLook: tryLook,
    videoType: videoType,
    language: language,
    voiceBalance: voiceBalance,
    videoAccountIdentity: videoAccountIdentity,
    videoAccountMid: videoAccountMid,
  );

  group('VideoDetailPlayUrlRequest', () {
    test('uses every request and account field for identity', () {
      final base = request();
      final same = request();
      expect(base, same);
      expect(base.hashCode, same.hashCode);

      final variants = <VideoDetailPlayUrlRequest>[
        request(bvid: 'BV1yy411c7mD'),
        request(cid: 11),
        request(epId: 21),
        request(seasonId: 31),
        request(qn: 64),
        request(tryLook: true),
        request(videoType: VideoType.pgc),
        request(language: 'yue'),
        request(voiceBalance: true),
        request(videoAccountIdentity: 41),
        request(videoAccountMid: 51),
      ];
      for (final variant in variants) {
        expect(base, isNot(variant));
      }
    });

    test('resolves the same effective API type as the detail controller', () {
      expect(
        VideoDetailPlayUrlRequest.actualVideoType(
          requestedVideoType: VideoType.pgc,
          isVideoAccountLoggedIn: false,
          usePgcApi: false,
        ),
        VideoType.ugc,
      );
      expect(
        VideoDetailPlayUrlRequest.actualVideoType(
          requestedVideoType: VideoType.ugc,
          isVideoAccountLoggedIn: true,
          usePgcApi: true,
        ),
        VideoType.pgc,
      );
      expect(
        VideoDetailPlayUrlRequest.actualVideoType(
          requestedVideoType: VideoType.pugv,
          isVideoAccountLoggedIn: true,
          usePgcApi: false,
        ),
        VideoType.pugv,
      );
    });
  });

  group('VideoDetailPlayUrlPrefetch', () {
    test('starts immediately and can be consumed only once', () async {
      final key = request();
      final completer = Completer<LoadingState<PlayUrlModel>>();
      var loadCount = 0;
      final prefetch = VideoDetailPlayUrlPrefetch.start(
        key,
        loader: () {
          loadCount++;
          return completer.future;
        },
      );

      expect(loadCount, 1);
      final result = prefetch.takeIfMatches(key);
      expect(result, isNotNull);
      expect(prefetch.takeIfMatches(key), isNull);

      final model = PlayUrlModel();
      completer.complete(Success(model));
      expect(await result, Success(model));
    });

    test('a mismatch discards the launch-only future', () {
      final key = request();
      final prefetch = VideoDetailPlayUrlPrefetch.start(
        key,
        loader: () async => Success(PlayUrlModel()),
      );

      expect(prefetch.takeIfMatches(request(cid: 11)), isNull);
      expect(prefetch.takeIfMatches(key), isNull);
    });

    test('turns loader exceptions into a single error result', () async {
      final key = request();
      final prefetch = VideoDetailPlayUrlPrefetch.start(
        key,
        loader: () => Future<LoadingState<PlayUrlModel>>.error(
          StateError('signing failed'),
        ),
      );

      final result = await prefetch.takeIfMatches(key);
      expect(result, isA<Error>());
      expect(result.toString(), contains('signing failed'));
    });

    test('preserves API errors without causing an implicit retry', () async {
      final key = request();
      final prefetch = VideoDetailPlayUrlPrefetch.start(
        key,
        loader: () async => const Error('not available'),
      );

      expect(
        await prefetch.takeIfMatches(key),
        const Error('not available'),
      );
    });

    test('cannot be consumed after disposal', () {
      final key = request();
      final prefetch = VideoDetailPlayUrlPrefetch.start(
        key,
        loader: () async => Success(PlayUrlModel()),
      )..dispose();

      expect(prefetch.takeIfMatches(key), isNull);
    });
  });
}
