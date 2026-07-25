import 'dart:async';

import 'package:PiliMax/utils/cache_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CacheAutoClearPeriod', () {
    test('accepts only the supported periods', () {
      for (final days in CacheAutoClearPeriod.allowedDays) {
        expect(CacheAutoClearPeriod.normalize(days), days);
      }

      for (final value in <Object?>[null, 0, 2, 31, '3', 3.0]) {
        expect(
          CacheAutoClearPeriod.normalize(value),
          CacheAutoClearPeriod.defaultDays,
        );
      }
    });

    test('normalizes a copy without mutating imported settings', () {
      const periodKey = 'autoClearCachePeriod';
      final source = <dynamic, dynamic>{periodKey: 99, 'other': true};

      final normalized = CacheAutoClearPeriod.normalizedSettingsCopy(
        source,
        periodKey: periodKey,
      );

      expect(source[periodKey], 99);
      expect(normalized[periodKey], CacheAutoClearPeriod.defaultDays);
      expect(normalized['other'], isTrue);
    });
  });

  group('AutoCacheClearPolicy', () {
    const day = Duration(days: 1);
    final now = DateTime(2026, 7, 25).millisecondsSinceEpoch;

    test('does nothing when automatic clearing is disabled', () {
      expect(
        AutoCacheClearPolicy.decide(
          enabled: false,
          nowMilliseconds: now,
          lastClearMilliseconds: 0,
          periodDays: 3,
        ),
        AutoCacheClearDecision.disabled,
      );
    });

    test('initializes a missing or malformed baseline without clearing', () {
      for (final baseline in <Object?>[null, 'bad', 0, -1]) {
        expect(
          AutoCacheClearPolicy.decide(
            enabled: true,
            nowMilliseconds: now,
            lastClearMilliseconds: baseline,
            periodDays: 3,
          ),
          AutoCacheClearDecision.initializeBaseline,
        );
      }
    });

    test('resets a future baseline after the clock moves backwards', () {
      expect(
        AutoCacheClearPolicy.decide(
          enabled: true,
          nowMilliseconds: now,
          lastClearMilliseconds: now + day.inMilliseconds,
          periodDays: 3,
        ),
        AutoCacheClearDecision.resetClockBaseline,
      );
    });

    test('clears only when the normalized period is due', () {
      expect(
        AutoCacheClearPolicy.decide(
          enabled: true,
          nowMilliseconds: now,
          lastClearMilliseconds: now - 3 * day.inMilliseconds + 1,
          periodDays: 3,
        ),
        AutoCacheClearDecision.notDue,
      );
      expect(
        AutoCacheClearPolicy.decide(
          enabled: true,
          nowMilliseconds: now,
          lastClearMilliseconds: now - 3 * day.inMilliseconds,
          periodDays: 3,
        ),
        AutoCacheClearDecision.clear,
      );
      expect(
        AutoCacheClearPolicy.decide(
          enabled: true,
          nowMilliseconds: now,
          lastClearMilliseconds: now - 2 * day.inMilliseconds,
          periodDays: 99,
        ),
        AutoCacheClearDecision.notDue,
      );
    });
  });

  group('CacheClearCoordinator', () {
    test('coalesces concurrent requests into the same operation', () async {
      final coordinator = CacheClearCoordinator();
      final release = Completer<void>();
      var networkRuns = 0;
      var appRuns = 0;
      final tasks = <CacheClearTarget, CacheClearTask>{
        CacheClearTarget.networkImages: () async {
          networkRuns++;
          await release.future;
        },
        CacheClearTarget.appCache: () async {
          appRuns++;
        },
      };

      final first = coordinator.run(tasks);
      final second = coordinator.run(tasks);

      expect(identical(first, second), isTrue);
      expect(networkRuns, 1);
      expect(appRuns, 0);

      release.complete();
      final result = await first;
      expect(result.allSucceeded, isTrue);
      expect(result.totalCount, 2);
      expect(networkRuns, 1);
      expect(appRuns, 1);

      await coordinator.run(tasks);
      expect(networkRuns, 2);
      expect(appRuns, 2);
    });

    test('isolates target failures and reports a partial result', () async {
      final coordinator = CacheClearCoordinator();
      final reportedTargets = <CacheClearTarget>[];
      var appCacheCleared = false;

      final result = await coordinator.run(
        {
          CacheClearTarget.networkImages: () =>
              Future.error(StateError('network cache failed')),
          CacheClearTarget.appCache: () {
            appCacheCleared = true;
            return Future.value();
          },
        },
        onError: (target, _, _) => reportedTargets.add(target),
      );

      expect(appCacheCleared, isTrue);
      expect(result.partialFailure, isTrue);
      expect(result.allSucceeded, isFalse);
      expect(result.allFailed, isFalse);
      expect(result.failedCount, 1);
      expect(result.failedTargets, {CacheClearTarget.networkImages});
      expect(reportedTargets, [CacheClearTarget.networkImages]);
    });

    test('distinguishes complete failure from complete success', () async {
      final failed = await CacheClearCoordinator().run({
        CacheClearTarget.networkImages: () => Future.error(StateError('first')),
        CacheClearTarget.appCache: () => Future.error(StateError('second')),
      });
      final succeeded = await CacheClearCoordinator().run({
        CacheClearTarget.networkImages: Future.value,
        CacheClearTarget.appCache: Future.value,
      });

      expect(failed.allFailed, isTrue);
      expect(failed.failedCount, 2);
      expect(succeeded.allSucceeded, isTrue);
      expect(succeeded.failedCount, 0);
    });
  });
}
