import 'dart:async';

import 'package:PiliMax/pilimax/utils/accounts/anonymous_buvid_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepts only complete safe SPI identifier pairs', () {
    expect(_cookies('b3', 'b4')!.buvid4, 'b4');
    for (final response in [
      null,
      {
        'code': -1,
        'data': {'b_3': 'b3', 'b_4': 'b4'},
      },
      {
        'code': 0,
        'data': {'b_3': 'b3'},
      },
      {
        'code': 0,
        'data': {'b_3': 123, 'b_4': 'b4'},
      },
      {
        'code': 0,
        'data': {'b_3': '', 'b_4': 'b4'},
      },
      {
        'code': 0,
        'data': {'b_3': 'b3; other=value', 'b_4': 'b4'},
      },
      {
        'code': 0,
        'data': {'b_3': 'b3', 'b_4': 'bad\nvalue'},
      },
      {
        'code': 0,
        'data': {'b_3': 'b3', 'b_4': 'b4\n'},
      },
    ]) {
      expect(AnonymousBuvidCookies.fromResponse(response), isNull);
    }
  });

  test(
    'concurrent preparation fetches once and keeps fallback until complete',
    () async {
      final response = Completer<AnonymousBuvidCookies?>();
      var requests = 0;
      var value = 'fallback';
      final coordinator = AnonymousBuvidCoordinator(
        apply: (cookies) => value = '${cookies.buvid3}:${cookies.buvid4}',
        resetCookies: () async {},
      );
      Future<AnonymousBuvidCookies?> fetch() {
        requests++;
        return response.future;
      }

      final callers = List.generate(12, (_) => coordinator.ensure(fetch));
      expect(requests, 1);
      expect(value, 'fallback');
      response.complete(_cookies('b3', 'b4'));
      await Future.wait(callers);
      await coordinator.ensure(fetch);
      expect(requests, 1);
      expect(value, 'b3:b4');
    },
  );

  test('failed initialization keeps fallback without a retry storm', () async {
    var requests = 0;
    var applied = false;
    final coordinator = AnonymousBuvidCoordinator(
      apply: (_) => applied = true,
      resetCookies: () async {},
    );
    Future<AnonymousBuvidCookies?> fetch() {
      requests++;
      return Future.error(StateError('offline'));
    }

    await Future.wait(List.generate(8, (_) => coordinator.ensure(fetch)));
    await coordinator.ensure(fetch);
    expect(requests, 1);
    expect(applied, isFalse);
    await coordinator.reset();
    await coordinator.ensure(() async => _cookies('new3', 'new4'));
    expect(applied, isTrue);
  });

  test('clear releases old waiters and rejects late SPI data', () async {
    final oldResponse = Completer<AnonymousBuvidCookies?>();
    final clearRelease = Completer<void>();
    final newStarted = Completer<void>();
    var requests = 0;
    var value = 'fallback';
    final coordinator = AnonymousBuvidCoordinator(
      apply: (cookies) => value = cookies.buvid3,
      resetCookies: () async {
        await clearRelease.future;
        value = 'new-fallback';
      },
    );
    Future<AnonymousBuvidCookies?> fetch() async {
      if (++requests == 1) return oldResponse.future;
      newStarted.complete();
      return _cookies('new3', 'new4');
    }

    final oldCaller = coordinator.ensure(fetch);
    final clearing = coordinator.reset();
    final newCaller = coordinator.ensure(fetch);
    expect(coordinator.generation, 1);
    expect(requests, 1);
    clearRelease.complete();
    await clearing;
    await newStarted.future;
    await Future.wait([oldCaller, newCaller]);
    expect(value, 'new3');
    expect(requests, 2);
    oldResponse.complete(_cookies('old3', 'old4'));
    await Future<void>.delayed(Duration.zero);
    expect(value, 'new3');
  });

  test('repeated clears serialize before a new session is prepared', () async {
    final firstRelease = Completer<void>();
    final secondRelease = Completer<void>();
    final secondStarted = Completer<void>();
    var resets = 0;
    var requests = 0;
    final coordinator = AnonymousBuvidCoordinator(
      apply: (_) {},
      resetCookies: () async {
        if (++resets == 1) {
          await firstRelease.future;
        } else {
          secondStarted.complete();
          await secondRelease.future;
        }
      },
    );
    final first = coordinator.reset();
    final second = coordinator.reset();
    final caller = coordinator.ensure(() async {
      requests++;
      return _cookies('new3', 'new4');
    });
    expect(resets, 1);
    expect(requests, 0);
    firstRelease.complete();
    await first;
    await secondStarted.future;
    expect(requests, 0);
    secondRelease.complete();
    await Future.wait([second, caller]);
    expect(coordinator.generation, 2);
    expect(requests, 1);
  });
}

AnonymousBuvidCookies? _cookies(String b3, String b4) =>
    AnonymousBuvidCookies.fromResponse({
      'code': 0,
      'data': {'b_3': b3, 'b_4': b4},
    });
