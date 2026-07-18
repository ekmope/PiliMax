import 'dart:async';
import 'dart:collection';

import 'package:PiliMax/models_new/video/video_play_info/subtitle.dart';
import 'package:PiliMax/pages/video/video_subtitle_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'track mutations are serialized across video page coordinators',
    () async {
      final sharedState = VideoSubtitleSharedState();
      final player = _FakeSubtitlePlayer();
      final firstGate = Completer<void>();
      final firstStarted = Completer<void>();
      player.onPrimary = (track) async {
        if (!firstStarted.isCompleted) {
          firstStarted.complete();
          await firstGate.future;
        }
      };
      final first = _Harness(
        sharedState: sharedState,
        player: player,
        subtitles: [_subtitle('first', '/first')],
      )..sources[0] = (isData: false, id: 'first.vtt');
      final second = _Harness(
        sharedState: sharedState,
        player: player,
        subtitles: [_subtitle('second', '/second')],
      )..sources[0] = (isData: false, id: 'second.vtt');

      final firstSelection = first.coordinator.selectPrimary(1);
      await firstStarted.future;
      final secondSelection = second.coordinator.selectPrimary(1);
      await _flushAsyncCallbacks();

      expect(player.primaryTracks.map((track) => track?.uri), ['first.vtt']);

      firstGate.complete();
      await Future.wait([firstSelection, secondSelection]);

      expect(
        player.primaryTracks.map((track) => track?.uri),
        ['first.vtt', 'second.vtt'],
      );
      expect(first.primaryIndex, 1);
      expect(second.primaryIndex, 1);
    },
  );

  test('a late VTT response cannot overwrite a newer primary choice', () async {
    final requests = <String, Completer<String?>>{};
    final player = _FakeSubtitlePlayer();
    final harness = _Harness(
      player: player,
      subtitles: [
        _subtitle('first', '/first'),
        _subtitle('second', '/second'),
      ],
      loadVtt: (url) => (requests[url] = Completer<String?>()).future,
    );

    final firstSelection = harness.coordinator.selectPrimary(1);
    await _flushAsyncCallbacks();
    final secondSelection = harness.coordinator.selectPrimary(2);
    await _flushAsyncCallbacks();

    requests['/second']!.complete('second-data');
    await secondSelection;
    requests['/first']!.complete('stale-first-data');
    await firstSelection;

    expect(player.primaryTracks, hasLength(1));
    expect(player.primaryTracks.single?.uri, 'memory://second-data');
    expect(harness.primaryIndex, 2);
    expect(harness.sources[1]?.id, 'second-data');
    expect(harness.sources.containsKey(0), isFalse);
  });

  test(
    'primary wins when a same-track secondary VTT request is in flight',
    () async {
      final requests = Queue<Completer<String?>>();
      final player = _FakeSubtitlePlayer();
      final harness = _Harness(
        player: player,
        subtitles: [_subtitle('same', '/same')],
        loadVtt: (_) {
          final request = Completer<String?>();
          requests.add(request);
          return request.future;
        },
      );

      final secondarySelection = harness.coordinator.selectSecondary(1);
      await _flushAsyncCallbacks();
      final staleSecondaryRequest = requests.removeFirst();

      final primarySelection = harness.coordinator.selectPrimary(1);
      await _flushAsyncCallbacks();
      requests.removeFirst().complete('primary-data');
      await primarySelection;

      staleSecondaryRequest.complete('stale-secondary-data');
      await secondarySelection;

      expect(player.primaryTracks.single?.uri, 'memory://primary-data');
      expect(
        player.secondaryTracks.whereType<VideoSubtitleTrack>(),
        isEmpty,
      );
      expect(player.secondaryTracks, contains(null));
      expect(harness.primaryIndex, 1);
      expect(harness.secondaryIndex, 0);
      expect(harness.sources.values.single.id, 'primary-data');
    },
  );

  test(
    'context invalidation drops a late VTT result without caching it',
    () async {
      final request = Completer<String?>();
      final player = _FakeSubtitlePlayer();
      final harness = _Harness(
        player: player,
        subtitles: [_subtitle('old', '/old')],
        loadVtt: (_) => request.future,
      );

      final selection = harness.coordinator.selectPrimary(1);
      await _flushAsyncCallbacks();
      harness.context = const VideoSubtitleContext(
        bvid: 'new',
        cid: 2,
        epId: null,
        seasonId: null,
      );
      harness.coordinator.invalidate();
      request.complete('stale-data');
      await selection;

      expect(player.primaryTracks, isEmpty);
      expect(harness.sources, isEmpty);
      expect(harness.primaryIndex, -1);
    },
  );

  test(
    'a stale player completion cannot publish into a replacement source',
    () async {
      final oldPlayer = _FakeSubtitlePlayer();
      final oldStarted = Completer<void>();
      final releaseOld = Completer<void>();
      oldPlayer.onPrimary = (_) async {
        oldStarted.complete();
        await releaseOld.future;
      };
      final newPlayer = _FakeSubtitlePlayer();
      final harness =
          _Harness(
              player: oldPlayer,
              subtitles: [
                _subtitle('old', '/old'),
                _subtitle('new', '/new'),
              ],
            )
            ..sources[0] = (isData: false, id: 'old.vtt')
            ..sources[1] = (isData: false, id: 'new.vtt');

      final staleSelection = harness.coordinator.selectPrimary(1);
      await oldStarted.future;
      harness
        ..context = const VideoSubtitleContext(
          bvid: 'new',
          cid: 2,
          epId: null,
          seasonId: null,
        )
        ..player = newPlayer;
      harness.coordinator.invalidate();
      releaseOld.complete();
      await staleSelection;

      expect(harness.primaryIndex, -1);

      await harness.coordinator.selectPrimary(2);

      expect(newPlayer.primaryTracks.single?.uri, 'new.vtt');
      expect(harness.primaryIndex, 2);
    },
  );

  test('a failed player mutation does not poison the shared queue', () async {
    final player = _FakeSubtitlePlayer();
    var failNext = true;
    player.onPrimary = (_) async {
      if (failNext) {
        failNext = false;
        throw StateError('primary failed');
      }
    };
    final harness =
        _Harness(
            player: player,
            subtitles: [
              _subtitle('first', '/first'),
              _subtitle('second', '/second'),
            ],
          )
          ..sources[0] = (isData: false, id: 'first.vtt')
          ..sources[1] = (isData: false, id: 'second.vtt');

    await expectLater(
      harness.coordinator.selectPrimary(1),
      throwsA(isA<StateError>()),
    );
    await harness.coordinator.selectPrimary(2);

    expect(player.primaryTracks, hasLength(2));
    expect(player.primaryTracks.last?.uri, 'second.vtt');
    expect(harness.primaryIndex, 2);
  });
}

