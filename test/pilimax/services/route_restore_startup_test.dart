import 'dart:async';

import 'package:PiliMax/pilimax/services/route_restore_startup.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RouteRestoreStartupCoordinator', () {
    test('registers one shared future and starts only once', () async {
      final coordinator = RouteRestoreStartupCoordinator<int>();
      final pending = Completer<int>();
      var starts = 0;

      final waiting = coordinator.future;
      final started = coordinator.start(() {
        starts++;
        return pending.future;
      });
      final duplicate = coordinator.start(() async {
        starts++;
        return 99;
      });

      expect(identical(waiting, started), isTrue);
      expect(identical(started, duplicate), isTrue);
      expect(starts, 1);
      pending.complete(7);
      expect(await Future.wait([waiting, started, duplicate]), [7, 7, 7]);
    });
  });

  group('RouteRestoreDecisionResolver', () {
    test('retries unavailable and preserves a later decision', () async {
      const resolver = RouteRestoreDecisionResolver(
        deadline: Duration(seconds: 1),
        retryDelays: [Duration.zero, Duration.zero],
      );
      final decisions = <RouteRestoreNativeDecision>[
        RouteRestoreNativeDecision.unavailable,
        RouteRestoreNativeDecision.restore,
      ];
      var queries = 0;

      final decision = await resolver.resolve(() async {
        queries++;
        return decisions.removeAt(0);
      });

      expect(decision, RouteRestoreNativeDecision.restore);
      expect(queries, 2);
    });

    test('uses one deadline for a query that never completes', () async {
      const resolver = RouteRestoreDecisionResolver(
        deadline: Duration(milliseconds: 20),
        retryDelays: [],
      );
      final stopwatch = Stopwatch()..start();

      final decision = await resolver.resolve(
        () => Completer<RouteRestoreNativeDecision>().future,
      );

      expect(decision, RouteRestoreNativeDecision.unavailable);
      expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 250)));
    });

    test('shares one deadline across queries and retry delays', () async {
      const resolver = RouteRestoreDecisionResolver(
        deadline: Duration(milliseconds: 300),
        retryDelays: [
          Duration(milliseconds: 180),
          Duration(milliseconds: 180),
        ],
      );
      var queries = 0;
      final stopwatch = Stopwatch()..start();

      final decision = await resolver.resolve(() async {
        queries++;
        return RouteRestoreNativeDecision.unavailable;
      });

      expect(decision, RouteRestoreNativeDecision.unavailable);
      expect(queries, 2);
      expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 330)));
    });

    test('stops after the configured retry sequence', () async {
      const resolver = RouteRestoreDecisionResolver(
        deadline: Duration(seconds: 1),
        retryDelays: [Duration.zero, Duration.zero],
      );
      var queries = 0;

      final decision = await resolver.resolve(() async {
        queries++;
        return RouteRestoreNativeDecision.unavailable;
      });

      expect(decision, RouteRestoreNativeDecision.unavailable);
      expect(queries, 3);
    });
  });

  test('missing stored state skips the native decision query', () async {
    var queries = 0;
    Future<RouteRestoreNativeDecision> query() async {
      queries++;
      return RouteRestoreNativeDecision.restore;
    }

    expect(
      await resolveRouteRestoreDecisionForStoredState(
        storedState: null,
        expectedVersion: 1,
        nowMilliseconds: 1000,
        query: query,
      ),
      isNull,
    );
    expect(queries, 0);

    final result = await resolveRouteRestoreDecisionForStoredState(
      storedState: '{"version":1,"time":123}',
      expectedVersion: 1,
      nowMilliseconds: 1000,
      query: query,
    );
    expect(result?.state, {'version': 1, 'time': 123});
    expect(result?.savedAt, 123);
    expect(result?.decision, RouteRestoreNativeDecision.restore);
    expect(queries, 1);
  });

  test('invalid stored state rejects without querying native state', () async {
    var queries = 0;
    Future<RouteRestoreNativeDecision> query() async {
      queries++;
      return RouteRestoreNativeDecision.restore;
    }

    for (final state in <Object?>[
      '',
      42,
      '{',
      '[]',
      '{"version":2,"time":123}',
      '{"version":1,"time":null}',
      '{"version":1,"time":0}',
      '{"version":1,"time":1001}',
      '{"version":1,"time":-1}',
      '{"version":1,"time":123}',
    ]) {
      final result = await resolveRouteRestoreDecisionForStoredState(
        storedState: state,
        expectedVersion: 1,
        nowMilliseconds: 1000,
        validDuration: const Duration(milliseconds: 100),
        query: query,
      );
      expect(result?.state, isNull);
      expect(result?.savedAt, isNull);
      expect(result?.decision, RouteRestoreNativeDecision.reject);
    }
    expect(queries, 0);
  });
}
