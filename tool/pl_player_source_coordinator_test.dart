import 'dart:async';

import 'package:PiliMax/plugin/pl_player/pl_player_source_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

final class _FakePlayer {
  _FakePlayer(this.name);

  final String name;
  final events = StreamController<String>.broadcast(sync: true);

  Future<void> dispose() => events.close();
}

PlPlayerPreparedSource<_FakePlayer> _prepared({
  required _FakePlayer player,
  required _FakePlayer? Function() currentPlayer,
  required void Function(String event) onEvent,
  void Function(String event)? onOpeningEvent,
  Future<void> Function()? open,
  void Function()? didOpen,
  Future<void> Function()? initialize,
  FutureOr<void> Function()? discard,
}) => PlPlayerPreparedSource<_FakePlayer>(
  player: player,
  subscribe: (lease) => [
    player.events.stream.listen((event) {
      final sourceCurrent = lease.isCurrent(currentPlayer());
      final active = lease.isCurrent(currentPlayer(), requireActive: true);
      if (sourceCurrent && !active) {
        onOpeningEvent?.call(event);
      }
      if (active) {
        onEvent(event);
      }
    }),
  ],
  open: (_) => open?.call() ?? Future<void>.value(),
  didOpen: (_) => didOpen?.call(),
  initialize: (_) => initialize?.call() ?? Future<void>.value(),
  discard: discard,
);

const _shortTimeouts = PlPlayerSourceTimeouts(
  prepare: Duration(milliseconds: 40),
  open: Duration(milliseconds: 40),
  initialize: Duration(milliseconds: 40),
  refresh: Duration(milliseconds: 40),
  retry: Duration(milliseconds: 60),
  activeOperation: Duration(milliseconds: 40),
  abort: Duration(milliseconds: 10),
);

