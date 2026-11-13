import 'dart:async';

/// Web cookie identifiers returned by SPI, independent of the app/gRPC buvid.
final class AnonymousBuvidCookies {
  const AnonymousBuvidCookies._(this.buvid3, this.buvid4);

  final String buvid3;
  final String buvid4;

  // RFC 6265 cookie-octet. Reject separators, whitespace and control characters
  // before replacing any cookie in the current anonymous session.
  static final _cookieValue = RegExp(
    r'^[\x21\x23-\x2b\x2d-\x3a\x3c-\x5b\x5d-\x7e]{1,1024}$',
  );

  static bool _isCookieValue(String value) =>
      _cookieValue.matchAsPrefix(value)?.end == value.length;

  static AnonymousBuvidCookies? fromResponse(Object? response) {
    if (response is! Map || response['code'] != 0) return null;
    final data = response['data'];
    if (data is! Map) return null;
    final b3 = data['b_3'];
    final b4 = data['b_4'];
    if (b3 is! String ||
        b4 is! String ||
        !_isCookieValue(b3) ||
        !_isCookieValue(b4)) {
      return null;
    }
    return AnonymousBuvidCookies._(b3, b4);
  }
}

typedef AnonymousBuvidFetcher = Future<AnonymousBuvidCookies?> Function();

/// Coalesces one SPI attempt per anonymous session, keeping fallback cookies if
/// it fails. A reset invalidates old responses immediately and serializes jar
/// clearing before requests in the new session are allowed to continue.
final class AnonymousBuvidCoordinator {
  AnonymousBuvidCoordinator({
    required this.apply,
    required this.resetCookies,
  });

  final void Function(AnonymousBuvidCookies cookies) apply;
  final Future<void> Function() resetCookies;
  int _generation = 0;
  Completer<void> _invalidated = Completer<void>();
  Future<void>? _inFlight;
  Future<void>? _resetBarrier;

  int get generation => _generation;

  Future<void> ensure(AnonymousBuvidFetcher fetch) async {
    while (true) {
      final barrier = _resetBarrier;
      if (barrier != null) {
        await barrier;
        continue;
      }
      final generation = _generation;
      final invalidated = _invalidated.future;
      final pending = _inFlight ??= _fetchAndApply(fetch, generation);
      // Clearing the session releases existing callers immediately; they wait
      // for the new jar and share its attempt instead of waiting on stale I/O.
      await Future.any([pending, invalidated]);
      if (generation == _generation && _resetBarrier == null) return;
    }
  }

  Future<void> _fetchAndApply(
    AnonymousBuvidFetcher fetch,
    int generation,
  ) async {
    try {
      final cookies = await fetch();
      if (generation == _generation && cookies != null) apply(cookies);
    } catch (_) {
      // A bounded failed attempt keeps the locally generated fallback. Do not
      // retry on every request, or expose SPI/cookie data through error logs.
    }
  }

  Future<void> reset() {
    _generation++;
    _inFlight = null;
    final invalidated = _invalidated;
    _invalidated = Completer<void>();
    invalidated.complete();
    final previous = _resetBarrier;
    final operation = previous == null
        ? Future<void>.sync(resetCookies)
        : previous.then(
            (_) => resetCookies(),
            onError: (Object _, StackTrace _) => resetCookies(),
          );
    late final Future<void> barrier;
    barrier = operation.whenComplete(() {
      if (identical(_resetBarrier, barrier)) _resetBarrier = null;
    });
    _resetBarrier = barrier;
    return barrier;
  }
}
