import 'dart:math';

import 'package:PiliMax/models/common/list_order.dart';
import 'package:PiliMax/models_new/media_list/media_list.dart';
import 'package:PiliMax/models_new/media_list/page.dart';
import 'package:PiliMax/pages/video/video_media_list_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

MediaListItemModel item({
  required int aid,
  required String? bvid,
  int? cid,
  int? progress,
  int? duration,
  List<int>? pageCids,
}) => MediaListItemModel(
  aid: aid,
  bvid: bvid,
  cid: cid,
  progress: progress,
  duration: duration,
  pages: pageCids?.map((id) => Page(id: id)).toList(),
);

void main() {
  group('VideoMediaListCoordinator ordering', () {
    test('shuffle pagination commits every successful page once', () {
      final coordinator = VideoMediaListCoordinator(random: Random(7))
        ..setInitialOrder(ListOrder.desc)
        ..advanceOrder(totalCount: 41);

      final pages = <int>[];
      while (true) {
        final request = coordinator.beginRequest(
          totalCount: 41,
          isReverse: false,
          isLoadPrevious: false,
          playbackIdentity: 'video',
        );
        if (request == null) break;
        pages.add(request.page!);
        final result = coordinator.applyFetchedItems(
          request: request,
          fetched: [
            item(aid: 100 + request.page!, bvid: 'page-${request.page}'),
          ],
          currentBvid: 'missing',
          currentPlaybackIdentity: 'video',
        );
        expect(result.accepted, isTrue);
      }

      expect(coordinator.order, ListOrder.shuffle);
      expect(pages.toSet(), {1, 2, 3});
      expect(pages, hasLength(3));
      expect(pages.first, isNot(3));
    });

    test(
      'failed shuffle response retries, then empty page advances',
      () {
        final coordinator = VideoMediaListCoordinator(random: Random(5))
          ..setInitialOrder(ListOrder.shuffle);
        final failed = coordinator.beginRequest(
          totalCount: 60,
          isReverse: false,
          isLoadPrevious: false,
          playbackIdentity: 'video',
        )!;
        expect(coordinator.abandonRequest(failed), isTrue);

        final retried = coordinator.beginRequest(
          totalCount: 60,
          isReverse: false,
          isLoadPrevious: false,
          playbackIdentity: 'video',
        )!;
        expect(retried.page, failed.page);
        expect(
          coordinator
              .applyFetchedItems(
                request: retried,
                fetched: const [],
                currentBvid: 'missing',
                currentPlaybackIdentity: 'video',
              )
              .accepted,
          isTrue,
        );

        final afterEmpty = coordinator.beginRequest(
          totalCount: 60,
          isReverse: false,
          isLoadPrevious: false,
          playbackIdentity: 'video',
        )!;
        expect(afterEmpty.page, isNot(failed.page));
      },
    );

    test('stale response cannot overwrite a newer order generation', () {
      final coordinator = VideoMediaListCoordinator()
        ..setInitialOrder(ListOrder.asc);
      final stale = coordinator.beginRequest(
        totalCount: 40,
        isReverse: true,
        isLoadPrevious: false,
        playbackIdentity: 'old-video',
      )!;

      expect(coordinator.advanceOrder(totalCount: 40), ListOrder.desc);
      final current = coordinator.beginRequest(
        totalCount: 40,
        isReverse: true,
        isLoadPrevious: false,
        playbackIdentity: 'current-video',
      )!;
      final currentItem = item(aid: 2, bvid: 'current', pageCids: [20]);
      expect(
        coordinator
            .applyFetchedItems(
              request: current,
              fetched: [currentItem],
              currentBvid: 'old',
              currentPlaybackIdentity: 'current-video',
            )
            .accepted,
        isTrue,
      );

      expect(
        coordinator
            .applyFetchedItems(
              request: stale,
              fetched: [
                item(aid: 1, bvid: 'stale', pageCids: [10]),
              ],
              currentBvid: 'old',
              currentPlaybackIdentity: 'current-video',
            )
            .accepted,
        isFalse,
      );
      expect(coordinator.items, [currentItem]);
    });

    test('reverse refresh cannot auto-select after a manual video change', () {
      final coordinator = VideoMediaListCoordinator();
      final request = coordinator.beginRequest(
        totalCount: 1,
        isReverse: true,
        isLoadPrevious: false,
        playbackIdentity: 'video-before-request',
      )!;
      final fetched = item(aid: 1, bvid: 'fetched', pageCids: [10]);

      final result = coordinator.applyFetchedItems(
        request: request,
        fetched: [fetched],
        currentBvid: 'manually-selected',
        currentPlaybackIdentity: 'manually-selected-video',
      );

      expect(result.accepted, isTrue);
      expect(result.nextEpisode, isNull);
      expect(coordinator.items, [fetched]);
    });

    test('same generation serializes requests', () {
      final coordinator = VideoMediaListCoordinator();
      final first = coordinator.beginRequest(
        totalCount: null,
        isReverse: false,
        isLoadPrevious: false,
        playbackIdentity: 'video',
      );
      final overlapping = coordinator.beginRequest(
        totalCount: null,
        isReverse: false,
        isLoadPrevious: true,
        playbackIdentity: 'video',
      );

      expect(first, isNotNull);
      expect(overlapping, isNull);
    });

    test(
      'shuffle merge is atomic, deduplicated, and never drops fetched items',
      () async {
        final coordinator = VideoMediaListCoordinator(random: Random(11))
          ..setInitialOrder(ListOrder.shuffle);
        final before = item(aid: 1, bvid: 'before');
        final current = item(aid: 2, bvid: 'current');
        final oldTail = item(aid: 3, bvid: 'old-tail');
        coordinator.items.addAll([before, current, oldTail]);
        final fetched = List.generate(
          20,
          (index) => item(aid: 100 + index, bvid: 'new-$index'),
        )..add(item(aid: 3, bvid: 'old-tail', progress: 99));
        final snapshots = <List<MediaListItemModel>>[];
        final subscription = coordinator.items.listen(
          (value) => snapshots.add(List<MediaListItemModel>.of(value)),
        );
        final request = coordinator.beginRequest(
          totalCount: 100,
          isReverse: false,
          isLoadPrevious: false,
          playbackIdentity: 'video',
        )!;

        final result = coordinator.applyFetchedItems(
          request: request,
          fetched: fetched,
          currentBvid: 'current',
          currentPlaybackIdentity: 'video',
        );
        await Future<void>.delayed(Duration.zero);

        expect(result.accepted, isTrue);
        expect(coordinator.items, hasLength(23));
        expect(coordinator.items.take(2), [before, current]);
        expect(
          coordinator.items.singleWhere((value) => value.aid == 3).progress,
          99,
        );
        for (final fetchedItem in fetched.where((value) => value.aid != 3)) {
          expect(coordinator.items, contains(fetchedItem));
        }
        expect(snapshots, hasLength(1));
        expect(snapshots.single, hasLength(23));
        await subscription.cancel();
      },
    );

    test('reverse refresh returns the first playable item', () {
      final coordinator = VideoMediaListCoordinator(random: Random(2));
      final unavailable = item(aid: 1, bvid: 'missing-pages');
      final playable = item(aid: 2, bvid: 'playable', pageCids: [22]);

      final request = coordinator.beginRequest(
        totalCount: 2,
        isReverse: true,
        isLoadPrevious: false,
        playbackIdentity: 'video',
      )!;
      final result = coordinator.applyFetchedItems(
        request: request,
        fetched: [unavailable, playable],
        currentBvid: 'old',
        currentPlaybackIdentity: 'video',
      );

      expect(result.nextEpisode, same(playable));
      expect(coordinator.items, [unavailable, playable]);
    });

    test('deduplication prefers aid when bvid availability changes', () {
      final coordinator = VideoMediaListCoordinator();
      final oldItem = item(aid: 123, bvid: null, progress: 1);
      final refreshedItem = item(aid: 123, bvid: 'BV123', progress: 2);
      coordinator.items.add(oldItem);
      final request = coordinator.beginRequest(
        totalCount: 2,
        isReverse: false,
        isLoadPrevious: false,
        playbackIdentity: 'video',
      )!;

      coordinator.applyFetchedItems(
        request: request,
        fetched: [refreshedItem],
        currentBvid: 'current',
        currentPlaybackIdentity: 'video',
      );

      expect(coordinator.items, [refreshedItem]);
    });
  });

  group('VideoMediaListCoordinator progress', () {
    test('JSON model preserves a top-level cid without pages', () {
      final parsed = MediaListItemModel.fromJson({
        'id': 5,
        'bv_id': 'BV5',
        'cid': 50,
      });

      expect(parsed.cid, 50);
    });

    test('updates only the matching page and clamps progress', () {
      final coordinator = VideoMediaListCoordinator();
      final first = item(
        aid: 1,
        bvid: 'BV1',
        progress: 3,
        pageCids: [10, 11],
      );
      final second = item(
        aid: 2,
        bvid: 'BV2',
        progress: 4,
        pageCids: [20],
      );
      coordinator.items.addAll([first, second]);

      expect(
        coordinator.updateProgress(
          videoAid: 1,
          videoBvid: 'BV1',
          videoCid: 11,
          progressSeconds: 500,
          videoDuration: 120,
        ),
        isTrue,
      );
      expect(first.progress, 120);
      expect(second.progress, 4);
      expect(
        coordinator.updateProgress(
          videoAid: 1,
          videoBvid: 'BV1',
          videoCid: 99,
          progressSeconds: 5,
          videoDuration: 120,
        ),
        isFalse,
      );
      expect(
        coordinator.updateProgress(
          videoAid: 1,
          videoBvid: 'BV1',
          videoCid: 10,
          progressSeconds: -1,
          videoDuration: 120,
        ),
        isTrue,
      );
      expect(first.progress, -1);
    });

    test(
      'audio snapshot is valid, unique, and excludes multi-page ambiguity',
      () {
        final coordinator = VideoMediaListCoordinator();
        coordinator.items.addAll([
          item(
            aid: 1,
            bvid: 'current-copy',
            progress: 8,
            duration: 100,
            pageCids: [10],
          ),
          item(
            aid: 2,
            bvid: 'single',
            progress: 15,
            duration: 10,
            pageCids: [20],
          ),
          item(aid: 3, bvid: 'multi', progress: 30, pageCids: [30, 31]),
          item(aid: 4, bvid: 'invalid', progress: 0, pageCids: [40]),
          item(
            aid: 5,
            bvid: 'without-pages',
            cid: 50,
            progress: 18,
            duration: 20,
          ),
        ]);

        expect(
          coordinator.buildAudioProgressSnapshot(
            currentAid: 1,
            currentCid: 10,
            currentProgress: 700,
            currentDuration: 100,
          ),
          [
            {'aid': 1, 'cid': 10, 'progress': 100},
            {'aid': 2, 'cid': 20, 'progress': 10},
            {'aid': 5, 'cid': 50, 'progress': 18},
          ],
        );
      },
    );

    test('duration and heartbeat policy handles completion boundaries', () {
      expect(
        VideoMediaListCoordinator.resolveDurationSeconds(
          timeLengthMilliseconds: 1501,
        ),
        2,
      );
      expect(
        VideoMediaListCoordinator.resolveDurationSeconds(
          timeLengthMilliseconds: null,
          fallbackDuration: const Duration(milliseconds: 200),
        ),
        1,
      );
      expect(
        VideoMediaListCoordinator.heartBeatProgressSeconds(
          position: Duration.zero,
          isCompleted: false,
          timeLengthMilliseconds: 500,
        ),
        0,
      );
      expect(
        VideoMediaListCoordinator.heartBeatProgressSeconds(
          position: Duration.zero,
          isCompleted: false,
          timeLengthMilliseconds: 1000,
        ),
        0,
      );
      expect(
        VideoMediaListCoordinator.heartBeatProgressSeconds(
          position: const Duration(milliseconds: 450),
          isCompleted: false,
          timeLengthMilliseconds: 500,
        ),
        -1,
      );
      expect(
        VideoMediaListCoordinator.heartBeatProgressSeconds(
          position: const Duration(milliseconds: 9300),
          isCompleted: false,
          timeLengthMilliseconds: 10000,
        ),
        -1,
      );
      expect(
        VideoMediaListCoordinator.heartBeatProgressSeconds(
          position: Duration.zero,
          isCompleted: true,
          timeLengthMilliseconds: null,
        ),
        -1,
      );
      expect(
        VideoMediaListCoordinator.heartBeatProgressSeconds(
          position: const Duration(seconds: 12),
          isCompleted: false,
          timeLengthMilliseconds: 10000,
        ),
        -1,
      );
      expect(
        VideoMediaListCoordinator.heartBeatProgressSeconds(
          position: const Duration(seconds: 3),
          isCompleted: false,
          timeLengthMilliseconds: 10000,
        ),
        3,
      );
    });
  });
}