Subtitle _subtitle(String language, String url) => Subtitle(
  lan: language,
  lanDoc: language,
  subtitleUrl: url,
);

Future<void> _flushAsyncCallbacks() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

final class _Harness {
  _Harness({
    required this.player,
    required this.subtitles,
    VideoSubtitleSharedState? sharedState,
    VideoSubtitleLoader? loadVtt,
  }) {
    coordinator = VideoSubtitleCoordinator(
      subtitles: () => subtitles,
      sources: sources,
      primaryIndex: () => primaryIndex,
      setPrimaryIndex: (value) => primaryIndex = value,
      secondaryIndex: () => secondaryIndex,
      setSecondaryIndex: (value) => secondaryIndex = value,
      currentContext: () => context,
      isCurrentSource: () => active,
      playerProvider: () => player,
      loadVtt: loadVtt ?? ((_) async => null),
      sharedState: sharedState ?? VideoSubtitleSharedState(),
    );
  }

  final List<Subtitle> subtitles;
  final Map<int, VideoSubtitleSource> sources = {};
  late VideoSubtitleCoordinator coordinator;
  VideoSubtitlePlayer? player;
  bool active = true;
  int primaryIndex = -1;
  int secondaryIndex = 0;
  VideoSubtitleContext context = const VideoSubtitleContext(
    bvid: 'old',
    cid: 1,
    epId: null,
    seasonId: null,
  );
}

final class _FakeSubtitlePlayer implements VideoSubtitlePlayer {
  final List<VideoSubtitleTrack?> primaryTracks = [];
  final List<VideoSubtitleTrack?> secondaryTracks = [];
  Future<void> Function(VideoSubtitleTrack? track)? onPrimary;
  Future<void> Function(VideoSubtitleTrack? track)? onSecondary;

  @override
  Object get identity => this;

  @override
  Future<void> setPrimarySubtitle(VideoSubtitleTrack? track) async {
    primaryTracks.add(track);
    await onPrimary?.call(track);
  }

  @override
  Future<void> setSecondarySubtitle(VideoSubtitleTrack? track) async {
    secondaryTracks.add(track);
    await onSecondary?.call(track);
  }
}
