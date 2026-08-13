import 'dart:async';

import 'package:PiliMax/grpc/bilibili/app/playurl/v1.pb.dart';
import 'package:PiliMax/http/loading_state.dart';
import 'package:PiliMax/models/common/video/video_quality.dart';
import 'package:PiliMax/pilimax/services/playback/trial_play_view_request_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TrialPlayViewRequestPlan', () {
    test('uses one qn=120 request only for enabled UGC playback', () {
      final plan = TrialPlayViewRequestPlan.automatic(
        isUgc: true,
        unlimitedTrialEnabled: true,
      );

      expect(plan, hasLength(1));
      expect(plan.single.quality, VideoQuality.super4K.code);
      expect(
        TrialPlayViewRequestPlan.automatic(
          isUgc: false,
          unlimitedTrialEnabled: true,
        ),
        isEmpty,
      );
      expect(
        TrialPlayViewRequestPlan.automatic(
          isUgc: true,
          unlimitedTrialEnabled: false,
        ),
        isEmpty,
      );
    });
  });

  group('TrialPlayViewRequestCache', () {
    test('coalesces same-key in-flight requests', () async {
      final cache = TrialPlayViewRequestCache();
      final completer = Completer<LoadingState<PlayViewReply>?>();
      var loads = 0;

      Future<LoadingState<PlayViewReply>?> loader() {
        loads++;
        return completer.future;
      }

      final first = cache.request(key: _key(), loader: loader);
      final second = cache.request(key: _key(), loader: loader);

      expect(identical(first, second), isTrue);
      expect(loads, 1);
      completer.complete(Success(_completeReply()));
      await Future.wait([first, second]);
    });

    test('caches complete success until TTL expires', () async {
      var now = DateTime(2026);
      final cache = TrialPlayViewRequestCache(now: () => now);
      var loads = 0;

      Future<LoadingState<PlayViewReply>?> loader() async {
        loads++;
        return Success(_completeReply());
      }

      await cache.request(key: _key(), loader: loader);
      await cache.request(key: _key(), loader: loader);
      expect(loads, 1);

      now = now.add(const Duration(seconds: 60));
      await cache.request(key: _key(), loader: loader);
      expect(loads, 2);
    });

    test('removes failed and incomplete responses immediately', () async {
      final cache = TrialPlayViewRequestCache();
      var loads = 0;

      Future<LoadingState<PlayViewReply>?> loader() async {
        loads++;
        return switch (loads) {
          1 => Success(PlayViewReply()),
          2 => const Error('failed'),
          _ => Success(_completeReply()),
        };
      }

      await cache.request(key: _key(), loader: loader);
      await cache.request(key: _key(), loader: loader);
      await cache.request(key: _key(), loader: loader);
      await cache.request(key: _key(), loader: loader);

      expect(loads, 3);
    });

    test('removes thrown loaders so the next request can retry', () async {
      final cache = TrialPlayViewRequestCache();
      var loads = 0;

      Future<LoadingState<PlayViewReply>?> loader() async {
        loads++;
        if (loads == 1) throw StateError('offline');
        return Success(_completeReply());
      }

      await expectLater(
        cache.request(key: _key(), loader: loader),
        throwsStateError,
      );
      await cache.request(key: _key(), loader: loader);

      expect(loads, 2);
    });

    test('bounds distinct entries and clear forces a reload', () async {
      final cache = TrialPlayViewRequestCache(maxEntries: 2);
      var loads = 0;

      Future<LoadingState<PlayViewReply>?> loader() async {
        loads++;
        return Success(_completeReply());
      }

      await cache.request(key: _key(cid: 1), loader: loader);
      await cache.request(key: _key(cid: 2), loader: loader);
      await cache.request(key: _key(cid: 3), loader: loader);
      await cache.request(key: _key(cid: 1), loader: loader);
      expect(loads, 4);

      cache.clear();
      await cache.request(key: _key(cid: 1), loader: loader);
      expect(loads, 5);
    });

    test('never evicts an in-flight request when the cache is full', () async {
      final cache = TrialPlayViewRequestCache(maxEntries: 2);
      final completers = <int, Completer<LoadingState<PlayViewReply>?>>{};
      final loads = <int, int>{};

      Future<LoadingState<PlayViewReply>?> load(int cid) {
        loads.update(cid, (count) => count + 1, ifAbsent: () => 1);
        return (completers[cid] ??= Completer()).future;
      }

      Future<LoadingState<PlayViewReply>?> request(int cid) => cache.request(
        key: _key(cid: cid),
        loader: () => load(cid),
      );

      final first = request(1);
      request(2);
      request(3);
      final firstAgain = request(1);

      expect(identical(first, firstAgain), isTrue);
      expect(loads[1], 1);
      for (final completer in completers.values) {
        completer.complete(Success(_completeReply()));
      }
      await Future.wait([first, firstAgain]);
    });
  });
}

TrialPlayViewRequestCacheKey _key({int cid = 2}) =>
    TrialPlayViewRequestCacheKey(
      accountMid: 1,
      aid: 1,
      cid: cid,
      quality: VideoQuality.super4K.code,
    );

PlayViewReply _completeReply() => PlayViewReply(videoInfo: VideoInfo());
