abstract final class CacheAutoClearPeriod {
  static const int defaultDays = 3;
  static const List<int> allowedDays = [1, 3, 7, 15, 30];

  static int normalize(Object? value) =>
      value is int && allowedDays.contains(value) ? value : defaultDays;

  static Map<dynamic, dynamic> normalizedSettingsCopy(
    Map<dynamic, dynamic> source, {
    required Object periodKey,
  }) {
    return Map<dynamic, dynamic>.from(source)
      ..[periodKey] = normalize(source[periodKey]);
  }
}

enum AutoCacheClearDecision {
  disabled,
  initializeBaseline,
  resetClockBaseline,
  notDue,
  clear,
}

abstract final class AutoCacheClearPolicy {
  static AutoCacheClearDecision decide({
    required bool enabled,
    required int nowMilliseconds,
    required Object? lastClearMilliseconds,
    required int periodDays,
  }) {
    if (!enabled) {
      return AutoCacheClearDecision.disabled;
    }
    if (lastClearMilliseconds is! int || lastClearMilliseconds <= 0) {
      return AutoCacheClearDecision.initializeBaseline;
    }
    if (nowMilliseconds < lastClearMilliseconds) {
      return AutoCacheClearDecision.resetClockBaseline;
    }
    final period = Duration(
      days: CacheAutoClearPeriod.normalize(periodDays),
    ).inMilliseconds;
    return nowMilliseconds - lastClearMilliseconds >= period
        ? AutoCacheClearDecision.clear
        : AutoCacheClearDecision.notDue;
  }
}

enum CacheClearTarget { networkImages, appCache }

final class CacheClearResult {
  final Set<CacheClearTarget> succeededTargets;
  final Set<CacheClearTarget> failedTargets;

  const CacheClearResult({
    required this.succeededTargets,
    required this.failedTargets,
  });

  int get totalCount => succeededTargets.length + failedTargets.length;

  int get failedCount => failedTargets.length;

  bool get allSucceeded => succeededTargets.isNotEmpty && failedTargets.isEmpty;

  bool get partialFailure =>
      succeededTargets.isNotEmpty && failedTargets.isNotEmpty;

  bool get allFailed => succeededTargets.isEmpty && failedTargets.isNotEmpty;
}

typedef CacheClearTask = Future<void> Function();
typedef CacheClearErrorHandler =
    void Function(CacheClearTarget target, Object error, StackTrace stackTrace);

final class CacheClearCoordinator {
  Future<CacheClearResult>? _inFlight;

  Future<CacheClearResult> run(
    Map<CacheClearTarget, CacheClearTask> tasks, {
    CacheClearErrorHandler? onError,
  }) {
    final inFlight = _inFlight;
    if (inFlight != null) {
      return inFlight;
    }

    late final Future<CacheClearResult> operation;
    operation = _runTasks(tasks, onError).whenComplete(() {
      if (identical(_inFlight, operation)) {
        _inFlight = null;
      }
    });
    _inFlight = operation;
    return operation;
  }

  static Future<CacheClearResult> _runTasks(
    Map<CacheClearTarget, CacheClearTask> tasks,
    CacheClearErrorHandler? onError,
  ) async {
    final succeeded = <CacheClearTarget>{};
    final failed = <CacheClearTarget>{};
    for (final entry in tasks.entries) {
      try {
        await entry.value();
        succeeded.add(entry.key);
      } catch (error, stackTrace) {
        failed.add(entry.key);
        onError?.call(entry.key, error, stackTrace);
      }
    }
    return CacheClearResult(
      succeededTargets: Set.unmodifiable(succeeded),
      failedTargets: Set.unmodifiable(failed),
    );
  }
}
