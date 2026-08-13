import 'dart:async';
import 'dart:convert';

enum RouteRestoreNativeDecision { restore, reject, unavailable }

final class RouteRestoreStartupCoordinator<T> {
  Completer<T>? _completer;
  bool _started = false;

  Future<T> get future => (_completer ??= Completer<T>()).future;

  Future<T> start(Future<T> Function() operation) {
    final completer = _completer ??= Completer<T>();
    if (_started) {
      return completer.future;
    }
    _started = true;
    Future<T>.sync(operation).then(
      completer.complete,
      onError: completer.completeError,
    );
    return completer.future;
  }
}

final class RouteRestoreDecisionResolver {
  const RouteRestoreDecisionResolver({
    this.deadline = const Duration(milliseconds: 600),
    this.retryDelays = const [
      Duration(milliseconds: 80),
      Duration(milliseconds: 160),
      Duration(milliseconds: 280),
    ],
  });

  final Duration deadline;
  final List<Duration> retryDelays;

  Future<RouteRestoreNativeDecision> resolve(
    Future<RouteRestoreNativeDecision> Function() query,
  ) async {
    final stopwatch = Stopwatch()..start();
    for (var attempt = 0; ; attempt++) {
      final remaining = deadline - stopwatch.elapsed;
      if (remaining <= Duration.zero) {
        return RouteRestoreNativeDecision.unavailable;
      }
      final decision =
          await Future<RouteRestoreNativeDecision>.sync(
            query,
          ).timeout(
            remaining,
            onTimeout: () => RouteRestoreNativeDecision.unavailable,
          );
      if (decision != RouteRestoreNativeDecision.unavailable ||
          attempt == retryDelays.length) {
        return decision;
      }

      final retryDelay = retryDelays[attempt];
      final delayBudget = deadline - stopwatch.elapsed;
      if (retryDelay >= delayBudget) {
        return RouteRestoreNativeDecision.unavailable;
      }
      await Future<void>.delayed(retryDelay);
    }
  }
}

Future<
  ({
    Map<String, dynamic>? state,
    int? savedAt,
    RouteRestoreNativeDecision decision,
  })?
>
resolveRouteRestoreDecisionForStoredState({
  required Object? storedState,
  required int expectedVersion,
  required Future<RouteRestoreNativeDecision> Function() query,
  int? nowMilliseconds,
  Duration validDuration = const Duration(hours: 24),
  RouteRestoreDecisionResolver resolver = const RouteRestoreDecisionResolver(),
}) async {
  if (storedState == null) {
    return null;
  }
  if (storedState is! String || storedState.isEmpty) {
    return (
      state: null,
      savedAt: null,
      decision: RouteRestoreNativeDecision.reject,
    );
  }

  final Map<String, dynamic> state;
  try {
    final decoded = jsonDecode(storedState);
    if (decoded is! Map) {
      return (
        state: null,
        savedAt: null,
        decision: RouteRestoreNativeDecision.reject,
      );
    }
    state = Map<String, dynamic>.from(decoded);
  } on FormatException {
    return (
      state: null,
      savedAt: null,
      decision: RouteRestoreNativeDecision.reject,
    );
  } on TypeError {
    return (
      state: null,
      savedAt: null,
      decision: RouteRestoreNativeDecision.reject,
    );
  }

  final savedAt = _parseStoredTimestamp(state['time']);
  final now = nowMilliseconds ?? DateTime.now().millisecondsSinceEpoch;
  if (state['version'] != expectedVersion ||
      savedAt == null ||
      savedAt <= 0 ||
      savedAt > now ||
      now - savedAt > validDuration.inMilliseconds) {
    return (
      state: null,
      savedAt: null,
      decision: RouteRestoreNativeDecision.reject,
    );
  }

  return (
    state: state,
    savedAt: savedAt,
    decision: await resolver.resolve(query),
  );
}

int? _parseStoredTimestamp(Object? value) => switch (value) {
  int() => value,
  num() when value.isFinite => value.toInt(),
  String() => int.tryParse(value),
  _ => null,
};
