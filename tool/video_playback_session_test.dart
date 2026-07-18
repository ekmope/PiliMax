import 'dart:async';

import 'package:PiliMax/pages/video/video_playback_session.dart';
import 'package:flutter_test/flutter_test.dart';

const _videoA = VideoPlaybackIdentity(
  aid: 1,
  bvid: 'BV1A',
  cid: 11,
  epId: null,
  seasonId: null,
);

const _videoB = VideoPlaybackIdentity(
  aid: 2,
  bvid: 'BV1B',
  cid: 22,
  epId: 3,
  seasonId: 4,
);

const _videoC = VideoPlaybackIdentity(
  aid: 3,
  bvid: 'BV1C',
  cid: 33,
  epId: 5,
  seasonId: 6,
);

void main() {
  test('snapshot requires the same generation, identity, and active owner', () {
    final session = VideoPlaybackSession();
    final snapshot = session.begin(_videoA);

    expect(
      session.isCurrent(
        snapshot,
        isActive: () => true,
        currentIdentity: () => _videoA,
      ),
      isTrue,
    );
    expect(
      session.isCurrent(
        snapshot,
        isActive: () => true,
        currentIdentity: () => _videoB,
      ),
      isFalse,
    );

    var identityRead = false;
    expect(
      session.isCurrent(
        snapshot,
        isActive: () => false,
        currentIdentity: () {
          identityRead = true;
          return _videoA;
        },
      ),
      isFalse,
    );
    expect(identityRead, isFalse);
  });

  test('new begin and explicit invalidate make old snapshots stale', () {
    final session = VideoPlaybackSession();
    final first = session.begin(_videoA);
    final second = session.begin(_videoA);

    bool current(VideoPlaybackSessionSnapshot snapshot) => session.isCurrent(
      snapshot,
      isActive: () => true,
      currentIdentity: () => _videoA,
    );

    expect(current(first), isFalse);
    expect(current(second), isTrue);

    session.invalidate();
    expect(current(second), isFalse);
  });

  test(
    'source switches run serially while an older running switch finishes',
    () async {
      final session = VideoPlaybackSession();
      var currentIdentity = _videoA;
      final firstSnapshot = session.begin(currentIdentity);
      final firstStarted = Completer<void>();
      final releaseFirst = Completer<void>();
      final events = <String>[];

      final first = session.enqueueSourceSwitch(
        firstSnapshot,
        isActive: () => true,
        currentIdentity: () => currentIdentity,
        action: () async {
          events.add('first-start');
          firstStarted.complete();
          await releaseFirst.future;
          events.add('first-end');
        },
      );
      await firstStarted.future;

      currentIdentity = _videoB;
      final secondSnapshot = session.begin(currentIdentity);
      final second = session.enqueueSourceSwitch(
        secondSnapshot,
        isActive: () => true,
        currentIdentity: () => currentIdentity,
        action: () async {
          events.add('second');
        },
      );

      await Future<void>.delayed(Duration.zero);
      expect(events, ['first-start']);

      releaseFirst.complete();
      await Future.wait([first, second]);
      expect(events, ['first-start', 'first-end', 'second']);
    },
  );

  test(
    'a queued stale switch is skipped in favor of the latest snapshot',
    () async {
      final session = VideoPlaybackSession();
      var currentIdentity = _videoA;
      final firstSnapshot = session.begin(currentIdentity);
      final firstStarted = Completer<void>();
      final releaseFirst = Completer<void>();
      final events = <String>[];

      final first = session.enqueueSourceSwitch(
        firstSnapshot,
        isActive: () => true,
        currentIdentity: () => currentIdentity,
        action: () async {
          events.add('first');
          firstStarted.complete();
          await releaseFirst.future;
        },
      );
      await firstStarted.future;

      currentIdentity = _videoB;
      final staleSnapshot = session.begin(currentIdentity);
      final stale = session.enqueueSourceSwitch(
        staleSnapshot,
        isActive: () => true,
        currentIdentity: () => currentIdentity,
        action: () async {
          events.add('stale');
        },
      );

      currentIdentity = _videoC;
      final latestSnapshot = session.begin(currentIdentity);
      final latest = session.enqueueSourceSwitch(
        latestSnapshot,
        isActive: () => true,
        currentIdentity: () => currentIdentity,
        action: () async {
          events.add('latest');
        },
      );

      releaseFirst.complete();
      await Future.wait([first, stale, latest]);
      expect(events, ['first', 'latest']);
    },
  );

  test('a failed switch does not poison the serialized queue', () async {
    final session = VideoPlaybackSession();
    var currentIdentity = _videoA;
    final failedSnapshot = session.begin(currentIdentity);
    final failed = session.enqueueSourceSwitch(
      failedSnapshot,
      isActive: () => true,
      currentIdentity: () => currentIdentity,
      action: () => Future<void>.error(StateError('failed switch')),
    );

    await expectLater(failed, throwsA(isA<StateError>()));

    currentIdentity = _videoB;
    final nextSnapshot = session.begin(currentIdentity);
    var nextRan = false;
    await session.enqueueSourceSwitch(
      nextSnapshot,
      isActive: () => true,
      currentIdentity: () => currentIdentity,
      action: () async {
        nextRan = true;
      },
    );
    expect(nextRan, isTrue);
  });

  test(
    'additional validity prevents stale external queries from switching',
    () async {
      final session = VideoPlaybackSession();
      final snapshot = session.begin(_videoA);
      var actionRan = false;

      await session.enqueueSourceSwitch(
        snapshot,
        isActive: () => true,
        currentIdentity: () => _videoA,
        additionalValidity: () => false,
        action: () async {
          actionRan = true;
        },
      );

      expect(actionRan, isFalse);
    },
  );
}