void main() {
  for (final asynchronous in [false, true]) {
    test(
      '${asynchronous ? 'microtask' : 'synchronous'} opening error prevents activation',
      () async {
        _FakePlayer? currentPlayer;
        final coordinator = PlPlayerSourceCoordinator<_FakePlayer>(
          currentPlayer: () => currentPlayer,
          timeouts: _shortTimeouts,
        );
        final player = _FakePlayer('opening-error');
        String? openingError;
        var discarded = 0;
        currentPlayer = player;

        final result = await coordinator.openSource(
          owner: Object(),
          prepare: (attempt) async {
            attempt.registerAbort(() => discarded++);
            return _prepared(
              player: player,
              currentPlayer: () => currentPlayer,
              onEvent: (_) {},
              onOpeningEvent: (event) => openingError ??= event,
              open: () async {
                if (asynchronous) {
                  scheduleMicrotask(() => player.events.add('open failed'));
                } else {
                  player.events.add('open failed');
                }
                await Future<void>.delayed(Duration.zero);
                if (openingError != null) {
                  throw StateError('opening error');
                }
              },
              discard: attempt.abort,
            );
          },
        );

        expect(result, isFalse);
        expect(coordinator.activeLease(), isNull);
        expect(discarded, 1);
        await player.dispose();
      },
    );
  }

  test(
    'didOpen rechecks an opening error delivered after open-side check',
    () async {
      _FakePlayer? currentPlayer;
      final coordinator = PlPlayerSourceCoordinator<_FakePlayer>(
        currentPlayer: () => currentPlayer,
        timeouts: _shortTimeouts,
      );
      final player = _FakePlayer('handoff-opening-error');
      var openingFailed = false;
      var published = false;
      var discarded = 0;
      currentPlayer = player;

      final result = await coordinator.openSource(
        owner: Object(),
        prepare: (attempt) async {
          attempt.registerAbort(() => discarded++);
          return _prepared(
            player: player,
            currentPlayer: () => currentPlayer,
            onEvent: (_) {},
            onOpeningEvent: (_) => openingFailed = true,
            open: () async {
              expect(openingFailed, isFalse);
              scheduleMicrotask(
                () => player.events.add('late open failure'),
              );
            },
            didOpen: () {
              if (openingFailed) throw StateError('opening error');
              published = true;
            },
            discard: attempt.abort,
          );
        },
      );

      expect(result, isFalse);
      expect(published, isFalse);
      expect(discarded, 1);
      expect(coordinator.activeLease(), isNull);
      await player.dispose();
    },
  );

  test('abort requested before registration still runs cleanup once', () async {
    final coordinator = PlPlayerSourceCoordinator<_FakePlayer>(
      currentPlayer: () => null,
      timeouts: _shortTimeouts,
    );
    var aborted = 0;

    final result = await coordinator.openSource(
      owner: Object(),
      prepare: (attempt) async {
        await attempt.abort();
        attempt.registerAbort(() => aborted++);
        return null;
      },
    );

    expect(result, isFalse);
    expect(aborted, 1);
  });

  test('a reentrant abort callback is started exactly once', () async {
    final coordinator = PlPlayerSourceCoordinator<_FakePlayer>(
      currentPlayer: () => null,
      timeouts: _shortTimeouts,
    );
    var aborted = 0;
    Future<void>? reentrantAbort;

    final result = await coordinator.openSource(
      owner: Object(),
      prepare: (attempt) async {
        attempt.registerAbort(() {
          aborted++;
          reentrantAbort = attempt.abort();
        });
        await attempt.abort();
        await reentrantAbort;
        return null;
      },
    );

    expect(result, isFalse);
    expect(aborted, 1);
  });

  test('a preparation completing after timeout is discarded once', () async {
    _FakePlayer? currentPlayer;
    final coordinator = PlPlayerSourceCoordinator<_FakePlayer>(
      currentPlayer: () => currentPlayer,
      timeouts: _shortTimeouts,
    );
    final player = _FakePlayer('late-preparation');
    final releasePreparation = Completer<void>();
    var aborted = 0;
    var discarded = 0;

    final result = await coordinator.openSource(
      owner: Object(),
      prepare: (attempt) async {
        attempt.registerAbort(() => aborted++);
        await releasePreparation.future;
        currentPlayer = player;
        return _prepared(
          player: player,
          currentPlayer: () => currentPlayer,
          onEvent: (_) {},
          discard: () => discarded++,
        );
      },
    );

    expect(result, isFalse);
    expect(aborted, 1);
    releasePreparation.complete();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(discarded, 1);
    await player.dispose();
  });

  test('a stale in-flight open cannot activate or initialize', () async {
    _FakePlayer? currentPlayer;
    final coordinator = PlPlayerSourceCoordinator<_FakePlayer>(
      currentPlayer: () => currentPlayer,
    );
    final first = _FakePlayer('first');
    final second = _FakePlayer('second');
    final firstOpenStarted = Completer<void>();
    final releaseFirstOpen = Completer<void>();
    final opened = <String>[];
    final initialized = <String>[];
    var firstDiscarded = 0;
    var secondDiscarded = 0;

    final firstResult = coordinator.openSource(
      owner: Object(),
      prepare: (_) async {
        currentPlayer = first;
        return _prepared(
          player: first,
          currentPlayer: () => currentPlayer,
          onEvent: (_) {},
          open: () async {
            firstOpenStarted.complete();
            await releaseFirstOpen.future;
          },
          didOpen: () => opened.add(first.name),
          initialize: () async => initialized.add(first.name),
          discard: () => firstDiscarded++,
        );
      },
    );
    await firstOpenStarted.future;

    final secondResult = coordinator.openSource(
      owner: Object(),
      prepare: (_) async {
        currentPlayer = second;
        return _prepared(
          player: second,
          currentPlayer: () => currentPlayer,
          onEvent: (_) {},
          didOpen: () => opened.add(second.name),
          initialize: () async => initialized.add(second.name),
          discard: () => secondDiscarded++,
        );
      },
    );

    releaseFirstOpen.complete();
    expect(await firstResult, isFalse);
    expect(await secondResult, isTrue);
    expect(opened, ['second']);
    expect(initialized, ['second']);
    expect(firstDiscarded, 1);
    expect(secondDiscarded, 0);

    await first.dispose();
    await second.dispose();
  });

  for (final stage in ['prepare', 'open', 'initialize']) {
    test('a never-completing $stage cannot block a replacement', () async {
      _FakePlayer? currentPlayer;
      final coordinator = PlPlayerSourceCoordinator<_FakePlayer>(
        currentPlayer: () => currentPlayer,
        timeouts: _shortTimeouts,
      );
      final first = _FakePlayer('first-$stage');
      final second = _FakePlayer('second-$stage');
      final stageStarted = Completer<void>();
      final never = Completer<void>();
      var aborted = 0;

      final firstResult = coordinator.openSource(
        owner: Object(),
        prepare: (attempt) async {
          attempt.registerAbort(() => aborted++);
          currentPlayer = first;
          if (stage == 'prepare') {
            stageStarted.complete();
            await never.future;
          }
          return _prepared(
            player: first,
            currentPlayer: () => currentPlayer,
            onEvent: (_) {},
            open: stage == 'open'
                ? () async {
                    stageStarted.complete();
                    await never.future;
                  }
                : null,
            initialize: stage == 'initialize'
                ? () async {
                    stageStarted.complete();
                    await never.future;
                  }
                : null,
            discard: attempt.abort,
          );
        },
      );
      await stageStarted.future;

      final secondResult = coordinator.openSource(
        owner: Object(),
        prepare: (_) async {
          currentPlayer = second;
          return _prepared(
            player: second,
            currentPlayer: () => currentPlayer,
            onEvent: (_) {},
          );
        },
      );

      expect(await firstResult, isFalse);
      expect(await secondResult, isTrue);
      expect(aborted, 1);

      await first.dispose();
      await second.dispose();
    });
  }

  test('a current open timeout aborts instead of blocking forever', () async {
    _FakePlayer? currentPlayer;
    final coordinator = PlPlayerSourceCoordinator<_FakePlayer>(
      currentPlayer: () => currentPlayer,
      timeouts: _shortTimeouts,
    );
    final player = _FakePlayer('timeout');
    final never = Completer<void>();
    var aborted = 0;
    currentPlayer = player;

    final result = await coordinator.openSource(
      owner: Object(),
      prepare: (attempt) async {
        attempt.registerAbort(() => aborted++);
        return _prepared(
          player: player,
          currentPlayer: () => currentPlayer,
          onEvent: (_) {},
          open: () => never.future,
          discard: attempt.abort,
        );
      },
    );

    expect(result, isFalse);
    expect(aborted, 1);
    expect(coordinator.activeLease(), isNull);
    await player.dispose();
  });

  test('listener subscriptions reject events from the old source', () async {
    _FakePlayer? currentPlayer;
    final coordinator = PlPlayerSourceCoordinator<_FakePlayer>(
      currentPlayer: () => currentPlayer,
    );
    final first = _FakePlayer('first');
    final second = _FakePlayer('second');
    final received = <String>[];

    Future<bool> open(
      _FakePlayer player, {
      Future<void> Function()? openSource,
    }) => coordinator.openSource(
      owner: Object(),
      prepare: (_) async {
        currentPlayer = player;
        return _prepared(
          player: player,
          currentPlayer: () => currentPlayer,
          onEvent: received.add,
          open: openSource,
        );
      },
    );

    final firstOpenStarted = Completer<void>();
    final releaseFirstOpen = Completer<void>();
    final firstOpening = open(
      first,
      openSource: () async {
        firstOpenStarted.complete();
        await releaseFirstOpen.future;
      },
    );
    await firstOpenStarted.future;
    first.events.add('during-open');
    expect(received, isEmpty);
    releaseFirstOpen.complete();
    expect(await firstOpening, isTrue);
    first.events.add('first-current');
    expect(received, ['first-current']);

    expect(await open(second), isTrue);
    first.events.add('first-stale');
    second.events.add('second-current');
    expect(received, ['first-current', 'second-current']);

    await first.dispose();
    await second.dispose();
  });

  test('refresh is serialized and cannot publish after replacement', () async {
    _FakePlayer? currentPlayer;
    final coordinator = PlPlayerSourceCoordinator<_FakePlayer>(
      currentPlayer: () => currentPlayer,
    );
    final first = _FakePlayer('first');
    final second = _FakePlayer('second');
    final refreshStarted = Completer<void>();
    final releaseRefresh = Completer<void>();
    var refreshPublished = false;

    currentPlayer = first;
    expect(
      await coordinator.openSource(
        owner: Object(),
        prepare: (_) async => _prepared(
          player: first,
          currentPlayer: () => currentPlayer,
          onEvent: (_) {},
        ),
      ),
      isTrue,
    );

    final refresh = coordinator.refresh(
      open: (_) async {
        refreshStarted.complete();
        await releaseRefresh.future;
        return true;
      },
      didOpen: (_) => refreshPublished = true,
    );
    await refreshStarted.future;

    final replacement = coordinator.openSource(
      owner: Object(),
      prepare: (_) async {
        currentPlayer = second;
        return _prepared(
          player: second,
          currentPlayer: () => currentPlayer,
          onEvent: (_) {},
        );
      },
    );
    releaseRefresh.complete();

    expect(await refresh, isFalse);
    expect(refreshPublished, isFalse);
    expect(await replacement, isTrue);

    await first.dispose();
    await second.dispose();
  });

  test('a never-completing refresh cannot block a replacement', () async {
    _FakePlayer? currentPlayer;
    final coordinator = PlPlayerSourceCoordinator<_FakePlayer>(
      currentPlayer: () => currentPlayer,
      timeouts: _shortTimeouts,
    );
    final first = _FakePlayer('refresh-first');
    final second = _FakePlayer('refresh-second');
    final refreshStarted = Completer<void>();
    final never = Completer<void>();
    var aborted = 0;

    currentPlayer = first;
    expect(
      await coordinator.openSource(
        owner: Object(),
        prepare: (attempt) async {
          attempt.registerAbort(() {
            aborted++;
            if (identical(currentPlayer, first)) currentPlayer = null;
          });
          return _prepared(
            player: first,
            currentPlayer: () => currentPlayer,
            onEvent: (_) {},
            discard: attempt.abort,
          );
        },
      ),
      isTrue,
    );

    final refresh = coordinator.refresh(
      open: (_) async {
        refreshStarted.complete();
        await never.future;
        return true;
      },
      didOpen: (_) => fail('stale refresh published'),
    );
    await refreshStarted.future;

    final replacement = coordinator.openSource(
      owner: Object(),
      prepare: (_) async {
        currentPlayer = second;
        return _prepared(
          player: second,
          currentPlayer: () => currentPlayer,
          onEvent: (_) {},
        );
      },
    );

    expect(await refresh, isFalse);
    expect(await replacement, isTrue);
    expect(aborted, 1);
    await first.dispose();
    await second.dispose();
  });

  test('a never-completing discard is bounded for the replacement', () async {
    _FakePlayer? currentPlayer;
    final coordinator = PlPlayerSourceCoordinator<_FakePlayer>(
      currentPlayer: () => currentPlayer,
      timeouts: _shortTimeouts,
    );
    final first = _FakePlayer('discard-first');
    final second = _FakePlayer('discard-second');
    final openStarted = Completer<void>();
    final neverOpen = Completer<void>();
    final neverDiscard = Completer<void>();
    var discardStarted = 0;

    final firstResult = coordinator.openSource(
      owner: Object(),
      prepare: (_) async {
        currentPlayer = first;
        return _prepared(
          player: first,
          currentPlayer: () => currentPlayer,
          onEvent: (_) {},
          open: () async {
            openStarted.complete();
            await neverOpen.future;
          },
          discard: () async {
            discardStarted++;
            await neverDiscard.future;
          },
        );
      },
    );
    await openStarted.future;

    final replacement = coordinator.openSource(
      owner: Object(),
      prepare: (_) async {
        currentPlayer = second;
        return _prepared(
          player: second,
          currentPlayer: () => currentPlayer,
          onEvent: (_) {},
        );
      },
    );

    expect(await firstResult, isFalse);
    expect(await replacement, isTrue);
    expect(discardStarted, 1);
    await first.dispose();
    await second.dispose();
  });

  test(
    'a failed initialization discards the preparation exactly once',
    () async {
      _FakePlayer? currentPlayer;
      final coordinator = PlPlayerSourceCoordinator<_FakePlayer>(
        currentPlayer: () => currentPlayer,
      );
      final player = _FakePlayer('failed');
      var discarded = 0;
      var errors = 0;
      var timerRan = false;
      currentPlayer = player;

      final result = await coordinator.openSource(
        owner: Object(),
        prepare: (_) async => _prepared(
          player: player,
          currentPlayer: () => currentPlayer,
          onEvent: (_) {},
          initialize: () {
            coordinator.trackSourceTimer(
              Timer(
                const Duration(milliseconds: 20),
                () => timerRan = true,
              ),
            );
            return Future<void>.error(StateError('init failed'));
          },
          discard: () => discarded++,
        ),
        onError: (_, _, _) {
          errors++;
          throw StateError('error callback failed');
        },
      );
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(result, isFalse);
      expect(discarded, 1);
      expect(errors, 1);
      expect(timerRan, isFalse);
      expect(coordinator.activeLease(), isNull);

      await player.dispose();
    },
  );

  test('retry keeps one deadline and is cancelled by a new source', () async {
    _FakePlayer? currentPlayer;
    final coordinator = PlPlayerSourceCoordinator<_FakePlayer>(
      currentPlayer: () => currentPlayer,
    );
    final first = _FakePlayer('first');
    final second = _FakePlayer('second');
    currentPlayer = first;
    expect(
      await coordinator.openSource(
        owner: Object(),
        prepare: (_) async => _prepared(
          player: first,
          currentPlayer: () => currentPlayer,
          onEvent: (_) {},
        ),
      ),
      isTrue,
    );

    final lease = coordinator.activeLease()!;
    var retries = 0;
    coordinator
      ..scheduleRetry(
        lease,
        const Duration(milliseconds: 10),
        (_) => retries++,
      )
      ..scheduleRetry(
        lease,
        Duration.zero,
        (_) => retries += 100,
      );
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(retries, 1);

    coordinator.scheduleRetry(
      lease,
      const Duration(milliseconds: 30),
      (_) => retries += 10,
    );
    currentPlayer = second;
    expect(
      await coordinator.openSource(
        owner: Object(),
        prepare: (_) async => _prepared(
          player: second,
          currentPlayer: () => currentPlayer,
          onEvent: (_) {},
        ),
      ),
      isTrue,
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(retries, 1);

    await first.dispose();
    await second.dispose();
  });

  test('an error during an in-flight retry reserves one follow-up', () async {
    _FakePlayer? currentPlayer;
    final coordinator = PlPlayerSourceCoordinator<_FakePlayer>(
      currentPlayer: () => currentPlayer,
    );
    final player = _FakePlayer('retry-pending');
    currentPlayer = player;
    expect(
      await coordinator.openSource(
        owner: Object(),
        prepare: (_) async => _prepared(
          player: player,
          currentPlayer: () => currentPlayer,
          onEvent: (_) {},
        ),
      ),
      isTrue,
    );

    final lease = coordinator.activeLease()!;
    var retries = 0;
    late FutureOr<void> Function(PlPlayerSourceLease<_FakePlayer>) operation;
    operation = (retryLease) {
      retries++;
      if (retries == 1) {
        coordinator
          ..scheduleRetry(
            retryLease,
            Duration.zero,
            operation,
          )
          ..scheduleRetry(
            retryLease,
            Duration.zero,
            operation,
          );
      }
    };

    coordinator.scheduleRetry(lease, Duration.zero, operation);
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(retries, 2);
    await player.dispose();
  });

  test('a never-completing retry releases its reserved follow-up', () async {
    _FakePlayer? currentPlayer;
    final coordinator = PlPlayerSourceCoordinator<_FakePlayer>(
      currentPlayer: () => currentPlayer,
      timeouts: _shortTimeouts,
    );
    final player = _FakePlayer('retry-timeout');
    currentPlayer = player;
    expect(
      await coordinator.openSource(
        owner: Object(),
        prepare: (_) async => _prepared(
          player: player,
          currentPlayer: () => currentPlayer,
          onEvent: (_) {},
        ),
      ),
      isTrue,
    );

    final lease = coordinator.activeLease()!;
    final never = Completer<void>();
    var retries = 0;
    var errors = 0;
    late FutureOr<void> Function(PlPlayerSourceLease<_FakePlayer>) operation;
    operation = (retryLease) async {
      retries++;
      if (retries == 1) {
        coordinator.scheduleRetry(
          retryLease,
          Duration.zero,
          operation,
          onError: (_, _) => errors++,
        );
        await never.future;
      }
    };

    coordinator.scheduleRetry(
      lease,
      Duration.zero,
      operation,
      onError: (_, _) => errors++,
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(retries, 2);
    expect(errors, 1);
    await player.dispose();
  });

  test('a throwing retry error handler cannot block pending retry', () async {
    final zoneErrors = <Object>[];
    await runZonedGuarded<Future<void>>(
      () async {
        _FakePlayer? currentPlayer;
        final coordinator = PlPlayerSourceCoordinator<_FakePlayer>(
          currentPlayer: () => currentPlayer,
          timeouts: _shortTimeouts,
        );
        final player = _FakePlayer('retry-handler-error');
        currentPlayer = player;
        expect(
          await coordinator.openSource(
            owner: Object(),
            prepare: (_) async => _prepared(
              player: player,
              currentPlayer: () => currentPlayer,
              onEvent: (_) {},
            ),
          ),
          isTrue,
        );

        final lease = coordinator.activeLease()!;
        var retries = 0;
        late FutureOr<void> Function(PlPlayerSourceLease<_FakePlayer>)
        operation;
        operation = (_) {
          retries++;
          if (retries == 1) throw StateError('retry failed');
        };
        coordinator.scheduleRetry(
          lease,
          Duration.zero,
          operation,
          onError: (_, _) {
            coordinator.scheduleRetry(
              lease,
              Duration.zero,
              operation,
            );
            throw StateError('handler failed');
          },
        );
        await Future<void>.delayed(const Duration(milliseconds: 30));

        expect(retries, 2);
        await player.dispose();
      },
      (error, _) => zoneErrors.add(error),
    );
    expect(zoneErrors, hasLength(1));
  });

  test('dispose cancels listeners and tracked source timers', () async {
    _FakePlayer? currentPlayer;
    final coordinator = PlPlayerSourceCoordinator<_FakePlayer>(
      currentPlayer: () => currentPlayer,
    );
    final player = _FakePlayer('only');
    final received = <String>[];
    var timerRan = false;
    currentPlayer = player;
    expect(
      await coordinator.openSource(
        owner: Object(),
        prepare: (_) async => _prepared(
          player: player,
          currentPlayer: () => currentPlayer,
          onEvent: received.add,
        ),
      ),
      isTrue,
    );
    coordinator
      ..trackSourceTimer(
        Timer(const Duration(milliseconds: 20), () => timerRan = true),
      )
      ..dispose();
    player.events.add('stale');
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(received, isEmpty);
    expect(timerRan, isFalse);
    expect(coordinator.activeLease(), isNull);
    expect(
      () => coordinator.openSource(
        owner: Object(),
        prepare: (_) async => null,
      ),
      throwsStateError,
    );

    await player.dispose();
  });
}
